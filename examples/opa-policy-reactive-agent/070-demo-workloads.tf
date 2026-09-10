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

# -----------------------------------------------------------------------------
# Compliant Workload Example
# Fully complies with all SCP guardrails:
# - Machine type in allowed list (g2i.1)
# - Has all mandatory tags (environment, owner, cost-center)
# - No public IP attached
# -----------------------------------------------------------------------------
resource "stackit_volume" "compliant_boot" {
  count             = var.enable_demo_workloads ? 1 : 0
  project_id        = var.stackit_project_id
  name              = "compliant-workload-boot"
  availability_zone = var.availability_zone
  size              = 10
  performance_class = "storage_premium_perf1"

  labels = {
    "environment" = var.environment
    "owner"       = "app-team"
    "cost-center" = "engineering"
  }

  source = {
    type = "image"
    id   = var.boot_image_id
  }
}

resource "stackit_network_interface" "compliant_nic" {
  count      = var.enable_demo_workloads ? 1 : 0
  project_id = var.stackit_project_id
  network_id = stackit_network.policy_engine_net.network_id
  security   = true
}

resource "stackit_server" "compliant_server" {
  count             = var.enable_demo_workloads ? 1 : 0
  project_id        = var.stackit_project_id
  name              = "compliant-workload-vm"
  availability_zone = var.availability_zone
  machine_type      = "g2i.1" # Approved machine type

  labels = {
    "environment" = var.environment
    "owner"       = "app-team"
    "cost-center" = "engineering"
  }

  boot_volume = {
    source_type = "volume"
    source_id   = stackit_volume.compliant_boot[0].volume_id
  }

  network_interfaces = [
    stackit_network_interface.compliant_nic[0].network_interface_id
  ]
}

# -----------------------------------------------------------------------------
# Non-Compliant Workload Example (for Policy Enforcement Testing)
# Violates SCP guardrails:
# - Unapproved public IP lacking 'allow-public-ip=true' tag
# - Missing mandatory tags ('cost-center')
# -----------------------------------------------------------------------------
resource "stackit_public_ip" "violating_public_ip" {
  count      = var.enable_demo_workloads ? 1 : 0
  project_id = var.stackit_project_id

  # Deliberately missing 'allow-public-ip' = 'true' approval tag to trigger SCP-01
  labels = {
    "environment" = var.environment
    "owner"       = "shadow-it"
  }
}
