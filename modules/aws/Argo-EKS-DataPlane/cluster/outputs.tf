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

output "eks_cluster_name" {
  value = module.eks_cluster.eks_cluster_name
}

output "eks_cluster_arn" {
  value = module.eks_cluster.eks_cluster_arn
}

output "eks_cluster_endpoint" {
  value = module.eks_cluster.eks_cluster_endpoint
}

output "eks_base64_encoded_ca_cert" {
  value = module.eks_cluster.eks_base64_encoded_ca_cert
}

output "oidc_provider_arn" {
  value = module.eks_cluster.oidc_provider_arn
}

output "oidc_provider_url" {
  value = module.eks_cluster.oidc_provider_url
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "stage_subnet_ids" {
  value = values(module.stage_private_subnet.subnet_ids)
}

output "prod_subnet_ids" {
  value = values(module.prod_private_subnet.subnet_ids)
}

output "stage_nat_gateway_public_ip" {
  value = module.stage_nat_gateway.public_ip
}

output "prod_nat_gateway_public_ip" {
  value = module.prod_nat_gateway.public_ip
}
