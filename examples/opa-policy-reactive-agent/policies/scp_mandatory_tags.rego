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

package stackit.scp.mandatory_tags

import future.keywords.in

default allow = false

allow {
    count(violations) == 0
}

# Collect violations for resources missing mandatory tags/labels
violations[violation] {
    some server in input.servers
    missing := missing_mandatory_tags(server.labels)
    count(missing) > 0
    violation := {
        "id": server.id,
        "name": server.name,
        "resource_type": "server",
        "policy": "SCP-03-MANDATORY-TAGS",
        "severity": "MEDIUM",
        "reason": sprintf("Server '%v' (%v) is missing required tags: %v", [server.name, server.id, missing]),
        "remediation_action": "quarantine_or_notify"
    }
}

violations[violation] {
    some volume in input.volumes
    missing := missing_mandatory_tags(volume.labels)
    count(missing) > 0
    violation := {
        "id": volume.id,
        "name": volume.name,
        "resource_type": "volume",
        "policy": "SCP-03-MANDATORY-TAGS",
        "severity": "MEDIUM",
        "reason": sprintf("Volume '%v' (%v) is missing required tags: %v", [volume.name, volume.id, missing]),
        "remediation_action": "notify"
    }
}

missing_mandatory_tags(labels) = missing {
    missing := [tag |
        some tag in input.mandatory_tags
        not has_tag(labels, tag)
    ]
}

has_tag(labels, tag) {
    labels[tag] != ""
}
