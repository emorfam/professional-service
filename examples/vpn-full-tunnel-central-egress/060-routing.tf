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

# =========================================================================
# Routing - this is where the full tunnel actually happens.
#
# A VPN gateway attaches to its SNA's default ("main") routing table, and only
# tables with dynamic_routes = true receive what the gateway learns via BGP.
# So the spoke's workload network simply stays on "main" and inherits the
# 0.0.0.0/1 + 128.0.0.0/1 pair that the hub announces (see 050-vpn.tf). No
# static route is needed on the spoke side.
# =========================================================================

data "stackit_routing_tables" "a" {
  organization_id = var.stackit_org_id
  network_area_id = stackit_network_area.a.network_area_id

  depends_on = [stackit_network_area_region.a]
}

data "stackit_routing_tables" "b" {
  organization_id = var.stackit_org_id
  network_area_id = stackit_network_area.b.network_area_id

  depends_on = [stackit_network_area_region.b]
}

locals {
  a_main_routing_table_id = one([for rt in data.stackit_routing_tables.a.items : rt.routing_table_id if rt.default])
  b_main_routing_table_id = one([for rt in data.stackit_routing_tables.b.items : rt.routing_table_id if rt.default])
}

# --- Hub side: hand tunnelled traffic to the central egress VM ------------
resource "stackit_routing_table_route" "b_default_via_egress" {
  count = var.enable_central_egress ? 1 : 0

  organization_id  = var.stackit_org_id
  network_area_id  = stackit_network_area.b.network_area_id
  routing_table_id = local.b_main_routing_table_id

  destination = {
    type  = "cidrv4"
    value = "0.0.0.0/0"
  }
  next_hop = {
    type  = "ipv4"
    value = stackit_network_interface.b_egress.ipv4
  }
}

# The egress network sits in its own routing table, so the route above does not
# apply to it and its own NATed traffic still takes the normal breakout. It does
# reach the spoke, because dynamic routes are propagated into every routing table
# that has dynamic_routes = true - not just into the default one. With this table
# set to dynamic_routes = true, no static route back to the spoke range is
# needed.
