variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "us-west-2"
}

variable "eks_cluster_config" {
  description = "EKS cluster config"
  type = object({
    name = string
    endpoint = string
    version = string
    oidc_provider_arn = string
  })
}

variable "aws_privateca_arn" {
    description = "Use an existing ACM PCA ARN"
    type = string
    default = null
}

variable "aws_privateca_cn" {
  type        = string
  description = "Common Name (CN) when creating a new ACM PCA."
  default     = "Istio on EKS PrivateCA"
}