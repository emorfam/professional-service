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

# Policy engine active ruleset declaration
resource "local_file" "policy_engine_config" {
  filename = "${path.module}/build/config.json"
  content = jsonencode({
    project_id                 = var.stackit_project_id
    enforcement_mode           = var.enforcement_mode
    allowed_machine_types      = var.allowed_machine_types
    mandatory_tags             = var.mandatory_tags
    whitelisted_admin_subjects = [stackit_service_account.policy_engine.email]
    active_policies = [
      "SCP-01-NO-PUBLIC-IPS",
      "SCP-02-ALLOWED-FLAVORS",
      "SCP-03-MANDATORY-TAGS",
      "SCP-04-VOLUME-ENCRYPTION",
      "SCP-05-IAM-ADMIN-GUARDRAIL"
    ]
  })
}
