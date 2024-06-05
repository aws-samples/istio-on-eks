provider "aws" {
  region = local.region
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

provider "kubectl" {
  apply_retry_count      = 10
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  load_config_file       = false
  token                  = data.aws_eks_cluster_auth.this.token
}

# data "terraform_remote_state" "foo_vpc" {
  # backend = "local"
# 
  # config = {
    # path = "${path.module}/../0.vpc/terraform.tfstate"
  # }
# }

data "terraform_remote_state" "bar_vpc" {
  backend = "local"

  config = {
    path = "${path.module}/../0.vpc/terraform.tfstate"
  }
}

data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

data "aws_availability_zones" "available" {}

locals {
  name   = "bar-eks-cluster"
  region = "eu-west-2"

  cluster_version = "1.29"

  # foo_additional_sg_id = data.terraform_remote_state.foo_vpc.outputs.foo_additional_sg_id
  bar_additional_sg_id = data.terraform_remote_state.bar_vpc.outputs.bar_additional_sg_id
  
  istio_namespace = "istio-system"

  tags = {
    Blueprint  = local.name
    GithubRepo = "github.com/aws-ia/terraform-aws-eks-blueprints"
  }
}

################################################################################
# Cluster
################################################################################

#tfsec:ignore:aws-eks-enable-control-plane-logging
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.16"

  cluster_name                   = local.name
  cluster_version                = local.cluster_version
  cluster_endpoint_public_access = true
  
  vpc_id     = data.terraform_remote_state.bar_vpc.outputs.bar_vpc_id
  subnet_ids = data.terraform_remote_state.bar_vpc.outputs.bar_subnet_ids

  manage_aws_auth_configmap = true

  node_security_group_additional_rules = {
    ingress_self_all = {
      description = "Node to node all ports/protocols"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }
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
    # ingress_15021 = {
      # description                   = "Cluster API to nodes ports/protocols"
      # protocol                      = "TCP"
      # from_port                     = 15021
      # to_port                       = 15021
      # type                          = "ingress"
    # source_cluster_security_group = true
    # }
    egress_all = {
      description      = "Node all egress"
      protocol         = "-1"
      from_port        = 0
      to_port          = 0
      type             = "egress"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
    }
  }

  eks_managed_node_groups = {
    bar_nodes = {
      instance_types = ["m5.large"]

      min_size     = 1
      max_size     = 2
      desired_size = 2
      vpc_security_group_ids = [local.bar_additional_sg_id]
    }

    bar_spire_server = {
      instance_types = ["m5.large"]

      min_size     = 1
      max_size     = 1
      desired_size = 1
      vpc_security_group_ids = [local.bar_additional_sg_id]

      labels = {
        dedicated = "spire-server"
      }

      taints = [
        {
          key    = "dedicated"
          value  = "spire-server"
          effect = "NO_EXECUTE"
        }
      ]
    }
  }

  tags = local.tags
}

################################################################################
# Kubernetes Addons
################################################################################

module "eks_blueprints_addons" {
  source = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.3"

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn

  # Add-ons
  eks_addons = {
    aws-ebs-csi-driver = {
      service_account_role_arn = module.ebs_csi_driver_irsa.iam_role_arn
    }
    vpc-cni    = {
      preserve = true
    }
    kube-proxy = {
      preserve = true
    }
    coredns    = {
      preserve = true
    } 
  }
  
  enable_aws_load_balancer_controller = true
  enable_cert_manager = true
  cert_manager = {
    chart_version    = "v1.13.1"
  }

  tags = local.tags
}

################################################################################
# Supporting Resources
################################################################################

module "ebs_csi_driver_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.20"

  role_name_prefix = "${module.eks.cluster_name}-ebs-csi-driver-"

  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = local.tags
}

#---------------------------------------------------------------
# GP3 Encrypted Storage Class
#---------------------------------------------------------------
resource "kubernetes_annotations" "gp2_default" {
  annotations = {
    "storageclass.kubernetes.io/is-default-class" : "false"
  }
  api_version = "storage.k8s.io/v1"
  kind        = "StorageClass"
  metadata {
    name = "gp2"
  }
  force = true

  depends_on = [module.eks]
}

resource "kubernetes_storage_class" "ebs_csi_encrypted_gp3_storage_class" {
  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" : "true"
    }
  }

  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  allow_volume_expansion = true
  volume_binding_mode    = "WaitForFirstConsumer"
  parameters = {
    fsType    = "xfs"
    encrypted = true
    type      = "gp3"
  }

  depends_on = [kubernetes_annotations.gp2_default]
}

#-------------------------------------------------------
# Configure Root CA self-signed certificate
#------------------------------------------------------
resource "kubernetes_namespace" "istio_system" {
  metadata {
    name = local.istio_namespace
  }
  depends_on = [module.eks.cluster_name]
}

data "kubectl_path_documents" "self_signed_ca" {
  pattern = "${path.module}/cert-manager-manifests/self-signed-ca.yaml"
}

resource "kubectl_manifest" "self_signed_ca" {
  for_each  = toset(data.kubectl_path_documents.self_signed_ca.documents)
  yaml_body = each.value

  depends_on = [module.eks_blueprints_addons]
}

data "kubectl_path_documents" "istio_cert" {
  pattern = "${path.module}/cert-manager-manifests/istio-cert.yaml"
}

resource "kubectl_manifest" "istio_cert" {
  for_each  = toset(data.kubectl_path_documents.istio_cert.documents)
  yaml_body = each.value

  depends_on = [module.eks_blueprints_addons]
}
