locals {
  region = "us-west-2"
  azs    = slice(data.aws_availability_zones.available.names, 0, 3)

  # VPC specific settings
  vpc_1_cidr = "10.9.0.0/16"
  vpc_2_cidr = "10.8.0.0/16"

  # EKS specific settings
  eks_1_name          = "cluster-1"
  eks_2_name          = "cluster-2"
  eks_cluster_version = "1.30"

  # Istio specific settings
  meshID       = "mesh1"
  networkName1 = "network1"
  networkName2 = "network2"
  clusterName1 = "cluster1"
  clusterName2 = "cluster2"

  istio_chart_url     = "https://istio-release.storage.googleapis.com/charts"
  istio_chart_version = "1.23"

  tags = {
    GithubRepo = "github.com/aws_ia/terraform-aws-eks-blueprints"
  }
}
