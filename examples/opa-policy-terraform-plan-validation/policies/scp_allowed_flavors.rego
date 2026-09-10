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

allowed_machine_types := {"g2i.1", "g2i.2", "c2i.2", "c2i.4"}

# SCP-02: Restrict server machine types to approved flavors list
violations contains msg if {
    some resource in input.resource_changes
    resource.type == "stackit_server"
    resource.change.actions[_] in ["create", "update"]
    machine_type := resource.change.after.machine_type
    not machine_type in allowed_machine_types
    msg := {
        "policy": "SCP-02-ALLOWED-FLAVORS",
        "resource": resource.address,
        "severity": "CRITICAL",
        "reason": sprintf("Server '%v' uses disallowed machine_type '%v'. Approved types: %v", [resource.address, machine_type, allowed_machine_types])
    }
}
