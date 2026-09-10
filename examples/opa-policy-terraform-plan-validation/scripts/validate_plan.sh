#!/usr/bin/env bash
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

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXAMPLE_DIR="$(dirname "$SCRIPT_DIR")"

echo "==> Initializing Terraform..."
terraform -chdir="$EXAMPLE_DIR" init -backend=false

echo "==> Generating Terraform plan..."
terraform -chdir="$EXAMPLE_DIR" plan -out="$EXAMPLE_DIR/tfplan.binary"

echo "==> Exporting plan to JSON format..."
terraform -chdir="$EXAMPLE_DIR" show -json "$EXAMPLE_DIR/tfplan.binary" > "$EXAMPLE_DIR/tfplan.json"

echo "==> Evaluating OPA Rego Policies against Terraform Plan..."
if ! command -v opa &> /dev/null; then
    echo "ERROR: OPA binary not found. Please install OPA (https://www.openpolicyagent.org/docs/latest/#cli)."
    exit 1
fi

VIOLATIONS=$(opa eval --data "$EXAMPLE_DIR/policies" --input "$EXAMPLE_DIR/tfplan.json" "data.terraform.analysis.violations" --format pretty)

echo "$VIOLATIONS"

if [[ "$VIOLATIONS" != "[]" && "$VIOLATIONS" != "" ]]; then
    echo "FAILED: Policy violations detected in Terraform plan!"
    exit 1
else
    echo "SUCCESS: Terraform plan passed all OPA policy checks."
fi
