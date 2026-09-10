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

package stackit.scp.iam_guardrails

import future.keywords.in

default allow = false

allow {
    count(violations) == 0
}

# Collect violations for prohibited IAM role assignments (e.g. project.admin or iam.admin to non-approved principals)
violations[violation] {
    some binding in input.role_bindings
    is_prohibited_admin_role(binding.role)
    not is_whitelisted_principal(binding.subject)
    violation := {
        "id": sprintf("%v-%v", [binding.role, binding.subject]),
        "role": binding.role,
        "subject": binding.subject,
        "resource_type": "role_binding",
        "policy": "SCP-05-IAM-ADMIN-GUARDRAIL",
        "severity": "CRITICAL",
        "reason": sprintf("Subject '%v' assigned prohibited admin role '%v' without governance approval", [binding.subject, binding.role]),
        "remediation_action": "revoke_role_binding"
    }
}

is_prohibited_admin_role(role) {
    role == "project.admin"
}

is_prohibited_admin_role(role) {
    role == "iam.admin"
}

is_whitelisted_principal(subject) {
    some allowed in input.whitelisted_admin_subjects
    allowed == subject
}
