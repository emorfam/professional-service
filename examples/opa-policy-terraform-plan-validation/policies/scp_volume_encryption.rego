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

# SCP-04: Enforce block storage volume KMS key encryption
violations contains msg if {
    some resource in input.resource_changes
    resource.type == "stackit_volume"
    resource.change.actions[_] in ["create", "update"]
    not resource.change.after.kms_key_id
    not resource.change.after.encrypted
    msg := {
        "policy": "SCP-04-VOLUME-ENCRYPTION",
        "resource": resource.address,
        "severity": "HIGH",
        "reason": sprintf("Volume '%v' is unencrypted or missing KMS key reference", [resource.address])
    }
}
