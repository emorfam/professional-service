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

package stackit.scp.volume_encryption

import future.keywords.in

default allow = false

allow {
    count(violations) == 0
}

# Collect violations for unencrypted volumes or volumes missing required KMS key reference
violations[violation] {
    some volume in input.volumes
    not is_encrypted_volume(volume)
    violation := {
        "id": volume.id,
        "name": volume.name,
        "resource_type": "volume",
        "policy": "SCP-04-VOLUME-ENCRYPTION",
        "severity": "HIGH",
        "reason": sprintf("Volume '%v' (%v) does not have KMS encryption configured", [volume.name, volume.id]),
        "remediation_action": "detach_volume"
    }
}

is_encrypted_volume(volume) {
    volume.kms_key_id != ""
    volume.kms_key_id != null
}

is_encrypted_volume(volume) {
    volume.encrypted == true
}
