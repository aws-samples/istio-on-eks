provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project = "Istio-on-EKS"
      GithubRepo = "github.com/aws-samples/istio-on-eks"
    }
  }
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.this.token
  
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

provider "kubectl" {
  apply_retry_count      = 10
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  load_config_file       = false
  token                  = data.aws_eks_cluster_auth.this.token
}

data "aws_partition" "current" {}

data "aws_caller_identity" "current" {}

data "aws_eks_cluster" "this" {
  name = var.eks_cluster_name
}

data "aws_eks_cluster_auth" "this" {
  name = var.eks_cluster_name
}

locals {
  eks_cluster_oidc_provider_arn = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${replace(data.aws_eks_cluster.this.identity[0].oidc[0].issuer, "/^https:///", "")}"
  eks_cluster_config = {
    name = data.aws_eks_cluster.this.name
    version = data.aws_eks_cluster.this.version
    endpoint = data.aws_eks_cluster.this.endpoint
    oidc_provider_arn = local.eks_cluster_oidc_provider_arn
  }
}

module setup_peer_authentication {
  source = "./peer-authentication"

  aws_region = var.aws_region
  eks_cluster_config = local.eks_cluster_config

  aws_privateca_arn = var.aws_privateca_arn
  aws_privateca_cn = var.aws_privateca_cn
}

module setup_opa_external_authorization {
  source = "./request-authn-authz/opa-external-authorization"

  aws_region = var.aws_region
  eks_cluster_config = local.eks_cluster_config
}

module setup_request_authn_authz {
  source = "./request-authn-authz"

  aws_region = var.aws_region

  eks_cluster_config = local.eks_cluster_config
}