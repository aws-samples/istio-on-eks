variable "name" {
  description = "Name for project resources"
  type        = string
  default     = "istio-on-eks-04-security"
}

variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "us-west-2"
}

variable "vpc_cidr" {
  description = "CIDR for the VPC"
  type = string
  default = "10.0.0.0/16"
}