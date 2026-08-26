# -------------------------------------------------------------------------------------
#
# Copyright (c) 2026, WSO2 LLC. (https://www.wso2.com) All Rights Reserved.
#
# WSO2 LLC. licenses this file to you under the Apache License,
# Version 2.0 (the "License"); you may not use this file except
# in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied. See the License for the
# specific language governing permissions and limitations
# under the License.
#
# --------------------------------------------------------------------------------------
#
# Raw kubernetes/helm resources, no dependency on wso2/common-terraform-modules.
#
# --------------------------------------------------------------------------------------

resource "kubernetes_namespace_v1" "this" {
  metadata {
    name = var.namespace
  }
}

resource "helm_release" "nats" {
  name             = "nats"
  repository       = var.nats_helm_repo
  chart            = "nats"
  version          = var.nats_chart_version
  namespace        = var.namespace
  create_namespace = false
  values           = var.nats_values

  depends_on = [kubernetes_namespace_v1.this]
}

resource "helm_release" "argo_workflows" {
  name             = "argo-workflows"
  repository       = var.argo_helm_repo
  chart            = "argo-workflows"
  version          = var.argo_workflows_chart_version
  namespace        = var.namespace
  create_namespace = false
  values           = var.argo_workflows_values

  depends_on = [kubernetes_namespace_v1.this]
}

resource "helm_release" "argo_events" {
  name             = "argo-events"
  repository       = var.argo_helm_repo
  chart            = "argo-events"
  version          = var.argo_events_chart_version
  namespace        = var.namespace
  create_namespace = false
  values           = var.argo_events_values

  depends_on = [kubernetes_namespace_v1.this]
}

# Several real pipeline manifests are multi-document YAML - yamldecode()
# only parses a single document, so each file is split on a bare "---"
# line first (same fix as the data-plane apps modules).
locals {
  manifest_documents = flatten([
    for idx, m in var.manifest_files : [
      for doc_idx, doc in [
        for chunk in split("\n---\n", "\n${templatefile(m.location, m.template_map)}") : chunk
        if trimspace(chunk) != ""
        ] : {
        key      = "${idx}-${doc_idx}"
        manifest = yamldecode(doc)
      }
    ]
  ])
}

resource "kubernetes_manifest" "this" {
  for_each = { for d in local.manifest_documents : d.key => d.manifest }

  manifest = each.value

  depends_on = [helm_release.nats, helm_release.argo_workflows, helm_release.argo_events]
}
