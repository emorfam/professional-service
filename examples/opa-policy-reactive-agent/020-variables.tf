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

variable "stackit_project_id" {
  type        = string
  description = "STACKIT Project ID where the Reactive Policy Engine and monitored resources are deployed."
}

variable "stackit_service_account_key_path" {
  type        = string
  description = "Path to the STACKIT Service Account key JSON file used by Terraform provider."
  default     = "~/.stackit/sa-key.json"
}

variable "ssh_public_key_path" {
  type        = string
  description = "Path to the SSH public key file installed on the Policy Engine host VM."
  default     = "~/.ssh/id_rsa.pub"
}

variable "stackit_region" {
  type        = string
  description = "Target STACKIT region."
  default     = "eu01"
}

variable "availability_zone" {
  type        = string
  description = "Target STACKIT availability zone."
  default     = "eu01-1"
}

variable "boot_image_id" {
  type        = string
  description = "Boot image for all needed VMs"
  default     = "012d2f5b-ee00-4700-9bea-cdabf0e1bfa8" # Ubuntu 26.04
}

variable "environment" {
  type        = string
  description = "Deployment environment tag (e.g. demo, dev, prod)."
  default     = "demo"
}

variable "enforcement_mode" {
  type        = string
  description = "Policy enforcement mode: 'audit' (logs violations) or 'remediate' (automatically enforces SCP guardrails)."
  default     = "remediate"

  validation {
    condition     = contains(["audit", "remediate"], var.enforcement_mode)
    error_message = "enforcement_mode must be either 'audit' or 'remediate'."
  }
}

variable "allowed_machine_types" {
  type        = list(string)
  description = "List of approved VM machine types allowed under SCP-02 policy."
  default     = ["g2i.1", "g2i.2", "c2i.2", "c2i.4"]
}

variable "mandatory_tags" {
  type        = list(string)
  description = "List of required resource labels/tags under SCP-03 policy."
  default     = ["environment", "owner", "cost-center"]
}

variable "policy_engine_machine_type" {
  type        = string
  description = "Machine type for the Policy Engine host VM."
  default     = "g2i.1"
}

variable "policy_engine_disk_size" {
  type        = number
  description = "Disk size in GB for the Policy Engine host VM."
  default     = 20
}

variable "enable_demo_workloads" {
  type        = bool
  description = "Whether to provision example compliant and non-compliant workloads to demonstrate reactive policy enforcement."
  default     = true
}

variable "observability_plan_name" {
  type        = string
  description = "Plan name for STACKIT Observability instance."
  default     = "Observability-Starter-EU01"
}

variable "allowed_ingress_cidrs" {
  type        = list(string)
  description = "List of CIDR blocks allowed for internet ingress access (SSH security group rules and STACKIT Observability ACLs)."
  default     = ["0.0.0.0/0"]
}
