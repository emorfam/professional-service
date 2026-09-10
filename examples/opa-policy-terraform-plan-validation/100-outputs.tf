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

output "sample_server_name" {
  description = "Name of the sample compliant server."
  value       = stackit_server.compliant_server.name
}

output "sample_public_ip_id" {
  description = "ID of the sample approved public IP."
  value       = stackit_public_ip.approved_public_ip.public_ip_id
}

output "validation_instructions" {
  description = "Instructions to run pre-apply OPA policy validation against Terraform plan."
  value       = "Run './scripts/validate_plan.sh' or 'terraform plan -out=tfplan.binary && terraform show -json tfplan.binary > tfplan.json && opa eval --data policies --input tfplan.json \"data.terraform.analysis.violations\"'"
}
