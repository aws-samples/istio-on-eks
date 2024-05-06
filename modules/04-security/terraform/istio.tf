locals {
  istio_chart_url         = "https://istio-release.storage.googleapis.com/charts"
  istio_version           = "1.20"
  istio_patch_version     = "2"
  istio_chart_version     = "${local.istio_version}.${local.istio_patch_version}"
  istio_chart_description = "Enable ACM PCA issuer integration through cert-manager-istio-csr"
  istio_addon_names            = ["kiali", "jaeger", "prometheus", "grafana"]
}

# Using kubectl to workaround kubernetes provider issue https://github.com/hashicorp/terraform-provider-kubernetes/issues/1453
resource "kubectl_manifest" "aws_pca_root_ca_issuer" {
  yaml_body = yamlencode({
    apiVersion = "awspca.cert-manager.io/v1beta1"
    kind       = "AWSPCAClusterIssuer"
    metadata = {
      name = "root-ca"
    }
    spec = {
      arn    = aws_acmpca_certificate_authority.mtls.arn
      region = var.aws_region
    }
  })

  depends_on = [module.eks_blueprints_addons]
}

resource "tls_private_key" "lb_ingress_cert" {
  algorithm = "RSA"
}

resource "tls_self_signed_cert" "lb_ingress_cert" {
  private_key_pem = tls_private_key.lb_ingress_cert.private_key_pem

  subject {
    common_name  = var.name
    organization = "Istio on EKS Security Example"
  }

  dns_names = [
    "*.elb.${var.aws_region}.amazonaws.com",
    "*.example.com",
    "example.com"
  ]

  validity_period_hours = 168 # 7 days
  early_renewal_hours   = 12  # Renew if rerun 12 hours expiry

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

resource "aws_acm_certificate" "lb_ingress_cert" {
  private_key      = tls_private_key.lb_ingress_cert.private_key_pem
  certificate_body = tls_self_signed_cert.lb_ingress_cert.cert_pem
}

# Export certificate
resource "local_file" "lb_ingress_cert" {
  content  = tls_self_signed_cert.lb_ingress_cert.cert_pem
  filename = "../lb_ingress_cert.pem"
}

resource "kubernetes_namespace_v1" "istio_system" {
  metadata {
    name = "istio-system"
  }
  depends_on = [module.eks]
}

####################
# Using kubectl to workaround kubernetes provider issue https://github.com/hashicorp/terraform-provider-kubernetes/issues/1453
resource "kubectl_manifest" "istio_ca_cert" {
  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "istio-ca"
      namespace = kubernetes_namespace_v1.istio_system.metadata[0].name
    }
    spec = {
      isCA       = true
      duration   = "168h" # 7d
      secretName = "istio-ca"
      commonName = "istio-ca"
      subject = {
        organizations = [
          "cert-manager"
        ]
      }
      issuerRef = {
        group = "awspca.cert-manager.io"
        kind  = "AWSPCAClusterIssuer"
        name  = "root-ca"
      }
      renewBefore = "162h0m0s" # 6h less than 7d
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
      namespace : kubernetes_namespace_v1.istio_system.metadata[0].name
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
  namespace  = kubernetes_namespace_v1.cert_manager.metadata[0].name
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager-istio-csr"
  version    = "0.8.1"

  depends_on = [kubectl_manifest.istio_issuer]
}



resource "helm_release" "istio_base" {
  chart            = "base"
  version          = local.istio_chart_version
  repository       = local.istio_chart_url
  name             = "istio-base"
  namespace        = kubernetes_namespace_v1.istio_system.metadata[0].name
  create_namespace = false
  description      = local.istio_chart_description

  depends_on = [helm_release.cert_manager_istio_csr]
}

resource "helm_release" "istiod" {
  chart            = "istiod"
  version          = local.istio_chart_version
  repository       = local.istio_chart_url
  name             = "istiod"
  namespace        = kubernetes_namespace_v1.istio_system.metadata[0].name
  create_namespace = false
  description      = local.istio_chart_description

  values = [yamlencode({
    global = {
      certSigners = [
        "issuers.cert-manager.io/istio-ca"
      ]
      caAddress = "cert-manager-istio-csr.cert-manager.svc:443"
    }
    pilot = {
      env = {
        ENABLE_CA_SERVER = "false"
      }
    }
    meshConfig = {
      accessLogFile = "/dev/stdout"
    }
  })]

  depends_on = [helm_release.istio_base]
}

resource "kubernetes_namespace_v1" "istio_ingress" {
  metadata {
    name = "istio-ingress"
  }
  depends_on = [module.eks]
}

resource "helm_release" "istio_ingress" {
  chart            = "gateway"
  version          = local.istio_chart_version
  repository       = local.istio_chart_url
  name             = "istio-ingress"
  namespace        = kubernetes_namespace_v1.istio_ingress.metadata[0].name # per https://github.com/istio/istio/blob/master/manifests/charts/gateways/istio-ingress/values.yaml#L2
  create_namespace = false
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

  depends_on = [helm_release.istiod]
}

resource "null_resource" "istio_addons" {
  for_each = toset(local.istio_addon_names)

  provisioner "local-exec" {
    command     = "kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-${local.istio_version}/samples/addons/${each.key}.yaml"
    interpreter = ["/bin/bash", "-c"]
    environment = {
      AWS_REGION = var.aws_region
    }
  }
  depends_on = [helm_release.istio_ingress]
}
