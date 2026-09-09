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
# Managed VPN: one gateway per side, BGP route based, HA over two tunnels.
# =========================================================================

resource "stackit_vpn_gateway" "a" {
  project_id   = stackit_resourcemanager_project.a.project_id
  display_name = var.vpn_gateway_a_name
  plan_id      = var.vpn_plan_id
  routing_type = "BGP_ROUTE_BASED"

  availability_zones = {
    tunnel1 = var.vpn_availability_zones.tunnel1
    tunnel2 = var.vpn_availability_zones.tunnel2
  }

  bgp = {
    local_asn                  = var.vpn_asn_a
    override_advertised_routes = [var.sna_a_range]
  }

  depends_on = [stackit_network_area_region.a, stackit_network.a_client]
}

resource "stackit_vpn_gateway" "b" {
  project_id   = stackit_resourcemanager_project.b.project_id
  display_name = var.vpn_gateway_b_name
  plan_id      = var.vpn_plan_id
  routing_type = "BGP_ROUTE_BASED"

  availability_zones = {
    tunnel1 = var.vpn_availability_zones.tunnel1
    tunnel2 = var.vpn_availability_zones.tunnel2
  }

  bgp = {
    local_asn = var.vpn_asn_b
    # This is what actually turns the VPN into a full tunnel for side A.
    override_advertised_routes = concat([var.sna_b_range], var.enable_full_tunnel_bgp ? var.full_tunnel_advertised_routes : [])
  }

  depends_on = [stackit_network_area_region.b, stackit_network.b_egress]
}

data "stackit_vpn_gateway_status" "a" {
  project_id = stackit_resourcemanager_project.a.project_id
  gateway_id = stackit_vpn_gateway.a.gateway_id
}

data "stackit_vpn_gateway_status" "b" {
  project_id = stackit_resourcemanager_project.b.project_id
  gateway_id = stackit_vpn_gateway.b.gateway_id
}

resource "random_password" "psk" {
  length  = 40
  special = false
}

locals {
  # Link-local addresses used only for the BGP session inside each tunnel.
  # They never leave the tunnel, so they are not exposed as variables.
  peering = {
    tunnel1 = { a = "169.254.10.1", b = "169.254.10.2" }
    tunnel2 = { a = "169.254.11.1", b = "169.254.11.2" }
  }

  phase1 = {
    dh_groups             = ["modp2048"]
    encryption_algorithms = ["aes256gcm16"]
    integrity_algorithms  = ["sha2_256"]
  }
  phase2 = {
    dh_groups             = ["modp2048"]
    encryption_algorithms = ["aes256gcm16"]
    integrity_algorithms  = ["sha2_256"]
  }
}

resource "stackit_vpn_connection" "a_to_b" {
  project_id   = stackit_resourcemanager_project.a.project_id
  gateway_id   = stackit_vpn_gateway.a.gateway_id
  display_name = "a-to-b"

  tunnel1 = {
    remote_address            = data.stackit_vpn_gateway_status.b.tunnels[0].public_ip
    pre_shared_key_wo         = random_password.psk.result
    pre_shared_key_wo_version = 1
    bgp                       = { remote_asn = var.vpn_asn_b }
    peering                   = { local_address = local.peering.tunnel1.a, remote_address = local.peering.tunnel1.b }
    phase1                    = local.phase1
    phase2                    = local.phase2
  }

  tunnel2 = {
    remote_address            = data.stackit_vpn_gateway_status.b.tunnels[1].public_ip
    pre_shared_key_wo         = random_password.psk.result
    pre_shared_key_wo_version = 1
    bgp                       = { remote_asn = var.vpn_asn_b }
    peering                   = { local_address = local.peering.tunnel2.a, remote_address = local.peering.tunnel2.b }
    phase1                    = local.phase1
    phase2                    = local.phase2
  }
}

resource "stackit_vpn_connection" "b_to_a" {
  project_id   = stackit_resourcemanager_project.b.project_id
  gateway_id   = stackit_vpn_gateway.b.gateway_id
  display_name = "b-to-a"

  tunnel1 = {
    remote_address            = data.stackit_vpn_gateway_status.a.tunnels[0].public_ip
    pre_shared_key_wo         = random_password.psk.result
    pre_shared_key_wo_version = 1
    bgp                       = { remote_asn = var.vpn_asn_a }
    peering                   = { local_address = local.peering.tunnel1.b, remote_address = local.peering.tunnel1.a }
    phase1                    = local.phase1
    phase2                    = local.phase2
  }

  tunnel2 = {
    remote_address            = data.stackit_vpn_gateway_status.a.tunnels[1].public_ip
    pre_shared_key_wo         = random_password.psk.result
    pre_shared_key_wo_version = 1
    bgp                       = { remote_asn = var.vpn_asn_a }
    peering                   = { local_address = local.peering.tunnel2.b, remote_address = local.peering.tunnel2.a }
    phase1                    = local.phase1
    phase2                    = local.phase2
  }
}
