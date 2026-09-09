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

variable "stackit_org_id" {
  description = "The STACKIT organization ID in which both network areas are created."
  type        = string
}

variable "stackit_region" {
  description = "The STACKIT region."
  type        = string
  default     = "eu01"
}

variable "stackit_service_account_key_path" {
  description = "Path to the STACKIT service account key JSON file."
  type        = string
  default     = "./keys/stackit-sa.json"
}

variable "stackit_parent_container_id" {
  description = "Existing folder ID both projects are created under, or the organization ID to create them directly under the organization. This example does not create the folder."
  type        = string
}

variable "stackit_admin_email" {
  description = "An existing STACKIT user that becomes owner of both created projects. A non-existent address fails with 409 'subject is not found'."
  type        = string
}

# --- naming --------------------------------------------------------------

variable "project_a_name" {
  description = "Display name of the spoke project - the side whose traffic is fully tunnelled."
  type        = string
  default     = "vpn-spoke"
}

variable "project_b_name" {
  description = "Display name of the hub project - the side holding the central egress."
  type        = string
  default     = "vpn-hub"
}

variable "sna_a_name" {
  description = "Name of the spoke STACKIT Network Area."
  type        = string
  default     = "vpn-ft-sna-a"
}

variable "sna_b_name" {
  description = "Name of the hub STACKIT Network Area."
  type        = string
  default     = "vpn-ft-sna-b"
}

# --- addressing ----------------------------------------------------------

variable "sna_a_range" {
  description = "IPv4 range of the spoke network area. Also the prefix the spoke gateway advertises over BGP."
  type        = string
  default     = "10.90.0.0/16"
}

variable "sna_a_transfer_network" {
  description = "Transfer network of the spoke network area."
  type        = string
  default     = "172.20.0.0/16"
}

variable "sna_b_range" {
  description = "IPv4 range of the hub network area. Also the prefix the hub gateway advertises over BGP."
  type        = string
  default     = "10.91.0.0/16"
}

variable "sna_b_transfer_network" {
  description = "Transfer network of the hub network area."
  type        = string
  default     = "172.21.0.0/16"
}

variable "mgmt_network_prefix" {
  description = "Prefix of the management network holding the jump host. Must sit inside sna_a_range."
  type        = string
  default     = "10.90.1.0/24"
}

variable "mgmt_host_ipv4" {
  description = "Fixed address of the jump host inside mgmt_network_prefix."
  type        = string
  default     = "10.90.1.10"
}

variable "client_network_prefix" {
  description = "Prefix of the workload network that is fully tunnelled. Must sit inside sna_a_range."
  type        = string
  default     = "10.90.2.0/24"
}

variable "client_host_ipv4" {
  description = "Fixed address of the workload machine inside client_network_prefix."
  type        = string
  default     = "10.90.2.10"
}

variable "egress_network_prefix" {
  description = "Prefix of the hub network holding the central egress machine. Must sit inside sna_b_range."
  type        = string
  default     = "10.91.1.0/24"
}

variable "egress_host_ipv4" {
  description = "Fixed address of the egress machine. Every tunnelled packet on the hub side is routed here."
  type        = string
  default     = "10.91.1.10"
}

variable "default_nameservers" {
  description = "Nameservers handed to the networks of both network areas."
  type        = list(string)
  default     = ["1.1.1.1"]
}

# --- access --------------------------------------------------------------

variable "admin_cidr" {
  description = "Source CIDR allowed to reach the jump host and the egress machine over SSH, for example your public IP with a /32 suffix."
  type        = string
}

variable "ssh_public_key" {
  description = "Public SSH key installed for the 'debug' user on all three machines. Never the private key."
  type        = string
}

# --- VPN -----------------------------------------------------------------

variable "vpn_plan_id" {
  description = "Service plan of both VPN gateways. p100 is the smallest available plan."
  type        = string
  default     = "p100"
}

variable "vpn_asn_a" {
  description = "Private BGP ASN of the spoke gateway (RFC 6996, 64512-4294967294). Must differ from vpn_asn_b."
  type        = number
  default     = 64520
}

variable "vpn_asn_b" {
  description = "Private BGP ASN of the hub gateway (RFC 6996, 64512-4294967294). Must differ from vpn_asn_a."
  type        = number
  default     = 64521
}

variable "vpn_availability_zones" {
  description = "Availability zone per tunnel. Two tunnels per connection give the gateway its HA."
  type = object({
    tunnel1 = string
    tunnel2 = string
  })
  default = {
    tunnel1 = "eu01-1"
    tunnel2 = "eu01-2"
  }
}

# --- machines ------------------------------------------------------------

variable "image_id" {
  description = "Image UUID for all three machines. Default is Ubuntu 24.04 in eu01."
  type        = string
  default     = "95d77000-d977-4ed1-8639-70ca359a5d1a"
}

variable "machine_type" {
  description = "Flavor of all three machines."
  type        = string
  default     = "t3i.1"
}

variable "machine_availability_zone" {
  description = "Availability zone the three machines and their volumes are created in."
  type        = string
  default     = "eu01-1"
}

variable "machine_disk_size" {
  description = "Boot volume size in GB."
  type        = number
  default     = 20
}

variable "machine_disk_performance_class" {
  description = "Storage performance class of the boot volumes."
  type        = string
  default     = "storage_premium_perf1"
}

# --- routing behaviour ---------------------------------------------------

variable "enable_full_tunnel_bgp" {
  description = "Let the hub gateway advertise full_tunnel_advertised_routes into the tunnel. This is what turns the VPN into a full tunnel. Set to false for a plain site-to-site VPN in which only the two ranges reach each other."
  type        = bool
  default     = true
}

variable "full_tunnel_advertised_routes" {
  description = "What the hub gateway announces so the spoke sends its internet traffic into the tunnel. A literal 0.0.0.0/0 is accepted by BGP but the gateway does not forward on it - use the two /1 halves, which cover the whole address space and are more specific than any default route."
  type        = list(string)
  default     = ["0.0.0.0/1", "128.0.0.0/1"]
}

variable "enable_central_egress" {
  description = "On the hub side, route everything arriving from the tunnel to the egress machine."
  type        = bool
  default     = true
}


variable "vpn_gateway_a_name" {
  description = "Display name of the spoke VPN gateway."
  type        = string
  default     = "vpn-ft-gw-a"
}

variable "vpn_gateway_b_name" {
  description = "Display name of the hub VPN gateway."
  type        = string
  default     = "vpn-ft-gw-b"
}
