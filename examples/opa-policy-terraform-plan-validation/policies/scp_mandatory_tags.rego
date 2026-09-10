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

mandatory_tags := {"environment", "owner", "cost-center"}
tagged_resource_types := {"stackit_server", "stackit_volume", "stackit_public_ip"}

# SCP-03: Enforce mandatory resource labels (environment, owner, cost-center)
violations contains msg if {
    some resource in input.resource_changes
    resource.type in tagged_resource_types
    resource.change.actions[_] in ["create", "update"]
    labels := object.get(resource.change.after, "labels", {})
    some tag in mandatory_tags
    not labels[tag]
    msg := {
        "policy": "SCP-03-MANDATORY-TAGS",
        "resource": resource.address,
        "severity": "MEDIUM",
        "reason": sprintf("Resource '%v' of type '%v' is missing mandatory label '%v'", [resource.address, resource.type, tag])
    }
}
