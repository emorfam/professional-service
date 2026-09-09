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

locals {
  cloud_init_common = <<-EOT
    #cloud-config
    users:
      - name: debug
        groups: sudo
        shell: /bin/bash
        sudo: ["ALL=(ALL) NOPASSWD:ALL"]
        ssh_authorized_keys:
          - ${var.ssh_public_key}
    package_update: true
    packages:
      - tcpdump
      - traceroute
      - mtr-tiny
      - netcat-openbsd
  EOT

  # The egress machine additionally forwards and NATs whatever arrives from the
  # tunnel. This is the minimum required to demonstrate the path - a production
  # central egress point would be a firewall appliance instead.
  cloud_init_egress = <<-EOT
    ${local.cloud_init_common}
    write_files:
      - path: /etc/sysctl.d/99-forward.conf
        content: "net.ipv4.ip_forward=1\n"
    runcmd:
      - sysctl --system
      - iptables -t nat -A POSTROUTING -s ${var.sna_a_range} ! -d 10.0.0.0/8 -j MASQUERADE
      - iptables -A FORWARD -j ACCEPT
  EOT
}
