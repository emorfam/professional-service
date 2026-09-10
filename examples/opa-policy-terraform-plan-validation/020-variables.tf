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
  description = "STACKIT Project ID where sample resources are evaluated."
  default     = "00000000-0000-0000-0000-000000000000"
}

variable "stackit_service_account_key_path" {
  type        = string
  description = "Path to STACKIT Service Account key JSON credentials file."
  default     = "~/.stackit/keys/sa-key.json"
}

variable "stackit_region" {
  type        = string
  description = "Target STACKIT Region."
  default     = "eu01"
}

variable "availability_zone" {
  type        = string
  description = "Target STACKIT Availability Zone."
  default     = "eu01-1"
}

variable "environment" {
  type        = string
  description = "Deployment environment label."
  default     = "demo"
}

variable "boot_image_id" {
  type        = string
  description = "Boot image ID for sample servers."
  default     = "012d2f5b-ee00-4700-9bea-cdabf0e1bfa8"
}

variable "allowed_ingress_cidrs" {
  type        = list(string)
  description = "List of CIDR blocks allowed for internet ingress access."
  default     = ["0.0.0.0/0"]
}
