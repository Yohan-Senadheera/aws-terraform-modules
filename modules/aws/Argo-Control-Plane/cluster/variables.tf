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
# The control plane fronts SSO login, dispatch, and NATS for every data
# plane - the highest blast-radius component in the system - so unlike the
# per-tier data plane modules, this one is genuinely multi-AZ throughout:
# 3 AZs, 3 private + 3 public subnets, one NAT Gateway per AZ (no shared
# outbound path to lose), one node group spread across all 3 AZs.
#
# --------------------------------------------------------------------------------------

variable "project" {
  type        = string
  description = "Name of the project (used for resource naming/tagging)"
}

variable "environment" {
  type        = string
  description = "Name of the environment"
  default     = "prod"
}

variable "region" {
  type        = string
  description = "Code of the AWS region"
}

variable "application" {
  type        = string
  description = "Purpose tag for the resources created by this module"
  default     = "argo-controlplane"
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to all resources created by this module"
  default     = {}
}

variable "vpc_cidr_block" {
  type        = string
  description = "CIDR block for the control plane's VPC"
}

variable "availability_zones" {
  type        = list(string)
  description = "Exactly 3 availability zones for the control plane's multi-AZ layout"

  validation {
    condition     = length(var.availability_zones) == 3
    error_message = "The control plane is built for exactly 3 AZs to match NATS JetStream's RAFT quorum size."
  }
}

variable "private_subnet_cidr_blocks" {
  type        = list(string)
  description = "One CIDR per AZ for the private (node) subnets, same order as availability_zones"
}

variable "public_subnet_cidr_blocks" {
  type        = list(string)
  description = "One CIDR per AZ for the public (NAT Gateway) subnets, same order as availability_zones"
}

variable "kubernetes_version" {
  type        = string
  description = "Kubernetes version for the EKS cluster"
}

variable "endpoint_public_access" {
  type        = bool
  description = "Whether the EKS API server has a public endpoint"
  default     = false
}

variable "public_access_cidrs" {
  type        = list(string)
  description = "CIDRs allowed to reach the public API endpoint, if enabled"
  default     = []
}

variable "admin_principal_arns" {
  type        = list(string)
  description = "IAM principal ARNs (users/roles) granted EKS cluster-admin access entries (native-IAM cluster access path)"
  default     = []
}

variable "eks_addons" {
  type = list(object({
    name    = string
    version = optional(string)
  }))
  description = "Core EKS addons to install alongside the EBS CSI driver below"
  default = [
    { name = "vpc-cni" },
    { name = "coredns" },
    { name = "kube-proxy" },
  ]
}

variable "node_instance_types" {
  type        = list(string)
  description = "Instance types for the shared node group"
}

variable "node_min_size" {
  type    = number
  default = 3
}

variable "node_max_size" {
  type    = number
  default = 6
}

variable "node_desired_size" {
  type    = number
  default = 3
}

variable "node_capacity_type" {
  type    = string
  default = "ON_DEMAND"
}

variable "security_group_rules" {
  type = list(object({
    direction       = string
    to_port         = number
    from_port       = number
    protocol        = string
    cidr_blocks     = list(string)
    security_groups = list(string)
  }))
  description = "Additional security group rules, beyond the EKS-managed cluster security group"
  default     = []
}
