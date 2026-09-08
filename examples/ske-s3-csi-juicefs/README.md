<!-- tags: ske, juicefs, csi-driver, s3, object-storage, rwx, read-write-many, key-value-store, valkey, kubernetes -->

# SKE S3 CSI with JuiceFS

Mounts STACKIT Object Storage as a `ReadWriteMany` Kubernetes volume on SKE using the [JuiceFS CSI driver](https://github.com/juicedata/juicefs-csi-driver).

> S3-backed volumes are slower than block storage. Good fits: shared scratch space, ML dataset mounts, large file ingestion. Not recommended for latency-sensitive workloads.

JuiceFS requires a key-value store as its metadata engine. This example uses the managed **STACKIT Key Value Store** (based on Valkey). An in-cluster Redis deployment is also a valid alternative but is not covered here.

## What gets deployed

| File                    | Resources                                                                           |
| ----------------------- | ----------------------------------------------------------------------------------- |
| `030-ske.tf`            | SKE cluster + kubeconfig                                                            |
| `040-object-storage.tf` | S3 bucket + credentials                                                             |
| `050-managed-valkey.tf` | Managed STACKIT Key Value Store instance + credential                               |
| `055-juicefs.tf`        | JuiceFS CSI driver (Helm), `juicefs-secret`, `juicefs-sc` StorageClass              |
| `070-demo-workload.tf`  | `juicefs-demo` namespace, shared PVC, 2-replica Deployment writing to the same file |

## Usage

```bash
cp prod.auto.tfvars.example prod.auto.tfvars
# Set stackit_project_id and stackit_service_account_key_path.

terraform init && terraform apply
```

The Key Value Store plan and version can be overridden via `valkey_plan_name` and `valkey_version`. Run `stackit beta valkey plans list` or check the [STACKIT portal](https://portal.stackit.cloud) for available plan names.

The `sgw_acl` is set automatically from `stackit_ske_cluster.egress_address_ranges`, the computed list of public egress CIDRs the SKE API assigns to the cluster. No manual IP lookup is needed.

## Verify: shared volume

```bash
terraform output -raw kubeconfig > kubeconfig.yaml
export KUBECONFIG=$(pwd)/kubeconfig.yaml

kubectl rollout status deployment/juicefs-demo -n juicefs-demo
kubectl exec -n juicefs-demo deployment/juicefs-demo -- tail -20 /data/shared.txt
```

Both replicas write to the same `/data/shared.txt`. Lines from different pod hostnames appear interleaved.

## Verify: objects in S3

```bash
export AWS_ACCESS_KEY_ID=$(terraform output -raw juicefs_s3_access_key)
export AWS_SECRET_ACCESS_KEY=$(terraform output -raw juicefs_s3_secret_key)
export S3_ENDPOINT=$(terraform output -raw juicefs_s3_endpoint)
export BUCKET=$(terraform output -raw juicefs_bucket_name)

aws s3 ls s3://${BUCKET}/ --endpoint-url ${S3_ENDPOINT} --recursive --human-readable
```

## Gardener NetworkPolicy

SKE (Gardener) enforces a default-deny `NetworkPolicy` in `kube-system`. Pods must carry specific labels to open egress paths:

| Label                                                   | Opens                                          |
| ------------------------------------------------------- | ---------------------------------------------- |
| `networking.gardener.cloud/to-apiserver: allowed`       | Kubernetes API                                 |
| `networking.gardener.cloud/to-dns: allowed`             | CoreDNS                                        |
| `networking.gardener.cloud/to-public-networks: allowed` | Internet (S3, Key Value Store service gateway) |

Two sets of pods need these labels:

**CSI driver pods** (controller, node, dashboard): set via `controller.labels`, `node.labels`, `dashboard.labels` in the Helm values.

**Mount pods**: spawned dynamically in `kube-system` when a PVC is first mounted. They are not part of the Helm release and do not inherit the CSI driver labels. Patched via `globalConfig.mountPodPatch` (no `pvcSelector` means all mount pods). Without this, DNS resolution fails with `i/o timeout`.

The Key Value Store is accessed via a public IP through the STACKIT service gateway. The `to-public-networks` label covers this connection.

## Expected warnings

| Warning                                          | Cause                                                          | Action                                                                                       |
| ------------------------------------------------ | -------------------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| `AOF is not enabled`                             | The managed Key Value Store does not expose AOF configuration. | None. The managed service handles persistence internally.                                    |
| `try to reconfigure maxmemory-policy ... NOPERM` | The managed user has no `CONFIG SET` permissions.              | None. `maxmemory_policy = "noeviction"` is set at provision time in `050-managed-valkey.tf`. |
