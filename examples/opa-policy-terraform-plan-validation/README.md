<!-- tags: opa-policy-terraform-plan-validation, terraform, governance, compliance, ci-cd, shift-left, opa, rego -->

# Preventive IaC Governance: OPA Terraform Plan Validation

## Overview

This example demonstrates how to implement **Preventive IaC Governance ("Shift-Left")** by evaluating **Open Policy Agent (OPA)** declarative Rego policies against **STACKIT Terraform plan JSON output** (`tfplan.json`) before infrastructure is applied in CI/CD pipelines.

While the complementary [STACKIT Reactive Policy Agent (`examples/opa-policy-reactive-agent`)](../opa-policy-reactive-agent) continuously audits and remediates live resources at runtime ("Shift-Right"), this example prevents non-compliant resources from ever being provisioned in the first place.

---

## Preventive (CI/CD) vs. Reactive (Runtime) Governance

| Governance Strategy       | **Preventive IaC Guardrails** (This Example)       | **Reactive Policy Agent** ([`examples/opa-policy-reactive-agent`](../opa-policy-reactive-agent)) |
| :------------------------ | :------------------------------------------------- | :----------------------------------------------------------------------------------------------- |
| **Execution Point**       | **Pre-apply in CI/CD pipeline**                    | **Post-apply continuous runtime daemon**                                                         |
| **Input Schema**          | `terraform show -json tfplan.binary`               | STACKIT REST APIs via `stackit-sdk-python`                                                       |
| **Infrastructure Needed** | Zero infrastructure (runs in GitHub Actions / CLI) | Dedicated Policy Host VM & systemd daemon                                                        |
| **Enforcement**           | Fails CI/CD pipeline & blocks `terraform apply`    | Automatically remediates non-compliant live resources                                            |

---

## Rego Policy Rules

This example implements the same 5 core SCP-equivalent governance guardrails as the Reactive Policy Agent, adapted to the Terraform Plan JSON schema:

| Policy                       | Rule Name                    | Description                                                                                            |
| :--------------------------- | :--------------------------- | :----------------------------------------------------------------------------------------------------- |
| `scp_no_public_ips.rego`     | `SCP-01-NO-PUBLIC-IPS`       | Prohibits allocation of `stackit_public_ip` unless tagged with `allow-public-ip = "true"`.             |
| `scp_allowed_flavors.rego`   | `SCP-02-ALLOWED-FLAVORS`     | Restricts `stackit_server` machine types to an approved list (`g2i.1`, `g2i.2`, `c2i.2`, `c2i.4`).     |
| `scp_mandatory_tags.rego`    | `SCP-03-MANDATORY-TAGS`      | Enforces mandatory labels (`environment`, `owner`, `cost-center`) on compute, storage, and networking. |
| `scp_volume_encryption.rego` | `SCP-04-VOLUME-ENCRYPTION`   | Requires `stackit_volume` resources to be encrypted with a KMS key reference.                          |
| `scp_iam_guardrails.rego`    | `SCP-05-IAM-ADMIN-GUARDRAIL` | Restricts assignment of administrative roles (`project.admin`, `iam.admin`).                           |

---

## Quick Start

### Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.5.0
- [Open Policy Agent (OPA) CLI](https://www.openpolicyagent.org/docs/latest/#cli)

### Local Execution

1. Navigate to the example directory:

```bash
cd examples/opa-policy-terraform-plan-validation
```

2. Run the automated plan validation script:

```bash
./scripts/validate_plan.sh
```

---

## CI/CD Pipeline Integration Examples

### Forgejo Action (Recommended)

Include `.forgejo/workflows/opa-policy-check.yaml` in your repository:

```yaml
name: OPA Terraform Plan Validation (Forgejo Action)

on:
  pull_request:
    branches: [main]
  push:
    branches: [main]

jobs:
  validate-terraform-plan:
    runs-on: docker
    container:
      image: hashicorp/terraform:latest
    steps:
      - name: Checkout Repository
        uses: actions/checkout@v4

      - name: Install OPA CLI & Dependencies
        run: |
          apk add --no-cache bash curl jq
          curl -L -o /usr/local/bin/opa https://openpolicyagent.org/downloads/v0.68.0/opa_linux_amd64_static
          chmod +x /usr/local/bin/opa

      - name: Run OPA Plan Validation Script
        run: |
          cd examples/opa-policy-terraform-plan-validation
          chmod +x scripts/validate_plan.sh
          ./scripts/validate_plan.sh
```

### GitHub Actions

Include this workflow step in your GitHub Actions pipeline:

```yaml
name: Terraform Governance Pipeline

on:
  pull_request:
    branches: [main]

jobs:
  opa-plan-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3

      - name: Setup OPA
        uses: open-policy-agent/setup-opa@v2
        with:
          version: latest

      - name: Terraform Init & Plan
        run: |
          terraform init
          terraform plan -out=tfplan.binary
          terraform show -json tfplan.binary > tfplan.json

      - name: OPA Plan Policy Check
        run: |
          VIOLATIONS=$(opa eval --data policies/ --input tfplan.json "data.terraform.analysis.violations" --format pretty)
          echo "$VIOLATIONS"
          if [ "$VIOLATIONS" != "[]" ]; then
            echo "::error::OPA Policy check failed due to non-compliant IaC resources."
            exit 1
          fi
```

---

## References

- [Open Policy Agent Terraform Documentation](https://www.openpolicyagent.org/docs/latest/terraform/)
- [STACKIT Reactive Policy Agent Example](../opa-policy-reactive-agent)
- [STACKIT Terraform Provider](https://registry.terraform.io/providers/stackitcloud/stackit/latest/docs)
