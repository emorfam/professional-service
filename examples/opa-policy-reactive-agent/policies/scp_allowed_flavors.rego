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

package stackit.scp.allowed_flavors

import future.keywords.in

default allow = false

allow {
    count(violations) == 0
}

# Collect violations for servers running disallowed machine types / flavors
violations[violation] {
    some server in input.servers
    not is_allowed_machine_type(server.machine_type)
    violation := {
        "id": server.id,
        "name": server.name,
        "resource_type": "server",
        "policy": "SCP-02-ALLOWED-FLAVORS",
        "severity": "CRITICAL",
        "reason": sprintf("Server '%v' (%v) uses disallowed machine type '%v'", [server.name, server.id, server.machine_type]),
        "remediation_action": "stop_server"
    }
}

is_allowed_machine_type(machine_type) {
    some allowed in input.allowed_machine_types
    allowed == machine_type
}
