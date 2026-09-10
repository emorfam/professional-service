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

resource "stackit_key_pair" "keypair" {
  name       = "policy_key"
  public_key = chomp(file(var.ssh_public_key_path))
}

resource "stackit_volume" "policy_engine_boot" {
  project_id        = var.stackit_project_id
  name              = "policy-engine-boot"
  availability_zone = var.availability_zone
  size              = var.policy_engine_disk_size
  performance_class = "storage_premium_perf1"

  labels = {
    "environment" = var.environment
    "owner"       = "governance-team"
    "cost-center" = "sec-ops"
  }

  source = {
    type = "image"
    id   = var.boot_image_id
  }
}

resource "stackit_server" "policy_engine_host" {
  project_id        = var.stackit_project_id
  name              = "policy-engine-daemon"
  availability_zone = var.availability_zone
  machine_type      = var.policy_engine_machine_type

  labels = {
    "environment" = var.environment
    "owner"       = "governance-team"
    "cost-center" = "sec-ops"
    "role"        = "policy-engine"
  }

  boot_volume = {
    source_type = "volume"
    source_id   = stackit_volume.policy_engine_boot.volume_id
  }

  network_interfaces = [
    stackit_network_interface.policy_engine_nic.network_interface_id
  ]

  user_data = templatefile("${path.module}/cloud-init/policy-engine.yaml.tftpl", {
    project_id                      = var.stackit_project_id
    enforcement_mode                = var.enforcement_mode
    allowed_machine_types_json      = jsonencode(var.allowed_machine_types)
    mandatory_tags_json             = jsonencode(var.mandatory_tags)
    whitelisted_admin_subjects_json = jsonencode([stackit_service_account.policy_engine.email])
    sa_key_json                     = stackit_service_account_key.policy_engine_key.json
    policy_runner_b64gzip           = base64gzip(file("${path.module}/scripts/policy_runner.py"))
    policy_no_public_ips_b64        = base64encode(file("${path.module}/policies/scp_no_public_ips.rego"))
    policy_allowed_flavors_b64      = base64encode(file("${path.module}/policies/scp_allowed_flavors.rego"))
    policy_mandatory_tags_b64       = base64encode(file("${path.module}/policies/scp_mandatory_tags.rego"))
    policy_volume_encryption_b64    = base64encode(file("${path.module}/policies/scp_volume_encryption.rego"))
    policy_iam_guardrails_b64       = base64encode(file("${path.module}/policies/scp_iam_guardrails.rego"))
    obs_instance_id                 = stackit_observability_instance.policy_engine_obs.instance_id
    obs_logs_push_url               = stackit_observability_instance.policy_engine_obs.logs_push_url
    obs_metrics_push_url            = stackit_observability_instance.policy_engine_obs.metrics_push_url
    obs_username                    = stackit_observability_credential.policy_engine_obs_credentials.username
    obs_password                    = stackit_observability_credential.policy_engine_obs_credentials.password
  })

  keypair_name = "policy_key"
}
