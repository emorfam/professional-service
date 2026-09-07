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

# Managed STACKIT Key Value Store instance (based on Valkey) used as the JuiceFS metadata engine.

resource "stackit_valkey_instance" "juicefs" {
  project_id = var.stackit_project_id
  name       = "juicefs-metadata"
  version    = var.valkey_version
  plan_name  = var.valkey_plan_name

  parameters = {
    # Restrict inbound access to the SKE cluster's own public egress CIDRs.
    # egress_address_ranges is computed by the SKE API; sgw_acl expects a comma-separated string.
    sgw_acl = join(",", stackit_ske_cluster.this.egress_address_ranges)

    # JuiceFS requires noeviction so metadata keys are never evicted.
    # The managed Key Value Store user has no CONFIG SET permissions, so this must be set at provision time.
    maxmemory_policy = "noeviction"
  }
}

resource "stackit_valkey_credential" "juicefs" {
  project_id  = var.stackit_project_id
  instance_id = stackit_valkey_instance.juicefs.instance_id
}
