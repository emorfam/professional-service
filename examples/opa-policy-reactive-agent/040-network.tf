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

resource "stackit_network" "policy_engine_net" {
  project_id         = var.stackit_project_id
  name               = "policy-engine-net"
  ipv4_prefix_length = 26
  routed             = true
  ipv4_nameservers   = ["192.214.161.53", "213.17.17.17", "188.34.111.111"]
}

resource "stackit_security_group" "policy_engine_sg" {
  project_id = var.stackit_project_id
  name       = "policy-engine-sg"
  stateful   = true
}

resource "stackit_security_group_rule" "ssh_ingress" {
  for_each          = toset(var.allowed_ingress_cidrs)
  project_id        = var.stackit_project_id
  security_group_id = stackit_security_group.policy_engine_sg.security_group_id
  direction         = "ingress"
  description       = "Allow SSH access to policy engine daemon host"

  protocol   = { name = "tcp" }
  port_range = { min = 22, max = 22 }
  ip_range   = each.value
}

resource "stackit_security_group_rule" "egress_tcp" {
  project_id        = var.stackit_project_id
  security_group_id = stackit_security_group.policy_engine_sg.security_group_id
  direction         = "egress"
  description       = "Allow outbound TCP"

  protocol = { name = "tcp" }
  ip_range = "0.0.0.0/0"
}

resource "stackit_security_group_rule" "egress_udp" {
  project_id        = var.stackit_project_id
  security_group_id = stackit_security_group.policy_engine_sg.security_group_id
  direction         = "egress"
  description       = "Allow outbound UDP"

  protocol = { name = "udp" }
  ip_range = "0.0.0.0/0"
}

resource "stackit_security_group_rule" "egress_icmp" {
  project_id        = var.stackit_project_id
  security_group_id = stackit_security_group.policy_engine_sg.security_group_id
  direction         = "egress"
  description       = "Allow outbound ICMP"

  protocol = { name = "icmp" }
  ip_range = "0.0.0.0/0"
}

resource "stackit_network_interface" "policy_engine_nic" {
  project_id         = var.stackit_project_id
  network_id         = stackit_network.policy_engine_net.network_id
  security           = true
  security_group_ids = [stackit_security_group.policy_engine_sg.security_group_id]
}

resource "stackit_public_ip" "policy_engine_public_ip" {
  project_id           = var.stackit_project_id
  network_interface_id = stackit_network_interface.policy_engine_nic.network_interface_id
  labels = {
    "allow-public-ip" = "true"
    "environment"     = var.environment
    "owner"           = "governance-team"
    "cost-center"     = "sec-ops"
  }
}
