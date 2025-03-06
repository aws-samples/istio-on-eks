locals {
  region = "us-west-2"
  azs    = slice(data.aws_availability_zones.available.names, 0, 3)

  # VPC specific settings
  vpc_cidr = "10.0.0.0/16"
  vpc_IPv6 = local.eks_1_IPv6 || local.eks_2_IPv6

  # EKS specific settings
  eks_1_IPv6          = true
  eks_2_IPv6          = true
  eks_1_name          = "eks-1"
  eks_2_name          = "eks-2"
  eks_cluster_version = "1.32"

  # Istio specific settings
  meshID       = "mesh1"
  networkName  = "network1"
  clusterName1 = "cluster1"
  clusterName2 = "cluster2"

  istio_chart_url     = "https://istio-release.storage.googleapis.com/charts"
  istio_chart_version = "1.24.3"

  tags = {
    GithubRepo = "github.com/aws_ia/terraform-aws-eks-blueprints"
  }
}