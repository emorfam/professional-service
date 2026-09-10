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

package stackit.scp.public_ips

import future.keywords.in

# Default result: deny if any non-compliant public IP is present
default allow = false

# Allow if violations list is empty
allow {
    count(violations) == 0
}

# Collect violations for public IPs that lack the required approval tag/label
violations[violation] {
    some ip in input.public_ips
    not is_approved_public_ip(ip)
    violation := {
        "id": ip.id,
        "ip": ip.ip,
        "resource_type": "public_ip",
        "policy": "SCP-01-NO-PUBLIC-IPS",
        "severity": "HIGH",
        "reason": sprintf("Public IP %v (%v) is not explicitly approved with label 'allow-public-ip=true'", [ip.id, ip.ip]),
        "remediation_action": "delete_public_ip"
    }
}

is_approved_public_ip(ip) {
    ip.labels["allow-public-ip"] == "true"
}
