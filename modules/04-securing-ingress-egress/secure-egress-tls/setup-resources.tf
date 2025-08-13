data "aws_region" "current_region" {}

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_vpcs" "cluster_vpc" {
    
    filter {
        name = "tag:Name"
        values = ["istio"]
    }
}

data "aws_subnets" "cluster_private_subnets" {
    for_each = toset(data.aws_availability_zones.available.zone_ids)

    filter {
        name   = "vpc-id"
        values = [data.aws_vpcs.cluster_vpc.ids[0]]
    }
  
    filter {
        name = "tag:kubernetes.io/role/internal-elb"
        values = ["1"]
    }

    filter {
        name = "availability-zone-id"
        values = ["${each.value}"]
    }
}

resource "aws_db_subnet_group" "cluster_subnet_group" {
  name       = "cluster_subnet_group"
  subnet_ids = local.subnet_ids

  tags = {
    Name = "Cluster DB Subnet group"
  }
}

resource "aws_rds_cluster_parameter_group" "secure_tls_db_parms" {
  name        = "securedb-tls-pg"
  family      = "aurora-mysql5.7"
  description = "RDS secure tls cluster parameter group"

  parameter {
    name  = "require_secure_transport"
    value = "ON"
  }
}

resource "aws_rds_cluster" "product_catalog" {
  cluster_identifier      = "aurora-cluster-demo"
  engine                  = "aurora-mysql"
  engine_version          = "5.7.mysql_aurora.2.12.1"
  availability_zones      = slice(data.aws_availability_zones.available.names,0,2)
  database_name           = "product_catalog"
  db_cluster_parameter_group_name = "securedb-tls-pg"
  manage_master_user_password = true
  master_username             = "product_db_user1"
  db_subnet_group_name = "cluster_subnet_group"
  iam_database_authentication_enabled = true
  skip_final_snapshot = true
}

resource "aws_rds_cluster_instance" "product_catalog_instance" {
  identifier         = "product-catalog-db"
  cluster_identifier = aws_rds_cluster.product_catalog.id
  instance_class     = "db.r4.large"
  engine             = aws_rds_cluster.product_catalog.engine
  engine_version     = aws_rds_cluster.product_catalog.engine_version
  db_subnet_group_name = "cluster_subnet_group"

}

data "aws_eks_cluster" "istio_cluster" {
  name = "istio"
}

data "tls_certificate" "istio_cluster_cert" {
  url = data.aws_eks_cluster.istio_cluster.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "istio_cluster_oidc" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.istio_cluster_cert.certificates[0].sha1_fingerprint]
  url             = data.aws_eks_cluster.istio_cluster.identity[0].oidc[0].issuer
}

data "aws_iam_policy_document" "eks_cluster_irsa_allow_workshop_sa" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.istio_cluster_oidc.arn]
    }
    condition {
      test     = "StringLike"
      variable = local.irsa_audience
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = local.irsa_subject
      values   = ["system:serviceaccount:workshop:*","system:serviceaccount:legacy:*"]
    }
  }
  version = "2012-10-17"
}

resource "aws_iam_role" "allow_productcatalog_app_access" {
  name         = "allow.product_catalog.access"
  assume_role_policy = data.aws_iam_policy_document.eks_cluster_irsa_allow_workshop_sa.json

  tags = {
    tag-key = "allow.product_catalog.access"
  }
}

resource "aws_iam_role_policy_attachment" "allow_productcatalog_app_access_policy_attach" {
  policy_arn = aws_iam_policy.allow_productcatalog_app_accesspolicy.arn
  role       = aws_iam_role.allow_productcatalog_app_access.name
}


resource "aws_iam_policy" "allow_productcatalog_app_accesspolicy" {
  name        = "allow.product_catalog.accesspolicy"
  path        = "/"
  description = "Allow access to product catalog data"

  policy = jsonencode({
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "rds-db:connect"
      ],
      "Resource": [
        "arn:aws:rds-db:${data.aws_region.current_region.name}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_rds_cluster.product_catalog.cluster_resource_id}/product_catalog_app"
      ]
    }
  ]
  })
}

locals {
  irsa_subjects_tokens_1 = split(":",aws_iam_openid_connect_provider.istio_cluster_oidc.arn)
  irsa_subjects_tokens_2 = split("/",local.irsa_subjects_tokens_1[length(local.irsa_subjects_tokens_1) - 1])
  irsa_subject_prefix = join("/",[local.irsa_subjects_tokens_2[length(local.irsa_subjects_tokens_2) - 3],local.irsa_subjects_tokens_2[length(local.irsa_subjects_tokens_2) - 2],local.irsa_subjects_tokens_2[length(local.irsa_subjects_tokens_2) - 1]])
  irsa_subject = "${local.irsa_subject_prefix}:sub"
  irsa_audience = "${local.irsa_subject_prefix}:aud"
  subnet_ids = flatten([for k, v in data.aws_subnets.cluster_private_subnets : v.ids])
}
