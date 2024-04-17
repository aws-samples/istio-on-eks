resource "time_static" "activation_date" {}

locals {
  keycloak_name                 = "keycloak"
  keycloak_namespace            = "keycloak"
  user_creation_timestamp       = time_static.activation_date.unix * 1000
}


resource "kubernetes_namespace_v1" "external_secrets" {
  metadata {
    name = "external-secrets"
  }
}

resource "kubernetes_namespace_v1" "keycloak" {
  metadata {
    name = local.keycloak_namespace
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

  eks_cluster_id        = var.eks_cluster_config.name
  eks_oidc_provider_arn = var.eks_cluster_config.oidc_provider_arn
}

module "eks_blueprints_addons" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.16.2"

  cluster_name      = var.eks_cluster_config.name
  cluster_endpoint  = var.eks_cluster_config.endpoint
  cluster_version   = var.eks_cluster_config.version
  oidc_provider_arn = var.eks_cluster_config.oidc_provider_arn

  # EKS Add-on
  eks_addons = {
    aws-ebs-csi-driver = {
      preserve                 = false
      service_account_role_arn = module.ebs_csi_driver_irsa.irsa_iam_role_arn
    }
  }

  # Add-ons
  enable_external_secrets = true
  external_secrets_secrets_manager_arns = [
    aws_secretsmanager_secret.keycloak_admin.arn,
    aws_secretsmanager_secret.workshop_realm.arn
  ]
  external_secrets = {
    namespace        = kubernetes_namespace_v1.external_secrets.metadata[0].name
    create_namespace = false
  }

  enable_secrets_store_csi_driver              = true
  enable_secrets_store_csi_driver_provider_aws = true
}

resource "random_password" "keycloak_passwords" {
  count = 4

  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}:?"
}

resource "aws_secretsmanager_secret" "keycloak_admin" {
  name                    = local.keycloak_name
  description             = "Keycloak admin password used for Istio-on-EKS project."
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "keycloak_admin" {
  secret_id = aws_secretsmanager_secret.keycloak_admin.id
  secret_string = jsonencode({
    "admin_password" : random_password.keycloak_passwords[0].result
  })
}

resource "aws_secretsmanager_secret" "workshop_realm" {
  name                    = "workshop-realm"
  description             = "Keycloak realm for workshop."
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "workshop_realm" {
  secret_id = aws_secretsmanager_secret.workshop_realm.id
  secret_string = sensitive(jsonencode({
    "realm" : "workshop",
    "enabled" : true,
    "sslRequired" : "none",
    "roles" : {
      "realm" : [
        {
          "name" : "admin"
        },
        {
          "name" : "guest"
        },
        {
          "name" : "other"
        }
      ]
    },
    "users" : [
      {
        "id" : "alice@example.com",
        "username" : "alice",
        "email" : "alice@example.com",
        "emailVerified" : true,
        "enabled" : true,
        "firstName" : "Alice",
        "createdTimestamp" : local.user_creation_timestamp,
        "realmRoles" : [
          "guest"
        ],
        "credentials" : [
          {
            "type" : "password",
            "value" : random_password.keycloak_passwords[1].result
          }
        ]
      },
      {
        "id" : "bob@example.com",
        "username" : "bob",
        "email" : "bob@example.com",
        "emailVerified" : true,
        "enabled" : true,
        "firstName" : "Bob",
        "createdTimestamp" : local.user_creation_timestamp,
        "realmRoles" : [
          "admin"
        ],
        "credentials" : [
          {
            "type" : "password",
            "value" : random_password.keycloak_passwords[2].result
          }
        ]
      },
      {
        "id" : "charlie@example.com",
        "username" : "charlie",
        "email" : "charlie@example.com",
        "emailVerified" : true,
        "enabled" : true,
        "firstName" : "Charlie",
        "createdTimestamp" : local.user_creation_timestamp,
        "realmRoles" : [
          "other"
        ],
        "credentials" : [
          {
            "type" : "password",
            "value" : random_password.keycloak_passwords[3].result
          }
        ]
      }
    ],
    "requiredCredentials" : [
      "password"
    ],
    "clients" : [
      {
        "clientId" : "productapp",
        "name" : "productapp",
        "enabled" : true,
        "clientAuthenticatorType" : "client-secret",
        "publicClient" : true,
        "directAccessGrantsEnabled" : true,
        "protocol" : "openid-connect",
        "redirectUris" : [
          "/*"
        ],
        "webOrigins" : [
          "/*"
        ],
        "attributes" : {
          "oidc.ciba.grant.enabled" : "false",
          "oauth2.device.authorization.grant.enabled" : "false",
          "backchannel.logout.session.required" : "true",
          "backchannel.logout.revoke.offline.tokens" : "false"
        },
        "protocolMappers" : [
          {
            "name" : "AudienceMapper",
            "protocol" : "openid-connect",
            "protocolMapper" : "oidc-audience-mapper",
            "consentRequired" : false,
            "config" : {
              "included.client.audience" : "productapp",
              "id.token.claim" : "false",
              "access.token.claim" : "true",
              "introspection.token.claim" : "true"
            }
          }
        ],
        "defaultClientScopes" : [
          "web-origins",
          "acr",
          "profile",
          "roles",
          "email"
        ],
        "optionalClientScopes" : [
          "address",
          "phone",
          "offline_access",
          "microprofile-jwt"
        ]
      }
    ]
  }))
}

resource "kubectl_manifest" "keycloak_admin_secretstore" {
  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "SecretStore"
    metadata = {
      name      = local.keycloak_name
      namespace = kubernetes_namespace_v1.keycloak.metadata[0].name
    }
    spec = {
      provider = {
        aws = {
          service = "SecretsManager"
          region  = var.aws_region
        }
      }
    }
  })

  depends_on = [aws_secretsmanager_secret_version.keycloak_admin]
}

resource "kubectl_manifest" "keycloak_admin_externalsecret" {
  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = local.keycloak_name
      namespace = kubernetes_namespace_v1.keycloak.metadata[0].name
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef = {
        name = local.keycloak_name
        kind = "SecretStore"
      }
      target = {
        name           = local.keycloak_name
        creationPolicy = "Owner"
      }
      data = [
        {
          secretKey = "admin-password"
          remoteRef = {
            key      = local.keycloak_name
            property = "admin_password"
          }
        }
      ]
    }
  })

  depends_on = [
    aws_secretsmanager_secret_version.keycloak_admin,
    kubectl_manifest.keycloak_admin_secretstore,
  ]
}

resource "kubernetes_storage_class_v1" "ebs_sc" {
  metadata {
    name = "ebs-sc"
  }
  storage_provisioner = "ebs.csi.aws.com"
  volume_binding_mode = "WaitForFirstConsumer"

  depends_on = [module.eks_blueprints_addons]
}

#########
# Attach IRSA permissions to keycloak service account to read app realm secret from AWS Secrets Manager
# and mount as volume in keycloak pod using Secret Store CSI driver
#########
data "aws_iam_policy_document" "keycloak_serviceaccount_policy" {
  statement {
    effect = "Allow"
    resources = [
      aws_secretsmanager_secret.workshop_realm.arn
    ]
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret"
    ]
  }

  depends_on = [
    aws_secretsmanager_secret_version.workshop_realm
  ]
}

resource "aws_iam_policy" "keycloak_serviceaccount_policy" {
  description = "keycloak ServiceAccount IAM policy"
  name        = "keycloak-serviceaccount-policy"
  policy      = data.aws_iam_policy_document.keycloak_serviceaccount_policy.json
}

module "keycloak_serviceaccount_irsa" {
  source = "github.com/aws-ia/terraform-aws-eks-blueprints//modules/irsa?ref=v4.32.1"

  create_kubernetes_namespace         = false
  create_kubernetes_service_account   = false
  create_service_account_secret_token = false
  kubernetes_namespace                = kubernetes_namespace_v1.keycloak.metadata[0].name
  kubernetes_service_account          = "keycloak"
  irsa_iam_policies = [
    aws_iam_policy.keycloak_serviceaccount_policy.arn
  ]

  eks_cluster_id        = var.eks_cluster_config.name
  eks_oidc_provider_arn = var.eks_cluster_config.oidc_provider_arn
}
#########

resource "kubectl_manifest" "app_realm_secrets_store_csi" {
  yaml_body = yamlencode({
    apiVersion = "secrets-store.csi.x-k8s.io/v1"
    kind       = "SecretProviderClass"
    metadata = {
      name      = aws_secretsmanager_secret.workshop_realm.name
      namespace = kubernetes_namespace_v1.keycloak.metadata[0].name
    }
    spec = {
      provider = "aws"
      parameters = {
        objects = yamlencode([
          {
            objectName  = aws_secretsmanager_secret.workshop_realm.name
            objectType  = "secretsmanager"
            objectAlias = "realm.json"
          }
        ])
      }
    }
  })

  depends_on = [aws_secretsmanager_secret_version.workshop_realm]
}

resource "helm_release" "keycloak" {
  name       = local.keycloak_name
  namespace  = kubernetes_namespace_v1.keycloak.metadata[0].name
  repository = "https://charts.bitnami.com/bitnami"
  chart      = local.keycloak_name
  version    = "21.0.0"

  values = [
    yamlencode({
      global = {
        storageClass = kubernetes_storage_class_v1.ebs_sc.metadata[0].name
      }
      image = {
        registry   = "public.ecr.aws"
        repository = "bitnami/keycloak"
        tag        = "22.0.1-debian-11-r36"
        debug      = true
      }
      extraEnvVars = [
        {
          name  = "KEYCLOAK_EXTRA_ARGS"
          value = "--import-realm"
        }
      ]
      serviceAccount = {
        annotations = {
          "eks.amazonaws.com/role-arn" = module.keycloak_serviceaccount_irsa.irsa_iam_role_arn
        }
      }
      auth = {
        adminUser         = "admin"
        existingSecret    = "keycloak"
        passwordSecretKey = "admin-password"
      }
      production = false
      proxy      = "edge"
      service = {
        type = "LoadBalancer"
        annotations = {
          "service.beta.kubernetes.io/aws-load-balancer-scheme"                        = "internet-facing"
          "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type"               = "ip"
          "service.beta.kubernetes.io/aws-load-balancer-healthcheck-healthy-threshold" = "2"
        }
        http = {
          enabled = true
        }
        ports = {
          http = 80
        }
      }
      extraVolumeMounts = [
        {
          name      = aws_secretsmanager_secret.workshop_realm.name
          mountPath = "/opt/bitnami/keycloak/data/import"
          readOnly  = true
        }
      ]
      extraVolumes = [
        {
          name = aws_secretsmanager_secret.workshop_realm.name
          csi = {
            driver   = "secrets-store.csi.k8s.io"
            readOnly = true
            volumeAttributes = {
              secretProviderClass = aws_secretsmanager_secret.workshop_realm.name
            }
          }
        }
      ]
      logging = {
        output = "default"
        level  = "DEBUG"
      }
    })
  ]

  timeout = 10 * 60

  depends_on = [
    kubernetes_storage_class_v1.ebs_sc,
    kubectl_manifest.keycloak_admin_externalsecret,
    aws_secretsmanager_secret_version.workshop_realm,
    kubectl_manifest.app_realm_secrets_store_csi
  ]
}

resource "null_resource" "keycloak_lb_healthy" {
  provisioner "local-exec" {
    command     = "./scripts/helpers.sh --wait-lb --lb-arn-pattern 'loadbalancer/net/k8s-keycloak-keycloak-'"
    interpreter = ["/bin/bash", "-c"]
    environment = {
      AWS_REGION = var.aws_region
    }
  }

  depends_on = [helm_release.keycloak]
}