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
# Unlike the data plane apps modules, this one installs a single namespaced
# Argo Workflows/Events release (the control plane isn't per-tier) plus
# NATS/JetStream, and defaults its Helm values toward the HA topology the
# control plane needs: workflow-controller with leader election, NATS as a
# 3-replica StatefulSet. The actual per-AZ pod spread depends on the values
# passed in - defaults here are conservative starting points, override via
# the *_values variables for the real chart's exact value paths.
#
# --------------------------------------------------------------------------------------

variable "namespace" {
  type        = string
  description = "Kubernetes namespace for the control plane's Argo Workflows + Argo Events release"
  default     = "argo"
}

variable "argo_workflows_chart_version" {
  type    = string
  default = null
}

variable "argo_events_chart_version" {
  type    = string
  default = null
}

variable "nats_chart_version" {
  type    = string
  default = null
}

variable "argo_helm_repo" {
  type    = string
  default = "https://argoproj.github.io/argo-helm"
}

variable "nats_helm_repo" {
  type    = string
  default = "https://nats-io.github.io/k8s/helm/charts/"
}

variable "argo_workflows_values" {
  type        = list(string)
  description = "Helm values overrides (YAML strings, later entries win) for argo-workflows. Should include workflow-controller replicas>=2 with leader election for HA."
  default     = []
}

variable "argo_events_values" {
  type        = list(string)
  description = "Helm values overrides (YAML strings, later entries win) for argo-events"
  default     = []
}

variable "nats_values" {
  type        = list(string)
  description = "Helm values overrides (YAML strings, later entries win) for the nats chart. Should set JetStream replicas=3 with pod anti-affinity/topologySpreadConstraints across AZs, and a PVC-backed persistent store."
  default     = []
}

variable "install_cert_manager" {
  type        = bool
  description = "Install cert-manager and bootstrap a private client-CA for NATS mTLS - the security review doc's stated mechanism (\"client TLS certificates signed by a dedicated client-CA\") for the 5 identities: this control plane's own wildcard, plus one per data plane. cert-manager renews before expiry on its own, which is what makes rotation actually automatic (vs. a one-time tls provider generation)."
  default     = true
}

variable "cert_manager_chart_version" {
  type    = string
  default = null
}

variable "cert_manager_helm_repo" {
  type    = string
  default = "https://charts.jetstack.io"
}

variable "cert_manager_namespace" {
  type    = string
  default = "cert-manager"
}

variable "nats_client_identities" {
  type        = list(string)
  description = "commonName for each data-plane NATS client certificate cert-manager issues, e.g. [\"azure-stage\", \"azure-prod\", \"aws-stage\", \"aws-prod\"]. One Certificate per entry; the resulting cert/key end up in a Kubernetes Secret named \"nats-client-<entry>\" in var.namespace, readable via this module's nats_client_cert_pems/nats_client_key_pems outputs for manual, out-of-band distribution to each data plane's own environment - same pattern already used for control_plane_tunnel_host."
  default     = []
}

variable "manifest_files" {
  type = list(object({
    location     = string
    template_map = optional(map(string), {})
  }))
  description = "Additional Kubernetes manifests to apply - dispatch-namespace RBAC, the SSO gateway (oauth2-proxy/credential-injector/link-resolver/submit-attributor), Ingress/Service for the real Load Balancer replacing the current single-VM Elastic IP. Content and ordering are entirely caller-supplied."
  default     = []
}
