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

package terraform.analysis

import rego.v1

prohibited_roles := {"project.admin", "iam.admin"}
whitelisted_subjects := {"service-account-governance@stackit.cloud"}

# SCP-05: Restrict unauthorized assignment of administrative roles
violations contains msg if {
    some resource in input.resource_changes
    resource.type in {"stackit_authorization_project_role_assignment", "stackit_role_binding"}
    resource.change.actions[_] in ["create", "update"]
    role := resource.change.after.role
    subj := resource.change.after.subject
    role in prohibited_roles
    not subj in whitelisted_subjects
    msg := {
        "policy": "SCP-05-IAM-ADMIN-GUARDRAIL",
        "resource": resource.address,
        "severity": "CRITICAL",
        "reason": sprintf("Resource '%v' assigns prohibited role '%v' to subject '%v' without approval", [resource.address, role, subj])
    }
}
