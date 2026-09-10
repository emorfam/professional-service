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

# SCP-01: Prohibit Public IPs unless explicitly approved with label 'allow-public-ip = true'
violations contains msg if {
    some resource in input.resource_changes
    resource.type == "stackit_public_ip"
    resource.change.actions[_] in ["create", "update"]
    labels := object.get(resource.change.after, "labels", {})
    labels["allow-public-ip"] != "true"
    msg := {
        "policy": "SCP-01-NO-PUBLIC-IPS",
        "resource": resource.address,
        "severity": "HIGH",
        "reason": sprintf("Resource '%v' allocates a Public IP without required label 'allow-public-ip=true'", [resource.address])
    }
}
