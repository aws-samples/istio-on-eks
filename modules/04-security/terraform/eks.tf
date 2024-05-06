module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name                   = var.name
  cluster_version                = "1.29"
  cluster_endpoint_public_access = true

  # Give the Terraform identity admin access to the cluster
  # which will allow resources to be deployed into the cluster
  enable_cluster_creator_admin_permissions = true

  cluster_addons = {
    coredns    = {}
    kube-proxy = {}
    vpc-cni    = {}
  }

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  eks_managed_node_groups = {
    initial = {
      instance_types = ["m5.large"]

      min_size     = 1
      max_size     = 5
      desired_size = 2
    }
  }

  #  EKS K8s API cluster needs to be able to talk with the EKS worker nodes with port 15017/TCP and 15012/TCP which is used by Istio
  #  Istio in order to create sidecar needs to be able to communicate with webhook and for that network passage to EKS is needed.
  node_security_group_additional_rules = {
    ingress_15017 = {
      description                   = "Cluster API - Istio Webhook namespace.sidecar-injector.istio.io"
      protocol                      = "TCP"
      from_port                     = 15017
      to_port                       = 15017
      type                          = "ingress"
      source_cluster_security_group = true
    }
    ingress_15012 = {
      description                   = "Cluster API to nodes ports/protocols"
      protocol                      = "TCP"
      from_port                     = 15012
      to_port                       = 15012
      type                          = "ingress"
      source_cluster_security_group = true
    }
  }

  depends_on = [module.vpc]
}

resource "null_resource" "export_kube_config" {
  provisioner "local-exec" {
    command     = "aws eks --region=${var.aws_region} update-kubeconfig --name=${module.eks.cluster_name}"
    interpreter = ["/bin/bash", "-c"]
    environment = {
      AWS_REGION = var.aws_region
    }
  }
}

# Create AWS Private CA in short-lived CA mode for mTLS
# https://aws.github.io/aws-eks-best-practices/security/docs/network/#short-lived-ca-mode-for-mutual-tls-between-workloads
resource "aws_acmpca_certificate_authority" "mtls" {
  type = "ROOT"
  usage_mode = "SHORT_LIVED_CERTIFICATE"

  certificate_authority_configuration {
    key_algorithm     = "RSA_4096"
    signing_algorithm = "SHA512WITHRSA"

    subject {
      common_name = var.name
    }
  }
}

# Issue Root CA Certificate
resource "aws_acmpca_certificate" "mtls" {
  certificate_authority_arn   = aws_acmpca_certificate_authority.mtls.arn
  certificate_signing_request = aws_acmpca_certificate_authority.mtls.certificate_signing_request
  signing_algorithm           = "SHA512WITHRSA"

  template_arn = "arn:aws:acm-pca:::template/RootCACertificate/V1"

  validity {
    type  = "YEARS"
    value = 10
  }
}

# Associate the Root CA Certificate with the CA
resource "aws_acmpca_certificate_authority_certificate" "mtls" {
  certificate_authority_arn = aws_acmpca_certificate_authority.mtls.arn

  certificate       = aws_acmpca_certificate.mtls.certificate
  certificate_chain = aws_acmpca_certificate.mtls.certificate_chain
}

resource "kubernetes_namespace_v1" "aws_privateca_issuer" {
  metadata {
    name = "aws-privateca-issuer"
  }
}

resource "kubernetes_namespace_v1" "cert_manager" {
  metadata {
    name = "cert-manager"
  }
}

resource "kubernetes_namespace_v1" "external_secrets" {
  metadata {
    name = "external-secrets"
  }
}

resource "kubernetes_namespace_v1" "gatekeeper" {
  metadata {
    name = "gatekeeper-system"
    labels = {
      "admission.gatekeeper.sh/ignore" = "no-self-managing"
    }
  }
}

module "ebs_csi_driver_irsa" {
  source = "github.com/aws-ia/terraform-aws-eks-blueprints//modules/irsa?ref=v4.32.1"

  create_kubernetes_namespace       = false
  create_kubernetes_service_account = false
  kubernetes_namespace              = "kube-system"
  kubernetes_service_account        = "ebs-csi-controller-sa"
  irsa_iam_policies = [
    "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  ]

  eks_cluster_id        = module.eks.cluster_name
  eks_oidc_provider_arn = module.eks.oidc_provider_arn
}

# module "eks_blueprints_addons_core" {
#   source  = "aws-ia/eks-blueprints-addons/aws"
#   version = "~> 1.16.2"

#   cluster_name      = module.eks.cluster_name
#   cluster_endpoint  = module.eks.cluster_endpoint
#   cluster_version   = module.eks.cluster_version
#   oidc_provider_arn = module.eks.oidc_provider_arn

#   # Add-ons
#   enable_aws_load_balancer_controller = true
# }



module "eks_blueprints_addons" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.16.2"

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn

  # EKS Add-on
  eks_addons = {
    aws-ebs-csi-driver = {
      preserve                 = false
      service_account_role_arn = module.ebs_csi_driver_irsa.irsa_iam_role_arn
    }
  }

  enable_external_secrets = true
  external_secrets = {
    namespace        = kubernetes_namespace_v1.external_secrets.metadata[0].name
    create_namespace = false
  }

  enable_gatekeeper = true
  gatekeeper = {
    namespace        = kubernetes_namespace_v1.gatekeeper.metadata[0].name
    create_namespace = false
  }

  enable_secrets_store_csi_driver              = true
  enable_secrets_store_csi_driver_provider_aws = true

  enable_cert_manager = true
  cert_manager = {
    namespace        = kubernetes_namespace_v1.cert_manager.metadata[0].name
    create_namespace = false
  }

  enable_aws_privateca_issuer = true
  aws_privateca_issuer = {
    acmca_arn        = aws_acmpca_certificate_authority.mtls.arn
    namespace        = kubernetes_namespace_v1.aws_privateca_issuer.metadata[0].name
    create_namespace = false
  }

  helm_releases = {
    cert-manager-csi-driver = {
      description   = "Cert Manager CSI Driver Add-on"
      chart         = "cert-manager-csi-driver"
      namespace     = "cert-manager"
      chart_version = "v0.5.0"
      repository    = "https://charts.jetstack.io"
    }
  }

  depends_on = [ module.aws_load_balancer_controller, aws_acmpca_certificate_authority_certificate.mtls ]
}