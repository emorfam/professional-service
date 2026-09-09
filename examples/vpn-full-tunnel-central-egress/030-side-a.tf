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
# Side A - the "spoke": everything here must leave through the VPN tunnel.
# =========================================================================

resource "stackit_network_area" "a" {
  name            = var.sna_a_name
  organization_id = var.stackit_org_id
  labels = {
    "preview/routingtables" = "true"
  }
}

resource "stackit_network_area_region" "a" {
  organization_id = var.stackit_org_id
  network_area_id = stackit_network_area.a.network_area_id
  ipv4 = {
    transfer_network    = var.sna_a_transfer_network
    network_ranges      = [{ prefix = var.sna_a_range }]
    default_nameservers = var.default_nameservers
  }
}

resource "stackit_resourcemanager_project" "a" {
  parent_container_id = var.stackit_parent_container_id
  name                = var.project_a_name
  owner_email         = var.stackit_admin_email
  labels = {
    "networkArea" = stackit_network_area.a.network_area_id
  }
}

# The VPN gateway always attaches to the SNA's *default* ("main") routing table,
# and only that table receives the routes the gateway learns via BGP. So the
# workload network stays on "main" and gets the default route pointed at the VPN;
# the jump host opts out through a routing table of its own.
resource "stackit_routing_table" "a_mgmt" {
  organization_id = var.stackit_org_id
  network_area_id = stackit_network_area.a.network_area_id
  name            = "rt-mgmt-a"
  description     = "Jump host - keeps normal internet breakout, never full-tunnelled"
  system_routes   = true
  # A second safeguard. The explicit internet route below already outranks
  # anything learned via BGP, but with dynamic_routes off the announced default
  # never enters this table in the first place.
  dynamic_routes = false

  depends_on = [stackit_network_area_region.a]
}

resource "stackit_network" "a_mgmt" {
  project_id       = stackit_resourcemanager_project.a.project_id
  name             = "mgmt-a"
  ipv4_prefix      = var.mgmt_network_prefix
  ipv4_nameservers = var.default_nameservers
  routing_table_id = stackit_routing_table.a_mgmt.routing_table_id
  depends_on       = [stackit_network_area_region.a]
}

# Client network - on the default routing table, i.e. the one the VPN gateway uses.
resource "stackit_network" "a_client" {
  project_id       = stackit_resourcemanager_project.a.project_id
  name             = "client-a"
  ipv4_prefix      = var.client_network_prefix
  ipv4_nameservers = var.default_nameservers
  routing_table_id = local.a_main_routing_table_id
  depends_on       = [stackit_network_area_region.a]
}

# --- jump host -----------------------------------------------------------
resource "stackit_security_group" "a_jump" {
  project_id = stackit_resourcemanager_project.a.project_id
  name       = "jump-a-sg"
}

resource "stackit_security_group_rule" "a_jump_ssh" {
  project_id        = stackit_resourcemanager_project.a.project_id
  security_group_id = stackit_security_group.a_jump.security_group_id
  direction         = "ingress"
  ether_type        = "IPv4"
  ip_range          = var.admin_cidr
  protocol          = { name = "tcp" }
  port_range        = { min = 22, max = 22 }
}

resource "stackit_security_group_rule" "a_jump_internal" {
  project_id        = stackit_resourcemanager_project.a.project_id
  security_group_id = stackit_security_group.a_jump.security_group_id
  direction         = "ingress"
  ether_type        = "IPv4"
  ip_range          = "10.0.0.0/8"
}

resource "stackit_network_interface" "a_jump" {
  project_id         = stackit_resourcemanager_project.a.project_id
  network_id         = stackit_network.a_mgmt.network_id
  name               = "jump-a-nic"
  ipv4               = var.mgmt_host_ipv4
  security           = true
  security_group_ids = [stackit_security_group.a_jump.security_group_id]
}

resource "stackit_volume" "a_jump" {
  project_id        = stackit_resourcemanager_project.a.project_id
  name              = "jump-a-volume"
  availability_zone = var.machine_availability_zone
  size              = var.machine_disk_size
  performance_class = var.machine_disk_performance_class
  source            = { type = "image", id = data.stackit_image_v2.ubuntu.image_id }
}

resource "stackit_server" "a_jump" {
  project_id         = stackit_resourcemanager_project.a.project_id
  name               = "jump-a"
  availability_zone  = var.machine_availability_zone
  machine_type       = var.machine_type
  boot_volume        = { source_type = "volume", source_id = stackit_volume.a_jump.volume_id }
  agent              = { provisioning_policy = "ALWAYS" }
  network_interfaces = [stackit_network_interface.a_jump.network_interface_id]
  user_data          = local.cloud_init_common
}

resource "stackit_public_ip" "a_jump" {
  project_id           = stackit_resourcemanager_project.a.project_id
  network_interface_id = stackit_network_interface.a_jump.network_interface_id
}

# --- client (no public IP, reached via the jump host) ---------------------
resource "stackit_network_interface" "a_client" {
  project_id = stackit_resourcemanager_project.a.project_id
  network_id = stackit_network.a_client.network_id
  name       = "client-a-nic"
  ipv4       = var.client_host_ipv4
  security   = false
}

resource "stackit_volume" "a_client" {
  project_id        = stackit_resourcemanager_project.a.project_id
  name              = "client-a-volume"
  availability_zone = var.machine_availability_zone
  size              = var.machine_disk_size
  performance_class = var.machine_disk_performance_class
  source            = { type = "image", id = data.stackit_image_v2.ubuntu.image_id }
}

resource "stackit_server" "a_client" {
  project_id         = stackit_resourcemanager_project.a.project_id
  name               = "client-a"
  availability_zone  = var.machine_availability_zone
  machine_type       = var.machine_type
  boot_volume        = { source_type = "volume", source_id = stackit_volume.a_client.volume_id }
  agent              = { provisioning_policy = "ALWAYS" }
  network_interfaces = [stackit_network_interface.a_client.network_interface_id]
  user_data          = local.cloud_init_common
}

# Pin the jump host's breakout explicitly. A static route always wins over a
# route learned via BGP, so even a 0.0.0.0/0 announced by the remote side can
# no longer drag the management network into the tunnel.
resource "stackit_routing_table_route" "a_mgmt_internet" {
  organization_id  = var.stackit_org_id
  network_area_id  = stackit_network_area.a.network_area_id
  routing_table_id = stackit_routing_table.a_mgmt.routing_table_id

  destination = {
    type  = "cidrv4"
    value = "0.0.0.0/0"
  }
  next_hop = {
    type = "internet"
  }
}
