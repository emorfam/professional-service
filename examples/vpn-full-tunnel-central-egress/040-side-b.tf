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
# Side B - the "hub": tunnel traffic lands here and (optionally) leaves
# through one central egress machine.
# =========================================================================

resource "stackit_network_area" "b" {
  name            = var.sna_b_name
  organization_id = var.stackit_org_id
  labels = {
    "preview/routingtables" = "true"
  }
}

resource "stackit_network_area_region" "b" {
  organization_id = var.stackit_org_id
  network_area_id = stackit_network_area.b.network_area_id
  ipv4 = {
    transfer_network    = var.sna_b_transfer_network
    network_ranges      = [{ prefix = var.sna_b_range }]
    default_nameservers = var.default_nameservers
  }
}

resource "stackit_resourcemanager_project" "b" {
  parent_container_id = var.stackit_parent_container_id
  name                = var.project_b_name
  owner_email         = var.stackit_admin_email
  labels = {
    "networkArea" = stackit_network_area.b.network_area_id
  }
}

# The egress machine sits in its own routing table that keeps the normal
# internet default route - otherwise its own NATed traffic would be routed
# straight back to itself.
resource "stackit_routing_table" "b_egress" {
  organization_id = var.stackit_org_id
  network_area_id = stackit_network_area.b.network_area_id
  name            = "rt-egress-b"
  system_routes   = true
  dynamic_routes  = true

  depends_on = [stackit_network_area_region.b]
}

resource "stackit_network" "b_egress" {
  project_id       = stackit_resourcemanager_project.b.project_id
  name             = "egress-b"
  ipv4_prefix      = var.egress_network_prefix
  ipv4_nameservers = var.default_nameservers
  routing_table_id = stackit_routing_table.b_egress.routing_table_id
  depends_on       = [stackit_network_area_region.b]
}

resource "stackit_security_group" "b_egress" {
  project_id = stackit_resourcemanager_project.b.project_id
  name       = "egress-b-sg"
}

resource "stackit_security_group_rule" "b_egress_ssh" {
  project_id        = stackit_resourcemanager_project.b.project_id
  security_group_id = stackit_security_group.b_egress.security_group_id
  direction         = "ingress"
  ether_type        = "IPv4"
  ip_range          = var.admin_cidr
  protocol          = { name = "tcp" }
  port_range        = { min = 22, max = 22 }
}

resource "stackit_security_group_rule" "b_egress_internal" {
  project_id        = stackit_resourcemanager_project.b.project_id
  security_group_id = stackit_security_group.b_egress.security_group_id
  direction         = "ingress"
  ether_type        = "IPv4"
  ip_range          = "10.0.0.0/8"
}

resource "stackit_network_interface" "b_egress" {
  project_id         = stackit_resourcemanager_project.b.project_id
  network_id         = stackit_network.b_egress.network_id
  name               = "egress-b-nic"
  ipv4               = var.egress_host_ipv4
  security           = true
  security_group_ids = [stackit_security_group.b_egress.security_group_id]
  allowed_addresses  = ["0.0.0.0/0"]
}

resource "stackit_volume" "b_egress" {
  project_id        = stackit_resourcemanager_project.b.project_id
  name              = "egress-b-volume"
  availability_zone = var.machine_availability_zone
  size              = var.machine_disk_size
  performance_class = var.machine_disk_performance_class
  source            = { type = "image", id = data.stackit_image_v2.ubuntu.image_id }
}

resource "stackit_server" "b_egress" {
  project_id         = stackit_resourcemanager_project.b.project_id
  name               = "egress-b"
  availability_zone  = var.machine_availability_zone
  machine_type       = var.machine_type
  boot_volume        = { source_type = "volume", source_id = stackit_volume.b_egress.volume_id }
  agent              = { provisioning_policy = "ALWAYS" }
  network_interfaces = [stackit_network_interface.b_egress.network_interface_id]
  user_data          = local.cloud_init_egress
}

resource "stackit_public_ip" "b_egress" {
  project_id           = stackit_resourcemanager_project.b.project_id
  network_interface_id = stackit_network_interface.b_egress.network_interface_id
}
