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
# Manual, out-of-band distribution: the security review doc itself
# describes NATS client certs as "distributed to each site out-of-band and
# never committed to git" - these outputs are that handoff point. Copy the
# relevant identity's values into that data plane's own environment
# (terraform.tfvars), same pattern already used for
# control_plane_tunnel_host. Marked sensitive so `terraform output`
# doesn't print them by default - use `terraform output -raw` per field.
#
# --------------------------------------------------------------------------------------

output "nats_client_cert_pems" {
  value = {
    for identity in var.nats_client_identities :
    identity => try(data.kubernetes_secret_v1.nats_client_certificate[identity].data["tls.crt"], null)
  }
  sensitive = true
}

output "nats_client_key_pems" {
  value = {
    for identity in var.nats_client_identities :
    identity => try(data.kubernetes_secret_v1.nats_client_certificate[identity].data["tls.key"], null)
  }
  sensitive = true
}

output "nats_client_ca_pems" {
  value = {
    for identity in var.nats_client_identities :
    identity => try(data.kubernetes_secret_v1.nats_client_certificate[identity].data["ca.crt"], null)
  }
  sensitive = true
}
