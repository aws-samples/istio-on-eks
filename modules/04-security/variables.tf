variable "eks_cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "istio"
}

variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "us-west-2"
}

variable "aws_privateca_arn" {
    description = "Use an existing ACM PCA ARN when setting up peer authentication."
    type = string
    default = null
}

variable "aws_privateca_cn" {
  type        = string
  description = "Common Name (CN) when creating a new ACM PCA when setting up peer authentication."
  default     = "Istio on EKS PrivateCA"
}