provider "aws" {
  region = local.region
}

data "aws_caller_identity" "current" {}
data "aws_availability_zones" "available" {}

locals {
  foo_name   = "foo-eks-cluster"
  bar_name   = "bar-eks-cluster"
  region = "eu-west-2"

  foo_vpc_cidr = "10.2.0.0/16"
  bar_vpc_cidr = "10.3.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)

  account_id      = data.aws_caller_identity.current.account_id
  
}

################################################################################
# FOO VPC
################################################################################

module "foo_vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = local.foo_name
  cidr = local.foo_vpc_cidr
  
  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(local.foo_vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.foo_vpc_cidr, 8, k + 48)]

  enable_nat_gateway = true
  single_nat_gateway = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }

  tags = {
    Blueprint  = local.foo_name
    GithubRepo = "github.com/aws-ia/terraform-aws-eks-blueprints"
  }
}

################################################################################
# BAR VPC
################################################################################

module "bar_vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = local.bar_name
  cidr = local.bar_vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(local.bar_vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.bar_vpc_cidr, 8, k + 48)]

  enable_nat_gateway = true
  single_nat_gateway = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }

  tags = {
    Blueprint  = local.bar_name
    GithubRepo = "github.com/aws-ia/terraform-aws-eks-blueprints"
  }
}

################################################################################
# Create VPC peering and update the private subnets route tables
################################################################################

resource "aws_vpc_peering_connection" "foo_bar" {
  peer_owner_id = local.account_id
  vpc_id      = module.foo_vpc.vpc_id
  peer_vpc_id = module.bar_vpc.vpc_id
  auto_accept = true
  tags = {
    Name = "foo-bar"
  }
}

resource "aws_vpc_peering_connection_options" "foo_bar" {
  vpc_peering_connection_id = aws_vpc_peering_connection.foo_bar.id
  accepter {
    allow_remote_vpc_dns_resolution = true
  }
  requester {
   allow_remote_vpc_dns_resolution = true 
  }
}

resource "aws_route" "foo_bar" {
  route_table_id = module.foo_vpc.private_route_table_ids[0]
  destination_cidr_block = local.bar_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection_options.foo_bar.id
}

resource "aws_route" "bar_foo" {
  route_table_id = module.bar_vpc.private_route_table_ids[0]
  destination_cidr_block = local.foo_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection_options.foo_bar.id
}

################################################################################
# Foo cluster additional security group for cross cluster communication
################################################################################

resource "aws_security_group" "foo_eks_cluster_additional_sg" {
  name        = "foo_eks_cluster_additional_sg"
  description = "Allow communication from bar eks cluster SG to foo eks cluster SG"
  vpc_id      = module.foo_vpc.vpc_id
  tags = {
    Name = "foo_eks_cluster_additional_sg"
  }
}

resource "aws_vpc_security_group_egress_rule" "foo_eks_cluster_additional_sg_allow_all_4" {
  security_group_id = aws_security_group.foo_eks_cluster_additional_sg.id

  ip_protocol = "-1"
  cidr_ipv4   = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "foo_eks_cluster_additional_sg_allow_all_6" {
  security_group_id = aws_security_group.foo_eks_cluster_additional_sg.id

  ip_protocol = "-1"
  cidr_ipv6   = "::/0"
}

################################################################################
# Bar cluster additional security group for cross cluster communication
################################################################################

resource "aws_security_group" "bar_eks_cluster_additional_sg" {
  name        = "bar_eks_cluster_additional_sg"
  description = "Allow communication from foo eks cluster SG to bar eks cluster SG"
  vpc_id      = module.bar_vpc.vpc_id
  tags = {
    Name = "bar_eks_cluster_additional_sg"
  }
}

resource "aws_vpc_security_group_egress_rule" "bar_eks_cluster_additional_sg_allow_all_4" {
  security_group_id = aws_security_group.bar_eks_cluster_additional_sg.id

  ip_protocol = "-1"
  cidr_ipv4   = "0.0.0.0/0"
}
resource "aws_vpc_security_group_egress_rule" "bar_eks_cluster_additional_sg_allow_all_6" {
  security_group_id = aws_security_group.bar_eks_cluster_additional_sg.id

  ip_protocol = "-1"
  cidr_ipv6   = "::/0"
}

################################################################################
# cross SG  ingress rules bar eks cluster allow to foo eks cluster
################################################################################

resource "aws_vpc_security_group_ingress_rule" "bar_eks_cluster_to_cluster_1" {
  security_group_id = aws_security_group.foo_eks_cluster_additional_sg.id

  cidr_ipv4   = local.bar_vpc_cidr
  ip_protocol = "-1"
}

################################################################################
# cross SG  ingress rules foo eks cluster allow to bar eks cluster
################################################################################

resource "aws_vpc_security_group_ingress_rule" "foo_eks_cluster_to_cluster_2" {
  security_group_id = aws_security_group.bar_eks_cluster_additional_sg.id

  cidr_ipv4   = local.foo_vpc_cidr
  ip_protocol = "-1"
}