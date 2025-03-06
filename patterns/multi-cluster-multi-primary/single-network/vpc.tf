################################################################################
# VPC
################################################################################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.19.0"

  name = "shared-vpc"
  cidr = local.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 48)]

  enable_nat_gateway = true
  single_nat_gateway = true

  # IPv6 settings
  enable_ipv6            = local.vpc_IPv6
  create_egress_only_igw = local.vpc_IPv6

  public_subnet_ipv6_prefixes                    = local.vpc_IPv6 == true ? [0, 1, 2] : []
  public_subnet_assign_ipv6_address_on_creation  = local.vpc_IPv6
  private_subnet_ipv6_prefixes                   = local.vpc_IPv6 == true ? [3, 4, 5] : []
  private_subnet_assign_ipv6_address_on_creation = local.vpc_IPv6

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }

  tags = merge({
    Name = "shared-vpc"
  }, local.tags)
}