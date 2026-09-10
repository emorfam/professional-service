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

output "policy_engine_server_id" {
  description = "ID of the STACKIT VM running the Reactive Policy Engine daemon."
  value       = stackit_server.policy_engine_host.id
}

output "policy_engine_public_ip" {
  description = "Public IP allocated to the Policy Engine VM."
  value       = stackit_public_ip.policy_engine_public_ip.ip
}

output "policy_engine_service_account_email" {
  description = "Email of the dedicated Policy Engine Service Account."
  value       = stackit_service_account.policy_engine.email
}

output "enforcement_mode" {
  description = "Current policy engine enforcement mode (audit vs remediate)."
  value       = var.enforcement_mode
}

output "active_scp_policies" {
  description = "List of active SCP-equivalent guardrail policies evaluated by the engine."
  value = [
    "SCP-01-NO-PUBLIC-IPS: Restrict unapproved public IPs",
    "SCP-02-ALLOWED-FLAVORS: Restrict unapproved VM machine types",
    "SCP-03-MANDATORY-TAGS: Enforce environment, owner, and cost-center tags",
    "SCP-04-VOLUME-ENCRYPTION: Enforce KMS volume encryption",
    "SCP-05-IAM-ADMIN-GUARDRAIL: Enforce administrative role assignment guardrails"
  ]
}

output "audit_logs_command" {
  description = "Command to inspect reactive policy engine evaluation logs on the host."
  value       = "ssh -i ${replace(var.ssh_public_key_path, ".pub", "")} ubuntu@${stackit_public_ip.policy_engine_public_ip.ip} 'sudo journalctl -u stackit-policy-engine.service -f'"
}

output "observability_instance_id" {
  description = "ID of the STACKIT Observability instance."
  value       = stackit_observability_instance.policy_engine_obs.instance_id
}

output "observability_grafana_url" {
  description = "URL of the Grafana dashboard in STACKIT Observability."
  value       = stackit_observability_instance.policy_engine_obs.grafana_url
}

output "observability_logs_url" {
  description = "Logs (Loki) URL in STACKIT Observability."
  value       = stackit_observability_instance.policy_engine_obs.logs_url
}

output "observability_metrics_url" {
  description = "Metrics (Prometheus) URL in STACKIT Observability."
  value       = stackit_observability_instance.policy_engine_obs.metrics_url
}
