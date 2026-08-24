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
# Composes the tainted-node-pool + subnet-pinned + NAT-per-tier isolation
# pattern already proven live on the Azure data plane, purely from existing
# generic modules in this repo. Two tiers (stage, prod), each with its own
# private subnet, its own NAT Gateway (own outbound IP), and its own EKS
# managed node group. Prod nodes carry an "env=prod:NO_SCHEDULE" taint so
# only workloads that explicitly tolerate it can land there.
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

# --- Public subnets (NAT Gateway placement only, no workloads) ---

module "stage_public_subnet" {
  source = "../../VPC-Subnet"

  project     = var.project
  environment = var.environment
  region      = var.region
  application = "${var.application}-stage-public"
  tags        = var.tags

  vpc_id                = module.vpc.vpc_id
  availability_zones    = [var.stage_availability_zones[0]]
  cidr_blocks           = [var.stage_public_subnet_cidr_block]
  auto_assign_public_ip = true

  custom_routes = [{
    cidr_block = "0.0.0.0/0"
    ep_type    = "gateway_id"
    ep_id      = module.internet_gateway.gateway_id
  }]
}

module "prod_public_subnet" {
  source = "../../VPC-Subnet"

  project     = var.project
  environment = var.environment
  region      = var.region
  application = "${var.application}-prod-public"
  tags        = var.tags

  vpc_id                = module.vpc.vpc_id
  availability_zones    = [var.prod_availability_zones[0]]
  cidr_blocks           = [var.prod_public_subnet_cidr_block]
  auto_assign_public_ip = true

  custom_routes = [{
    cidr_block = "0.0.0.0/0"
    ep_type    = "gateway_id"
    ep_id      = module.internet_gateway.gateway_id
  }]
}

# --- Per-tier NAT Gateways (own outbound IP each, matching the Azure pattern) ---

module "stage_nat_gateway" {
  source = "../../NAT-Gateway"

  project     = var.project
  environment = var.environment
  region      = var.region
  application = "${var.application}-stage"
  tags        = var.tags

  subnet_id = values(module.stage_public_subnet.subnet_ids)[0]
}

module "prod_nat_gateway" {
  source = "../../NAT-Gateway"

  project     = var.project
  environment = var.environment
  region      = var.region
  application = "${var.application}-prod"
  tags        = var.tags

  subnet_id = values(module.prod_public_subnet.subnet_ids)[0]
}

# --- Private subnets (EKS nodes live here, tier-isolated egress via each
#     tier's own NAT Gateway) ---

module "stage_private_subnet" {
  source = "../../VPC-Subnet"

  project     = var.project
  environment = var.environment
  region      = var.region
  application = "${var.application}-stage"
  tags        = var.tags

  vpc_id             = module.vpc.vpc_id
  availability_zones = var.stage_availability_zones
  cidr_blocks        = var.stage_subnet_cidr_blocks

  custom_routes = [{
    cidr_block = "0.0.0.0/0"
    ep_type    = "nat_gateway_id"
    ep_id      = module.stage_nat_gateway.nat_gateway_id
  }]
}

module "prod_private_subnet" {
  source = "../../VPC-Subnet"

  project     = var.project
  environment = var.environment
  region      = var.region
  application = "${var.application}-prod"
  tags        = var.tags

  vpc_id             = module.vpc.vpc_id
  availability_zones = var.prod_availability_zones
  cidr_blocks        = var.prod_subnet_cidr_blocks

  custom_routes = [{
    cidr_block = "0.0.0.0/0"
    ep_type    = "nat_gateway_id"
    ep_id      = module.prod_nat_gateway.nat_gateway_id
  }]
}

# --- Per-tier security groups (extend the EKS-managed cluster SG, don't
#     replace it - see EKS-Node-Group's security_group_ids description) ---

module "stage_security_group" {
  source = "../../Security-Group"

  project     = var.project
  environment = var.environment
  region      = var.region
  application = "${var.application}-stage"
  description = "Stage-tier data plane nodes"
  tags        = var.tags

  vpc_id = module.vpc.vpc_id
  rules  = var.stage_security_group_rules
}

module "prod_security_group" {
  source = "../../Security-Group"

  project     = var.project
  environment = var.environment
  region      = var.region
  application = "${var.application}-prod"
  description = "Prod-tier data plane nodes"
  tags        = var.tags

  vpc_id = module.vpc.vpc_id
  rules  = var.prod_security_group_rules
}

# --- EKS cluster (uses the private subnets only; self-manages its own IAM
#     role and OIDC provider since cluster_iam_role_arn is left null) ---

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
  cluster_subnet_ids = concat(
    values(module.stage_private_subnet.subnet_ids),
    values(module.prod_private_subnet.subnet_ids),
  )
  authentication_mode                         = "API"
  bootstrap_cluster_creator_admin_permissions = true
  enable_ebs_csi_driver                       = false
}

resource "aws_eks_addon" "core" {
  for_each = { for a in var.eks_addons : a.name => a }

  cluster_name  = module.eks_cluster.eks_cluster_name
  addon_name    = each.value.name
  addon_version = try(each.value.version, null)
  depends_on    = [module.eks_cluster, module.stage_node_group, module.prod_node_group]
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

# --- Node groups: stage (untainted), prod (tainted) ---

module "stage_node_group" {
  source = "../../EKS-Node-Group"

  eks_cluster_name = module.eks_cluster.eks_cluster_name
  node_group_name  = "stage"
  subnet_ids       = values(module.stage_private_subnet.subnet_ids)
  tags             = var.tags

  instance_types  = var.stage_node_instance_types
  capacity_type   = var.stage_node_capacity_type
  min_size        = var.stage_node_min_size
  max_size        = var.stage_node_max_size
  desired_size    = var.stage_node_desired_size
  max_unavailable = 1
  k8s_version     = var.kubernetes_version

  security_group_ids = [
    module.eks_cluster.eks_security_group_id,
    module.stage_security_group.security_group_id,
  ]

  labels = { tier = "stage" }
}

module "prod_node_group" {
  source = "../../EKS-Node-Group"

  eks_cluster_name = module.eks_cluster.eks_cluster_name
  node_group_name  = "prod"
  subnet_ids       = values(module.prod_private_subnet.subnet_ids)
  tags             = var.tags

  instance_types  = var.prod_node_instance_types
  capacity_type   = var.prod_node_capacity_type
  min_size        = var.prod_node_min_size
  max_size        = var.prod_node_max_size
  desired_size    = var.prod_node_desired_size
  max_unavailable = 1
  k8s_version     = var.kubernetes_version

  security_group_ids = [
    module.eks_cluster.eks_security_group_id,
    module.prod_security_group.security_group_id,
  ]

  taints = {
    env = {
      value  = var.prod_node_taint_value
      effect = "NO_SCHEDULE"
    }
  }

  labels = { tier = "prod" }
}
