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

output "project_a_id" {
  description = "Project ID of the spoke - the side whose traffic is fully tunnelled."
  value       = stackit_resourcemanager_project.a.project_id
}

output "project_b_id" {
  description = "Project ID of the hub - the side holding the central egress."
  value       = stackit_resourcemanager_project.b.project_id
}

output "sna_a_id" {
  description = "Network area ID of the spoke."
  value       = stackit_network_area.a.network_area_id
}

output "sna_b_id" {
  description = "Network area ID of the hub."
  value       = stackit_network_area.b.network_area_id
}

output "jump_host_public_ip" {
  description = "Public IP of the jump host. SSH entry point for reaching the tunnelled workload."
  value       = stackit_public_ip.a_jump.ip
}

output "egress_public_ip" {
  description = "Public IP of the central egress machine. The tunnelled workload appears on the internet with this address."
  value       = stackit_public_ip.b_egress.ip
}

output "client_private_ip" {
  description = "Private address of the tunnelled workload. Reachable only through the jump host."
  value       = stackit_network_interface.a_client.ipv4
}

output "egress_private_ip" {
  description = "Private address of the egress machine. Next hop of the hub's default route."
  value       = stackit_network_interface.b_egress.ipv4
}

output "routing_table_mgmt_a_id" {
  description = "Routing table of the management network, the one deliberately excluded from the full tunnel."
  value       = stackit_routing_table.a_mgmt.routing_table_id
}

output "routing_table_main_a_id" {
  description = "Default routing table of the spoke network area, where the BGP routes from the hub arrive."
  value       = local.a_main_routing_table_id
}

output "routing_table_main_b_id" {
  description = "Default routing table of the hub network area, holding the route towards the egress machine."
  value       = local.b_main_routing_table_id
}

output "vpn_gateway_a_tunnels" {
  description = "Public and SNA-internal endpoints of the spoke gateway, one entry per tunnel."
  value       = data.stackit_vpn_gateway_status.a.tunnels
}

output "vpn_gateway_b_tunnels" {
  description = "Public and SNA-internal endpoints of the hub gateway, one entry per tunnel."
  value       = data.stackit_vpn_gateway_status.b.tunnels
}
