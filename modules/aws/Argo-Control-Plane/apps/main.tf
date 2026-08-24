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

module "namespace" {
  source = "git::https://github.com/wso2/common-terraform-modules.git//modules/kubernetes/Namespaces?ref=main"

  kubernetes_namespaces = {
    (var.namespace) = {}
  }
}

module "nats" {
  source = "git::https://github.com/wso2/common-terraform-modules.git//modules/helm/Helm-Release?ref=main"

  release_name     = "nats"
  chart_repo       = var.nats_helm_repo
  chart_name       = "nats"
  version_number   = var.nats_chart_version
  namespace        = var.namespace
  create_namespace = false
  values           = var.nats_values

  depends_on = [module.namespace]
}

module "argo_workflows" {
  source = "git::https://github.com/wso2/common-terraform-modules.git//modules/helm/Helm-Release?ref=main"

  release_name     = "argo-workflows"
  chart_repo       = var.argo_helm_repo
  chart_name       = "argo-workflows"
  version_number   = var.argo_workflows_chart_version
  namespace        = var.namespace
  create_namespace = false
  values           = var.argo_workflows_values

  depends_on = [module.namespace]
}

module "argo_events" {
  source = "git::https://github.com/wso2/common-terraform-modules.git//modules/helm/Helm-Release?ref=main"

  release_name     = "argo-events"
  chart_repo       = var.argo_helm_repo
  chart_name       = "argo-events"
  version_number   = var.argo_events_chart_version
  namespace        = var.namespace
  create_namespace = false
  values           = var.argo_events_values

  depends_on = [module.namespace]
}

module "manifests" {
  source   = "git::https://github.com/wso2/common-terraform-modules.git//modules/kubernetes/Manifest?ref=main"
  for_each = { for idx, m in var.manifest_files : idx => m }

  manifest_location = each.value.location
  template_map      = each.value.template_map

  depends_on = [module.nats, module.argo_workflows, module.argo_events]
}
