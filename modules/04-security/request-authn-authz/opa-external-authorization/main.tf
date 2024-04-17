resource "kubernetes_namespace_v1" "gatekeeper" {
  metadata {
    name = "gatekeeper-system"
    labels = {
      "admission.gatekeeper.sh/ignore" = "no-self-managing"
    }
  }
}

module "eks_blueprints_addons" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.16.2"

  cluster_name      = var.eks_cluster_config.name
  cluster_endpoint  = var.eks_cluster_config.endpoint
  cluster_version   = var.eks_cluster_config.version
  oidc_provider_arn = var.eks_cluster_config.oidc_provider_arn

  enable_gatekeeper = true
  gatekeeper = {
    namespace        = kubernetes_namespace_v1.gatekeeper.metadata[0].name
    create_namespace = false
  }
}