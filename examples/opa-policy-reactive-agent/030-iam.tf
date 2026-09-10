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

resource "random_string" "sa_suffix" {
  length  = 6
  special = false
  upper   = false
}

# Dedicated Service Account for the Reactive Policy Engine
resource "stackit_service_account" "policy_engine" {
  project_id = var.stackit_project_id
  name       = "policies-sa-${random_string.sa_suffix.result}"
}

# Service Account Key for Policy Engine daemon API authentication
resource "stackit_service_account_key" "policy_engine_key" {
  project_id            = var.stackit_project_id
  service_account_email = stackit_service_account.policy_engine.email
}

# Role Assignment: Reader / Auditor permissions across project resources
resource "stackit_authorization_project_role_assignment" "policy_engine_reader" {
  resource_id = var.stackit_project_id
  role        = "reader"
  subject     = stackit_service_account.policy_engine.email
}

# Role Assignment: Compute Admin permission for remediating VM/Network violations
resource "stackit_authorization_project_role_assignment" "policy_engine_compute_admin" {
  resource_id = var.stackit_project_id
  role        = "iaas.admin"
  subject     = stackit_service_account.policy_engine.email
}
