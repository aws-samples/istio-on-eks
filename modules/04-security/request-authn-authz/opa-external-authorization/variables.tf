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