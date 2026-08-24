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

module "vpc" {
  source = "../../VPC"

  project     = var.project
  environment = var.environment
  region      = var.region
  application = var.application
  tags        = var.tags

  vpc_cidr_block = var.vpc_cidr_block
}

module "internet_gateway" {
  source = "../../Gateway"

  project     = var.project
  environment = var.environment
  region      = var.region
  application = var.application
  tags        = var.tags

  vpc_ids = [module.vpc.vpc_id]
}

# --- Public subnets (one per AZ, NAT Gateway placement only) ---

module "public_subnets" {
  source   = "../../VPC-Subnet"
  for_each = { for idx, az in var.availability_zones : az => idx }

  project     = var.project
  environment = var.environment
  region      = var.region
  application = "${var.application}-public"
  tags        = var.tags

  vpc_id                = module.vpc.vpc_id
  availability_zones    = [each.key]
  cidr_blocks           = [var.public_subnet_cidr_blocks[each.value]]
  auto_assign_public_ip = true

  custom_routes = [{
    cidr_block = "0.0.0.0/0"
    ep_type    = "gateway_id"
    ep_id      = module.internet_gateway.gateway_id
  }]
}

# --- One NAT Gateway per AZ - no shared outbound path to lose ---

module "nat_gateways" {
  source   = "../../NAT-Gateway"
  for_each = { for idx, az in var.availability_zones : az => idx }

  project     = var.project
  environment = var.environment
  region      = var.region
  application = "${var.application}-${each.key}"
  tags        = var.tags

  subnet_id = values(module.public_subnets[each.key].subnet_ids)[0]
}

# --- Private subnets (nodes live here, each AZ egresses via its own NAT) ---

module "private_subnets" {
  source   = "../../VPC-Subnet"
  for_each = { for idx, az in var.availability_zones : az => idx }

  project     = var.project
  environment = var.environment
  region      = var.region
  application = var.application
  tags        = var.tags

  vpc_id             = module.vpc.vpc_id
  availability_zones = [each.key]
  cidr_blocks        = [var.private_subnet_cidr_blocks[each.value]]

  custom_routes = [{
    cidr_block = "0.0.0.0/0"
    ep_type    = "nat_gateway_id"
    ep_id      = module.nat_gateways[each.key].nat_gateway_id
  }]
}

module "security_group" {
  source = "../../Security-Group"

  project     = var.project
  environment = var.environment
  region      = var.region
  application = var.application
  description = "Control plane nodes"
  tags        = var.tags

  vpc_id = module.vpc.vpc_id
  rules  = var.security_group_rules
}

# --- EKS cluster, spanning all 3 private subnets ---

module "eks_cluster" {
  source = "../../EKS-Cluster"

  project     = var.project
  environment = var.environment
  region      = var.region
  application = var.application
  tags        = var.tags

  kubernetes_version      = var.kubernetes_version
  eks_vpc_id              = module.vpc.vpc_id
  endpoint_private_access = true
  endpoint_public_access  = var.endpoint_public_access
  public_access_cidrs     = var.public_access_cidrs
  service_ipv4_cidr       = null
  cluster_subnet_ids      = [for az in var.availability_zones : values(module.private_subnets[az].subnet_ids)[0]]

  authentication_mode                         = "API"
  bootstrap_cluster_creator_admin_permissions = true
  enable_ebs_csi_driver                       = true
}

resource "aws_eks_addon" "core" {
  for_each = { for a in var.eks_addons : a.name => a }

  cluster_name  = module.eks_cluster.eks_cluster_name
  addon_name    = each.value.name
  addon_version = try(each.value.version, null)
  depends_on    = [module.eks_cluster, module.node_group]
}

resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name             = module.eks_cluster.eks_cluster_name
  addon_name               = "aws-ebs-csi-driver"
  service_account_role_arn = module.eks_cluster.ebs_csi_driver_role_arn
  depends_on               = [module.eks_cluster, module.node_group]
}

# --- Cluster-admin access via native IAM (no unified cross-cloud identity) ---

resource "aws_eks_access_entry" "admin" {
  for_each = toset(var.admin_principal_arns)

  cluster_name  = module.eks_cluster.eks_cluster_name
  principal_arn = each.value
  type          = "STANDARD"
  depends_on    = [module.eks_cluster]
}

resource "aws_eks_access_policy_association" "admin" {
  for_each = toset(var.admin_principal_arns)

  cluster_name  = module.eks_cluster.eks_cluster_name
  principal_arn = each.value
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.admin]
}

# --- One node group, spread across all 3 AZs ---

module "node_group" {
  source = "../../EKS-Node-Group"

  eks_cluster_name = module.eks_cluster.eks_cluster_name
  node_group_name  = "system"
  subnet_ids       = [for az in var.availability_zones : values(module.private_subnets[az].subnet_ids)[0]]
  tags             = var.tags

  instance_types  = var.node_instance_types
  capacity_type   = var.node_capacity_type
  min_size        = var.node_min_size
  max_size        = var.node_max_size
  desired_size    = var.node_desired_size
  max_unavailable = 1
  k8s_version     = var.kubernetes_version

  security_group_ids = [
    module.eks_cluster.eks_security_group_id,
    module.security_group.security_group_id,
  ]
}
