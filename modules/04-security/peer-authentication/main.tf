locals {
  istio_chart_url     = "https://istio-release.storage.googleapis.com/charts"
  istio_chart_version = "1.20.2"
  istio_chart_description = "Enable ACM PCA issuer integration through cert-manager-istio-csr"
}

data "aws_acmpca_certificate_authority" "this" {
  count = var.aws_privateca_arn != null ? 1 : 0

  arn = var.aws_privateca_arn
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

module "eks_blueprints_addons_cert_manager" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.16.2"

  cluster_name      = var.eks_cluster_config.name
  cluster_endpoint  = var.eks_cluster_config.endpoint
  cluster_version   = var.eks_cluster_config.version
  oidc_provider_arn = var.eks_cluster_config.oidc_provider_arn

  enable_cert_manager = true
  cert_manager = {
    namespace        = kubernetes_namespace_v1.cert_manager.metadata[0].name
    create_namespace = false
  }

  enable_aws_privateca_issuer = true
  aws_privateca_issuer = {
    acmca_arn        = coalesce(var.aws_privateca_arn, aws_acmpca_certificate_authority.this[0].arn)
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
}

resource "aws_acmpca_certificate_authority" "this" {
  count = var.aws_privateca_arn == null ? 1 : 0

  type = "ROOT"

  certificate_authority_configuration {
    key_algorithm     = "RSA_4096"
    signing_algorithm = "SHA512WITHRSA"

    subject {
      common_name = var.aws_privateca_cn
    }
  }
}

resource "aws_acmpca_certificate" "this" {
  count = var.aws_privateca_arn == null ? 1 : 0

  certificate_authority_arn   = aws_acmpca_certificate_authority.this[0].arn
  certificate_signing_request = aws_acmpca_certificate_authority.this[0].certificate_signing_request
  signing_algorithm           = "SHA512WITHRSA"

  template_arn = "arn:aws:acm-pca:::template/RootCACertificate/V1"

  validity {
    type  = "YEARS"
    value = 10
  }
}

resource "aws_acmpca_certificate_authority_certificate" "this" {
  count = var.aws_privateca_arn == null ? 1 : 0

  certificate_authority_arn = aws_acmpca_certificate_authority.this[0].arn

  certificate       = aws_acmpca_certificate.this[0].certificate
  certificate_chain = aws_acmpca_certificate.this[0].certificate_chain
}

resource "aws_acm_certificate" "lb_ingress_cert" {
  certificate_authority_arn = coalesce(var.aws_privateca_arn, aws_acmpca_certificate_authority.this[0].arn)
  domain_name               = "*.elb.${var.aws_region}.amazonaws.com"

  subject_alternative_names = [
    "*.example.com",
    "example.com"
  ]
}

resource "local_file" "ca_cert" {
  content  = try(data.aws_acmpca_certificate_authority.this[0].certificate, aws_acmpca_certificate_authority.this[0].certificate)
  filename = "./ca-cert.pem"

  depends_on = [ aws_acm_certificate.lb_ingress_cert ]
}

# resource "null_resource" "patch_istio_ingress" {
#   provisioner "local-exec" {
#     command = "kubectl patch svc/istio-ingress -n istio-ingress --patch='${jsonencode({
#       metadata = {
#         annotations = {
#           "service.beta.kubernetes.io/aws-load-balancer-ssl-cert"               = aws_acm_certificate.lb_ingress_cert.arn
#           "service.beta.kubernetes.io/aws-load-balancer-ssl-ports"              = "https"
#           "service.beta.kubernetes.io/aws-load-balancer-ssl-negotiation-policy" = "ELBSecurityPolicy-TLS13-1-2-2021-06"
#           "service.beta.kubernetes.io/aws-load-balancer-backend-protocol"       = "tcp"
#         }
#       }
#     })}'"
#     interpreter = ["/bin/bash", "-c"]
#   }
#   provisioner "local-exec" {
#     command = "kubectl patch svc/istio-ingress -n istio-ingress --type='json' --patch='${jsonencode([
#       {
#         op   = "remove"
#         path = "/metadata/annotations/service.beta.kubernetes.io~1aws-load-balancer-ssl-cert"
#       },
#       {
#         op   = "remove"
#         path = "/metadata/annotations/service.beta.kubernetes.io~1aws-load-balancer-ssl-ports"
#       },
#       {
#         op   = "remove"
#         path = "/metadata/annotations/service.beta.kubernetes.io~1aws-load-balancer-ssl-negotiation-policy"
#       }
#     ])}'"
#     interpreter = ["/bin/bash", "-c"]
#     when        = destroy
#   }

#   depends_on = [
#     aws_acm_certificate.lb_ingress_cert,
#     local_file.ca_cert
#   ]
# }

# resource "null_resource" "patch_productapp_gateway" {
#   provisioner "local-exec" {
#     command = "kubectl patch gateway/productapp-gateway -n workshop --type=json --patch='${jsonencode([
#       {
#         op = "add"
#         path = "/spec/servers/-"
#         value = {
#           hosts = ["*"]
#           port = {
#             name: "https"
#             number: 443
#             protocol = "HTTP"
#           }
#         }
#       }
#     ])}'"
#     interpreter = ["/bin/bash", "-c"]
#   }
#   provisioner "local-exec" {
#     command = "kubectl patch gateway/productapp-gateway -n workshop --type=json --patch='${jsonencode([
#       {
#         op = "remove"
#         path = "/spec/servers/1"
#       }
#     ])}'"
#     interpreter = ["/bin/bash", "-c"]
#     when        = destroy
#   }

#   depends_on = [
#     null_resource.patch_istio_ingress
#   ]
# }

####################
# Using kubectl to workaround kubernetes provider issue https://github.com/hashicorp/terraform-provider-kubernetes/issues/1453
resource "kubectl_manifest" "aws_pca_root_ca_issuer" {
  yaml_body = yamlencode({
    apiVersion = "awspca.cert-manager.io/v1beta1"
    kind       = "AWSPCAIssuer"
    metadata = {
      name      = "root-ca"
      namespace = "istio-system"
    }
    spec = {
      arn    = coalesce(var.aws_privateca_arn, aws_acmpca_certificate_authority.this[0].arn)
      region = var.aws_region
    }
  })

  depends_on = [module.eks_blueprints_addons_cert_manager]
}

# Using kubectl to workaround kubernetes provider issue https://github.com/hashicorp/terraform-provider-kubernetes/issues/1453
resource "kubectl_manifest" "istio_ca_cert" {
  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "istio-ca"
      namespace = "istio-system"
    }
    spec = {
      isCA       = true
      duration   = "2160h" # 90d
      secretName = "istio-ca"
      commonName = "istio-ca"
      subject = {
        organizations = [
          "cert-manager"
        ]
      }
      issuerRef = {
        group = "awspca.cert-manager.io"
        kind  = "AWSPCAIssuer"
        name  = "root-ca"
      }
      renewBefore = "360h0m0s"
      usages = [
        "server auth",
        "client auth"
      ]
      privateKey = {
        algorithm : "RSA"
        size : 2048
      }
    }
  })

  depends_on = [kubectl_manifest.aws_pca_root_ca_issuer]
}

resource "kubectl_manifest" "istio_issuer" {
  yaml_body = yamlencode({
    apiVersion : "cert-manager.io/v1"
    kind : "Issuer"
    metadata : {
      name : "istio-ca"
      namespace : "istio-system"
    }
    spec : {
      ca : {
        secretName : "istio-ca"
      }
    }
  })

  depends_on = [kubectl_manifest.istio_ca_cert]
}

resource "helm_release" "cert_manager_istio_csr" {
  name       = "cert-manager-istio-csr"
  namespace  = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager-istio-csr"
  version    = "0.8.1"

  depends_on = [kubectl_manifest.istio_issuer]
}

resource "kubernetes_namespace_v1" "istio_system" {
  metadata {
    name = "istio-system"
  }
}

module "eks_blueprints_addons_istio" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.16.2"

  cluster_name      = var.eks_cluster_config.name
  cluster_endpoint  = var.eks_cluster_config.endpoint
  cluster_version   = var.eks_cluster_config.version
  oidc_provider_arn = var.eks_cluster_config.oidc_provider_arn

  helm_releases = {
    istio-base = {
      chart         = "base"
      chart_version = local.istio_chart_version
      repository    = local.istio_chart_url
      name          = "istio-base"
      namespace     = kubernetes_namespace_v1.istio_system.metadata[0].name
      description   = local.istio_chart_description
    }

    istiod = {
      chart         = "istiod"
      chart_version = local.istio_chart_version
      repository    = local.istio_chart_url
      name          = "istiod"
      namespace     = kubernetes_namespace_v1.istio_system.metadata[0].name
      description   = local.istio_chart_description

      set = [
        {
          name  = "meshConfig.accessLogFile"
          value = "/dev/stdout"
        },
        {
          name  = "global.certSigners[0]"
          value = "issuers.cert-manager.io/istio-ca"
        },
        {
          name  = "pilot.env.ENABLE_CA_SERVER"
          value = "false"
        },
        {
          name  = "global.caAddress"
          value = "cert-manager-istio-csr.cert-manager.svc:443"
        }
      ]
    }

    istio-ingress = {
      chart            = "gateway"
      chart_version    = local.istio_chart_version
      repository       = local.istio_chart_url
      name             = "istio-ingress"
      namespace        = "istio-ingress" # per https://github.com/istio/istio/blob/master/manifests/charts/gateways/istio-ingress/values.yaml#L2
      create_namespace = true
      description      = local.istio_chart_description

      values = [
        yamlencode(
          {
            labels = {
              istio = "ingressgateway"
            }
            service = {
              annotations = {
                "service.beta.kubernetes.io/aws-load-balancer-type"                   = "external"
                "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type"        = "ip"
                "service.beta.kubernetes.io/aws-load-balancer-scheme"                 = "internet-facing"
                "service.beta.kubernetes.io/aws-load-balancer-attributes"             = "load_balancing.cross_zone.enabled=true"
                "service.beta.kubernetes.io/aws-load-balancer-ssl-cert"               = aws_acm_certificate.lb_ingress_cert.arn
                "service.beta.kubernetes.io/aws-load-balancer-ssl-ports"              = "https"
                "service.beta.kubernetes.io/aws-load-balancer-ssl-negotiation-policy" = "ELBSecurityPolicy-TLS13-1-2-2021-06"
                "service.beta.kubernetes.io/aws-load-balancer-backend-protocol"       = "tcp"
              }
            }
          }
        )
      ]
    }
  }

  depends_on = [
    aws_acm_certificate.lb_ingress_cert,
    local_file.ca_cert,
    helm_release.cert_manager_istio_csr
  ]
}

# resource "helm_release" "istiod" {
#   chart       = "istiod"
#   name        = "istiod"
#   namespace   = "istio-system"
#   repository  = "https://istio-release.storage.googleapis.com/charts"
#   description = "Enable ACM PCA issuer integration through cert-manager-istio-csr"
#   max_history = 2

#   set {
#     name = "global.certSigners[0]"
#     value = "issuers.cert-manager.io/istio-ca"
#   }

#   set {
#     name  = "pilot.env.ENABLE_CA_SERVER"
#     value = "false"
#   }

#   set {
#     name  = "global.caAddress"
#     value = "cert-manager-istio-csr.cert-manager.svc:443"
#   }

#   depends_on = [helm_release.cert_manager_istio_csr]
# }
