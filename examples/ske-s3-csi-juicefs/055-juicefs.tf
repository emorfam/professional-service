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
  # STACKIT Key Value Store credentials use the "valkeys://" scheme (TLS).
  # JuiceFS only recognises "redis://" and "rediss://".
  # Replace the scheme so JuiceFS connects via TLS.
  metaurl = replace(stackit_valkey_credential.juicefs.uri, "valkeys://", "rediss://")

  # SKE (Gardener) enforces default-deny in kube-system.
  # Pods must carry these labels to open egress to the API server, DNS, and public networks (S3, Key Value Store).
  gardener_network_labels = {
    "networking.gardener.cloud/to-apiserver"       = "allowed"
    "networking.gardener.cloud/to-dns"             = "allowed"
    "networking.gardener.cloud/to-public-networks" = "allowed"
  }
}

# Secret consumed by the JuiceFS CSI driver to connect to the Key Value Store and S3.
resource "kubernetes_secret_v1" "juicefs" {
  metadata {
    name      = "juicefs-secret"
    namespace = "kube-system"
  }

  data = {
    name       = var.juicefs_filesystem_name
    metaurl    = local.metaurl
    storage    = "s3"
    bucket     = "https://object.storage.${var.stackit_region}.onstackit.cloud/${stackit_objectstorage_bucket.juicefs.name}"
    access-key = stackit_objectstorage_credential.juicefs.access_key
    secret-key = stackit_objectstorage_credential.juicefs.secret_access_key
  }

  depends_on = [
    stackit_ske_cluster.this,
    stackit_valkey_credential.juicefs,
    stackit_objectstorage_credential.juicefs,
  ]
}

resource "helm_release" "juicefs_csi" {
  name       = "juicefs-csi-driver"
  namespace  = "kube-system"
  repository = "https://juicedata.github.io/charts/"
  chart      = "juicefs-csi-driver"
  version    = "0.32.5"

  lint    = true
  wait    = true
  timeout = 300

  values = [
    yamlencode({
      controller = { labels = local.gardener_network_labels }
      node       = { labels = local.gardener_network_labels }
      dashboard  = { labels = local.gardener_network_labels }

      # Mount pods are spawned dynamically in kube-system and do not inherit the labels above.
      # Patch them explicitly so DNS and S3/Key Value Store egress work.
      globalConfig = {
        mountPodPatch = [
          { labels = local.gardener_network_labels }
        ]
      }

      # StorageClass is created below with explicit secret references.
      storageClasses = [{ enabled = false }]
    })
  ]

  depends_on = [stackit_ske_cluster.this]
}

resource "kubernetes_storage_class_v1" "juicefs" {
  metadata {
    name = "juicefs-sc"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "false"
    }
  }

  storage_provisioner    = "csi.juicefs.com"
  reclaim_policy         = "Retain"
  volume_binding_mode    = "Immediate"
  allow_volume_expansion = true

  parameters = {
    "csi.storage.k8s.io/provisioner-secret-name"       = kubernetes_secret_v1.juicefs.metadata[0].name
    "csi.storage.k8s.io/provisioner-secret-namespace"  = kubernetes_secret_v1.juicefs.metadata[0].namespace
    "csi.storage.k8s.io/node-publish-secret-name"      = kubernetes_secret_v1.juicefs.metadata[0].name
    "csi.storage.k8s.io/node-publish-secret-namespace" = kubernetes_secret_v1.juicefs.metadata[0].namespace
  }

  depends_on = [helm_release.juicefs_csi]
}
