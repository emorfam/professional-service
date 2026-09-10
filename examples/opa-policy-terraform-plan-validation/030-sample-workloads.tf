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

# -----------------------------------------------------------------------------
# Compliant Sample Resources (Pre-apply validation will PASS)
# -----------------------------------------------------------------------------
resource "stackit_network" "sample_net" {
  project_id         = var.stackit_project_id
  name               = "sample-net"
  ipv4_prefix_length = 26
  routed             = true
  ipv4_nameservers   = []
}

resource "stackit_security_group" "sample_sg" {
  project_id = var.stackit_project_id
  name       = "sample-sg"
  stateful   = true
}

resource "stackit_network_interface" "sample_nic" {
  project_id         = var.stackit_project_id
  network_id         = stackit_network.sample_net.network_id
  security           = true
  security_group_ids = [stackit_security_group.sample_sg.security_group_id]
}

# Approved Public IP (has 'allow-public-ip' = 'true' and mandatory labels)
resource "stackit_public_ip" "approved_public_ip" {
  project_id           = var.stackit_project_id
  network_interface_id = stackit_network_interface.sample_nic.network_interface_id
  labels = {
    "allow-public-ip" = "true"
    "environment"     = var.environment
    "owner"           = "governance-team"
    "cost-center"     = "sec-ops"
  }
}

# Compliant Server (Approved machine_type g2i.1, mandatory labels present)
resource "stackit_server" "compliant_server" {
  project_id        = var.stackit_project_id
  name              = "compliant-server"
  availability_zone = var.availability_zone
  machine_type      = "g2i.1"
  image_id          = var.boot_image_id

  labels = {
    "environment" = var.environment
    "owner"       = "engineering-team"
    "cost-center" = "dev-ops"
  }

  network_interfaces = [
    stackit_network_interface.sample_nic.network_interface_id
  ]
}

# -----------------------------------------------------------------------------
# Non-Compliant Sample Resources (Pre-apply validation will FAIL / DETECT)
# Uncomment these resources to test OPA plan validation failure:
# -----------------------------------------------------------------------------

# SCP-01 Violation: Unapproved Public IP lacking 'allow-public-ip = true' label
resource "stackit_public_ip" "unapproved_public_ip" {
  project_id = var.stackit_project_id
  labels = {
    "environment" = var.environment
    "owner"       = "unauthorized-team"
  }
}

# SCP-02 & SCP-03 Violation: Disallowed machine_type 'c2i.32' and missing 'cost-center' label
resource "stackit_server" "unapproved_server" {
  project_id        = var.stackit_project_id
  name              = "unapproved-server"
  availability_zone = var.availability_zone
  machine_type      = "c2i.32" # Disallowed large flavor
  image_id          = var.boot_image_id

  labels = {
    "environment" = var.environment
    "owner"       = "shadow-it"
  }
}
