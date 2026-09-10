#!/usr/bin/env python3
# Copyright 2026 Schwarz Digits Cloud GmbH & Co. KG
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""
STACKIT Reactive Policy Engine Runner
Periodically audits STACKIT infrastructure against declarative SCP guardrail policies.
Supports both 'audit' (log/alert only) and 'remediate' (active enforcement) modes.
Uses the official STACKIT Python SDK (stackit-sdk-python).
"""

import json
import logging
import os
import sys
import datetime
import shutil
import tempfile
import subprocess

try:
    from stackit.core.configuration import Configuration
    from stackit.iaas.api.default_api import DefaultApi as IaaSApi
    from stackit.authorization.api.default_api import DefaultApi as AuthorizationApi
    from stackit.authorization.models.remove_members_payload import RemoveMembersPayload
    from stackit.authorization.models.member import Member

    HAS_STACKIT_SDK = True
except ImportError:
    HAS_STACKIT_SDK = False

CONFIG_PATH = os.getenv("CONFIG_PATH", "/etc/stackit-policy-engine/config.json")
POLICIES_DIR = os.getenv("POLICIES_DIR", "/etc/stackit-policy-engine/policies")
LOG_FILE = os.getenv("LOG_PATH", "/var/log/stackit-policy-engine/audit.log")
METRICS_DIR = os.getenv("METRICS_DIR", "/var/lib/prometheus/node-exporter")
METRICS_FILE = os.path.join(METRICS_DIR, "policy_engine.prom")
OPA_BIN = shutil.which("opa") or "/usr/local/bin/opa"

RUN_ENV = os.environ.copy()
if not RUN_ENV.get("HOME"):
    RUN_ENV["HOME"] = "/root"
if not RUN_ENV.get("XDG_CONFIG_HOME"):
    RUN_ENV["XDG_CONFIG_HOME"] = "/root/.config"


def load_config():
    if os.path.exists(CONFIG_PATH):
        with open(CONFIG_PATH, "r") as f:
            return json.load(f)
    return {
        "project_id": os.getenv("STACKIT_PROJECT_ID", ""),
        "service_account_key_path": os.getenv("STACKIT_SERVICE_ACCOUNT_KEY_PATH", ""),
        "enforcement_mode": os.getenv("ENFORCEMENT_MODE", "remediate"),
        "allowed_machine_types": ["g2i.1", "g2i.2", "c2i.2", "c2i.4"],
        "mandatory_tags": ["environment", "owner", "cost-center"],
        "whitelisted_admin_subjects": [],
        "region": os.getenv("STACKIT_REGION", "eu01"),
    }


def setup_logger():
    logger = logging.getLogger("stackit_policy_engine")
    logger.setLevel(logging.INFO)
    logger.propagate = False

    if not logger.handlers:
        formatter = logging.Formatter("%(message)s")

        console_handler = logging.StreamHandler(sys.stdout)
        console_handler.setFormatter(formatter)
        logger.addHandler(console_handler)

        try:
            os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)
            file_handler = logging.FileHandler(LOG_FILE)
            file_handler.setFormatter(formatter)
            logger.addHandler(file_handler)
        except Exception as e:
            sys.stderr.write(f"Failed to create file handler for {LOG_FILE}: {e}\n")

    return logger


logger = setup_logger()


def log_audit(event_type, details):
    entry = {
        "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "event_type": event_type,
        "details": details,
    }
    logger.info(json.dumps(entry))


def get_sdk_config(config):
    if not HAS_STACKIT_SDK:
        return None
    sa_key_path = config.get(
        "service_account_key_path", "/etc/stackit-policy-engine/sa-key.json"
    )
    if sa_key_path and os.path.exists(sa_key_path):
        log_audit("AUTH_STEP", {"status": "AUTHENTICATING", "sa_key_path": sa_key_path})
        try:
            sdk_config = Configuration(service_account_key_path=sa_key_path)
            log_audit("AUTH_SUCCESS", {"sa_key_path": sa_key_path})
            return sdk_config
        except Exception as err:
            log_audit("AUTH_ERROR", {"error": str(err)})
            return Configuration()
    else:
        log_audit(
            "AUTH_SKIP",
            {
                "reason": f"Service account key not found at {sa_key_path}, using default Configuration"
            },
        )
        return Configuration()


def get_stackit_resources(config):
    """
    Retrieves current resource configuration from STACKIT APIs using stackit-sdk-python.
    Returns input structure matching Rego policy schemas.
    """
    project_id = config.get("project_id")
    region = config.get("region") or os.getenv("STACKIT_REGION", "eu01")
    sa_key_path = config.get(
        "service_account_key_path", "/etc/stackit-policy-engine/sa-key.json"
    )

    log_audit(
        "RESOURCE_DISCOVERY_START",
        {"project_id": project_id, "sa_key_path": sa_key_path, "region": region},
    )

    # If cached state file exists (for local testing/validation)
    if os.path.exists("/var/run/stackit-state.json"):
        try:
            with open("/var/run/stackit-state.json", "r") as f:
                state = json.load(f)
                log_audit(
                    "RESOURCE_DISCOVERY_CACHED",
                    {"source": "/var/run/stackit-state.json"},
                )
                return state
        except Exception as err:
            log_audit("STATE_READ_ERROR", {"error": str(err)})

    if not HAS_STACKIT_SDK:
        log_audit(
            "SDK_MISSING_ERROR",
            {"error": "stackit-sdk-python modules are not installed"},
        )

    sdk_config = get_sdk_config(config)

    servers = []
    public_ips = []
    volumes = []
    role_bindings = []

    if project_id and HAS_STACKIT_SDK:
        iaas_client = None
        auth_client = None

        try:
            iaas_client = IaaSApi(sdk_config)
        except Exception as err:
            log_audit("IAAS_CLIENT_INIT_ERROR", {"error": str(err)})

        try:
            auth_client = AuthorizationApi(sdk_config)
        except Exception as err:
            log_audit("AUTH_CLIENT_INIT_ERROR", {"error": str(err)})

        if iaas_client:
            # Query Public IPs via STACKIT SDK
            log_audit(
                "RESOURCE_FETCH_STEP",
                {"resource_type": "public_ip", "status": "IN_PROGRESS"},
            )
            try:
                res = iaas_client.list_public_ips(project_id=project_id, region=region)
                items = res.items if hasattr(res, "items") and res.items else []
                public_ips = [
                    item.model_dump(mode="json", by_alias=True) for item in items
                ]
                log_audit(
                    "RESOURCE_FETCH_SUCCESS",
                    {
                        "resource_type": "public_ip",
                        "count": len(public_ips),
                        "items": [
                            {
                                "id": str(ip.get("id") or ip.get("publicIpId") or ""),
                                "ip": ip.get("ip") or ip.get("address"),
                                "labels": ip.get("labels"),
                            }
                            for ip in public_ips
                        ],
                    },
                )
            except Exception as err:
                log_audit("FETCH_PUBLIC_IPS_ERROR", {"error": str(err)})

            # Query Servers via STACKIT SDK
            log_audit(
                "RESOURCE_FETCH_STEP",
                {"resource_type": "server", "status": "IN_PROGRESS"},
            )
            try:
                res = iaas_client.list_servers(project_id=project_id, region=region)
                items = res.items if hasattr(res, "items") and res.items else []
                servers = [
                    item.model_dump(mode="json", by_alias=True) for item in items
                ]
                log_audit(
                    "RESOURCE_FETCH_SUCCESS",
                    {
                        "resource_type": "server",
                        "count": len(servers),
                        "items": [
                            {
                                "id": str(s.get("id") or s.get("serverId") or ""),
                                "name": s.get("name"),
                                "machine_type": s.get("machine_type")
                                or s.get("machineType"),
                                "labels": s.get("labels"),
                            }
                            for s in servers
                        ],
                    },
                )
            except Exception as err:
                log_audit("FETCH_SERVERS_ERROR", {"error": str(err)})

            # Query Volumes via STACKIT SDK
            log_audit(
                "RESOURCE_FETCH_STEP",
                {"resource_type": "volume", "status": "IN_PROGRESS"},
            )
            try:
                res = iaas_client.list_volumes(project_id=project_id, region=region)
                items = res.items if hasattr(res, "items") and res.items else []
                volumes = [
                    item.model_dump(mode="json", by_alias=True) for item in items
                ]
                log_audit(
                    "RESOURCE_FETCH_SUCCESS",
                    {
                        "resource_type": "volume",
                        "count": len(volumes),
                        "items": [
                            {
                                "id": str(v.get("id") or v.get("volumeId") or ""),
                                "name": v.get("name"),
                                "labels": v.get("labels"),
                            }
                            for v in volumes
                        ],
                    },
                )
            except Exception as err:
                log_audit("FETCH_VOLUMES_ERROR", {"error": str(err)})

        if auth_client:
            # Query Role Bindings / Members via STACKIT Authorization SDK
            log_audit(
                "RESOURCE_FETCH_STEP",
                {"resource_type": "role_binding", "status": "IN_PROGRESS"},
            )
            try:
                res = auth_client.list_members(
                    resource_type="project", resource_id=project_id
                )
                members = res.members if hasattr(res, "members") and res.members else []
                role_bindings = [
                    m.model_dump(mode="json", by_alias=True) for m in members
                ]
                log_audit(
                    "RESOURCE_FETCH_SUCCESS",
                    {"resource_type": "role_binding", "count": len(role_bindings)},
                )
            except Exception as err:
                log_audit("FETCH_ROLE_BINDINGS_ERROR", {"error": str(err)})

    # Normalize fields for OPA Rego schema expectations
    for ip in public_ips:
        if "publicIpId" in ip and "id" not in ip:
            ip["id"] = ip["publicIpId"]
        if "ip" not in ip and "address" in ip:
            ip["ip"] = ip["address"]

    for s in servers:
        if "serverId" in s and "id" not in s:
            s["id"] = s["serverId"]
        if "machineType" in s and "machine_type" not in s:
            s["machine_type"] = s["machineType"]

    for v in volumes:
        if "volumeId" in v and "id" not in v:
            v["id"] = v["volumeId"]

    log_audit(
        "RESOURCE_DISCOVERY_SUMMARY",
        {
            "servers_count": len(servers),
            "public_ips_count": len(public_ips),
            "volumes_count": len(volumes),
            "role_bindings_count": len(role_bindings),
        },
    )

    input_payload = {
        "project_id": project_id,
        "allowed_machine_types": config.get("allowed_machine_types", []),
        "mandatory_tags": config.get("mandatory_tags", []),
        "whitelisted_admin_subjects": config.get("whitelisted_admin_subjects", []),
        "servers": servers,
        "public_ips": public_ips,
        "volumes": volumes,
        "role_bindings": role_bindings,
    }
    return input_payload


def extract_violations(res):
    """
    Recursively traverses OPA evaluation result structure to extract all policy violation entries.
    Handles nested package results like {"public_ips": {"violations": [...]}}.
    """
    violations = []
    if isinstance(res, dict):
        if "violations" in res and isinstance(res["violations"], list):
            violations.extend(res["violations"])
        for val in res.values():
            if isinstance(val, (dict, list)):
                violations.extend(extract_violations(val))
    elif isinstance(res, list):
        for item in res:
            if isinstance(item, (dict, list)):
                violations.extend(extract_violations(item))
    return violations


def evaluate_policy_opa(policy_file, input_data):
    """
    Evaluates OPA Rego policy file with input_data.
    """
    policy_name = os.path.basename(policy_file)
    log_audit("POLICY_EVAL_START", {"policy_file": policy_name, "evaluator": "OPA"})
    tmp_path = None
    try:
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as tmp:
            json.dump(input_data, tmp)
            tmp_path = tmp.name

        cmd = [
            OPA_BIN,
            "eval",
            "--format",
            "pretty",
            "--data",
            policy_file,
            "--input",
            tmp_path,
            "data.stackit.scp",
        ]
        res = subprocess.run(
            cmd, capture_output=True, text=True, timeout=10, env=RUN_ENV
        )
        if res.returncode == 0 and res.stdout:
            try:
                parsed = json.loads(res.stdout)
                log_audit(
                    "POLICY_EVAL_SUCCESS",
                    {"policy_file": policy_name, "evaluator": "OPA"},
                )
                return parsed
            except Exception as e:
                log_audit(
                    "POLICY_EVAL_PARSE_ERROR",
                    {
                        "policy_file": policy_name,
                        "error": str(e),
                        "raw_output": res.stdout,
                    },
                )
                return {"raw_output": res.stdout}
        else:
            log_audit(
                "POLICY_EVAL_OPA_FAILED",
                {
                    "policy_file": policy_name,
                    "exit_code": res.returncode,
                    "stderr": res.stderr.strip(),
                },
            )
            return run_fallback_evaluator(policy_file, input_data)
    except FileNotFoundError:
        log_audit(
            "POLICY_EVAL_OPA_NOT_FOUND",
            {
                "policy_file": policy_name,
                "notice": "OPA binary missing, switching to python fallback",
            },
        )
        return run_fallback_evaluator(policy_file, input_data)
    except Exception as e:
        log_audit("OPA_EVAL_ERROR", {"policy": policy_file, "error": str(e)})
        return run_fallback_evaluator(policy_file, input_data)
    finally:
        if tmp_path and os.path.exists(tmp_path):
            try:
                os.remove(tmp_path)
            except Exception:
                pass


def run_fallback_evaluator(policy_file, input_data):
    """
    Fallback python logic matching the Rego rule logic if OPA binary is missing.
    """
    policy_name = os.path.basename(policy_file)
    log_audit(
        "POLICY_EVAL_FALLBACK_START",
        {"policy_file": policy_name, "evaluator": "python_fallback"},
    )
    violations = []

    # Policy 1: No Public IPs
    if "scp_no_public_ips" in policy_file:
        for ip in input_data.get("public_ips", []):
            labels = ip.get("labels") or {}
            if labels.get("allow-public-ip") != "true":
                violations.append(
                    {
                        "id": ip.get("id"),
                        "ip": ip.get("ip"),
                        "resource_type": "public_ip",
                        "policy": "SCP-01-NO-PUBLIC-IPS",
                        "severity": "HIGH",
                        "reason": f"Public IP {ip.get('id')} ({ip.get('ip')}) not approved with 'allow-public-ip=true'",
                        "remediation_action": "delete_public_ip",
                    }
                )

    # Policy 2: Allowed Machine Types / Flavors
    if "scp_allowed_flavors" in policy_file:
        allowed = set(input_data.get("allowed_machine_types", []))
        for server in input_data.get("servers", []):
            m_type = server.get("machine_type") or server.get("machineType")
            if m_type and m_type not in allowed:
                violations.append(
                    {
                        "id": server.get("id"),
                        "name": server.get("name"),
                        "resource_type": "server",
                        "policy": "SCP-02-ALLOWED-FLAVORS",
                        "severity": "CRITICAL",
                        "reason": f"Server '{server.get('name')}' uses disallowed machine type '{m_type}'",
                        "remediation_action": "stop_server",
                    }
                )

    # Policy 3: Mandatory Tags
    if "scp_mandatory_tags" in policy_file:
        req_tags = input_data.get("mandatory_tags", [])
        for server in input_data.get("servers", []):
            s_labels = server.get("labels") or {}
            missing = [t for t in req_tags if not s_labels.get(t)]
            if missing:
                violations.append(
                    {
                        "id": server.get("id"),
                        "name": server.get("name"),
                        "resource_type": "server",
                        "policy": "SCP-03-MANDATORY-TAGS",
                        "severity": "MEDIUM",
                        "reason": f"Server '{server.get('name')}' missing tags: {missing}",
                        "remediation_action": "quarantine_or_notify",
                    }
                )

    # Policy 4: Volume Encryption
    if "scp_volume_encryption" in policy_file:
        for vol in input_data.get("volumes", []):
            if not vol.get("kms_key_id") and not vol.get("encrypted"):
                violations.append(
                    {
                        "id": vol.get("id"),
                        "name": vol.get("name"),
                        "resource_type": "volume",
                        "policy": "SCP-04-VOLUME-ENCRYPTION",
                        "severity": "HIGH",
                        "reason": f"Volume '{vol.get('name')}' is unencrypted",
                        "remediation_action": "detach_volume",
                    }
                )

    # Policy 5: IAM Admin Guardrails
    if "scp_iam_guardrails" in policy_file:
        whitelisted = set(input_data.get("whitelisted_admin_subjects", []))
        prohibited_roles = {"project.admin", "iam.admin"}
        for binding in input_data.get("role_bindings", []):
            role = binding.get("role")
            subj = binding.get("subject")
            if role in prohibited_roles and subj not in whitelisted:
                violations.append(
                    {
                        "id": f"{role}-{subj}",
                        "role": role,
                        "subject": subj,
                        "resource_type": "role_binding",
                        "policy": "SCP-05-IAM-ADMIN-GUARDRAIL",
                        "severity": "CRITICAL",
                        "reason": f"Subject '{subj}' holds prohibited admin role '{role}' without approval",
                        "remediation_action": "revoke_role_binding",
                    }
                )

    return {"violations": violations}


def remediate_violation(config, violation):
    """
    Executes reactive remediation against STACKIT API using stackit-sdk-python when enforcement_mode == 'remediate'.
    """
    action = violation.get("remediation_action")
    res_id = violation.get("id")
    res_type = violation.get("resource_type")
    project_id = config.get("project_id")
    region = config.get("region") or os.getenv("STACKIT_REGION", "eu01")

    log_audit(
        "REMEDIATION_TRIGGERED",
        {
            "action": action,
            "resource_id": res_id,
            "resource_type": res_type,
            "policy": violation.get("policy"),
        },
    )

    if not HAS_STACKIT_SDK:
        log_audit(
            "REMEDIATION_ACTION_EXEC",
            {
                "action": action,
                "status": "ERROR",
                "error": "stackit-sdk-python is not installed",
            },
        )
        return

    sdk_config = get_sdk_config(config)

    if action == "delete_public_ip" and res_id and project_id:
        try:
            iaas_client = IaaSApi(sdk_config)
            iaas_client.delete_public_ip(
                project_id=project_id, region=region, public_ip_id=res_id
            )
            log_audit(
                "REMEDIATION_ACTION_EXEC",
                {
                    "action": "delete_public_ip",
                    "public_ip_id": res_id,
                    "status": "SUCCESS",
                },
            )
        except Exception as err:
            log_audit(
                "REMEDIATION_ACTION_EXEC",
                {
                    "action": "delete_public_ip",
                    "public_ip_id": res_id,
                    "status": "ERROR",
                    "error": str(err),
                },
            )

    elif action == "stop_server" and res_id and project_id:
        try:
            iaas_client = IaaSApi(sdk_config)
            iaas_client.stop_server(
                project_id=project_id, region=region, server_id=res_id
            )
            log_audit(
                "REMEDIATION_ACTION_EXEC",
                {"action": "stop_server", "server_id": res_id, "status": "SUCCESS"},
            )
        except Exception as err:
            log_audit(
                "REMEDIATION_ACTION_EXEC",
                {
                    "action": "stop_server",
                    "server_id": res_id,
                    "status": "ERROR",
                    "error": str(err),
                },
            )

    elif action == "revoke_role_binding" and project_id:
        role = violation.get("role")
        subj = violation.get("subject")
        if role and subj:
            try:
                auth_client = AuthorizationApi(sdk_config)
                payload = RemoveMembersPayload(
                    members=[Member(role=role, subject=subj)],
                    resource_type="project",
                )
                auth_client.remove_members(
                    resource_id=project_id, remove_members_payload=payload
                )
                log_audit(
                    "REMEDIATION_ACTION_EXEC",
                    {
                        "action": "revoke_role_binding",
                        "binding": res_id,
                        "status": "SUCCESS",
                    },
                )
            except Exception as err:
                log_audit(
                    "REMEDIATION_ACTION_EXEC",
                    {
                        "action": "revoke_role_binding",
                        "binding": res_id,
                        "status": "ERROR",
                        "error": str(err),
                    },
                )
    else:
        log_audit(
            "REMEDIATION_ACTION_NOTICE", {"action": action, "status": "LOGGED_ONLY"}
        )


def get_rule_name(policy_file, violations=None):
    """
    Dynamically derives rule identifier from violation payload or policy file name.
    """
    if isinstance(violations, list):
        for v in violations:
            if isinstance(v, dict) and v.get("policy"):
                return v.get("policy")

    base_name = os.path.splitext(os.path.basename(policy_file))[0]
    return base_name.upper().replace("_", "-")


def export_prometheus_metrics(metrics_by_rule, project_id):
    """
    Writes policy violation metrics in Prometheus text format for node_exporter textfile collector.
    Exposes 'stackit_policy_engine_violations_found' with 'rule' label.
    """
    try:
        os.makedirs(METRICS_DIR, exist_ok=True)
        timestamp = int(datetime.datetime.now(datetime.timezone.utc).timestamp())

        lines = [
            "# HELP stackit_policy_engine_violations_found Number of policy violations found in the latest evaluation run.",
            "# TYPE stackit_policy_engine_violations_found gauge",
        ]

        for rule, count in metrics_by_rule.items():
            lines.append(
                f'stackit_policy_engine_violations_found{{rule="{rule}",project_id="{project_id}"}} {count}'
            )

        lines.extend(
            [
                "# HELP stackit_policy_engine_last_scan_timestamp_seconds Timestamp of the last policy engine scan in seconds.",
                "# TYPE stackit_policy_engine_last_scan_timestamp_seconds gauge",
                f'stackit_policy_engine_last_scan_timestamp_seconds{{project_id="{project_id}"}} {timestamp}',
            ]
        )

        tmp_file = METRICS_FILE + ".tmp"
        with open(tmp_file, "w") as f:
            f.write("\n".join(lines) + "\n")
        os.replace(tmp_file, METRICS_FILE)
        log_audit(
            "METRICS_EXPORT_SUCCESS",
            {"metrics_file": METRICS_FILE, "rules_count": len(metrics_by_rule)},
        )
    except Exception as err:
        log_audit("METRICS_EXPORT_ERROR", {"error": str(err)})


def main():
    config = load_config()
    project_id = config.get("project_id", "")
    if os.path.exists(POLICIES_DIR):
        policy_files = [
            os.path.join(POLICIES_DIR, f)
            for f in os.listdir(POLICIES_DIR)
            if f.endswith(".rego")
        ]
    else:
        policy_files = [
            "scp_no_public_ips.rego",
            "scp_allowed_flavors.rego",
            "scp_mandatory_tags.rego",
            "scp_volume_encryption.rego",
            "scp_iam_guardrails.rego",
        ]

    log_audit(
        "POLICY_SCAN_START",
        {
            "mode": config.get("enforcement_mode"),
            "project_id": project_id,
            "policies_count": len(policy_files),
            "policy_files": [os.path.basename(f) for f in policy_files],
        },
    )

    input_data = get_stackit_resources(config)

    total_violations = 0
    metrics_by_rule = {}

    for pf in policy_files:
        policy_name = os.path.basename(pf)
        res = evaluate_policy_opa(pf, input_data)
        violations = extract_violations(res)
        rule_violations = len(violations) if isinstance(violations, list) else 0

        rule_name = get_rule_name(pf, violations)
        metrics_by_rule[rule_name] = rule_violations

        log_audit(
            "POLICY_CHECK_STEP",
            {"policy_file": policy_name, "rule": rule_name, "status": "EVALUATING"},
        )
        log_audit(
            "POLICY_CHECK_SUMMARY",
            {
                "policy_file": policy_name,
                "rule": rule_name,
                "violations_found": rule_violations,
                "status": "NON_COMPLIANT" if rule_violations > 0 else "COMPLIANT",
            },
        )
        if isinstance(violations, list):
            for v in violations:
                total_violations += 1
                log_audit("SCP_POLICY_VIOLATION", v)
                if config.get("enforcement_mode") == "remediate":
                    remediate_violation(config, v)

    export_prometheus_metrics(metrics_by_rule, project_id)

    log_audit(
        "POLICY_SCAN_COMPLETE",
        {
            "total_violations": total_violations,
            "enforcement_mode": config.get("enforcement_mode"),
        },
    )


if __name__ == "__main__":
    main()
