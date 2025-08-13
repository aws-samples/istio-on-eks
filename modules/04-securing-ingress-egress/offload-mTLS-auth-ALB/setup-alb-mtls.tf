data "aws_region" "current_region" {}

resource "tls_private_key" "istio-mtls-root-private-key" {
  algorithm = "RSA"
}

resource "local_file" "istio-mtls-root-private-key-file" {
  content  = tls_private_key.istio-mtls-root-private-key.private_key_pem
  filename = "${path.module}/certs/istio-mtls-root-private-key.key"
}

resource "tls_self_signed_cert" "istio-mtls-root-cert" {
  private_key_pem = tls_private_key.istio-mtls-root-private-key.private_key_pem
  
  dns_names = ["aws-samples.com", "*.${data.aws_region.current_region.name}.elb.amazonaws.com"]
  
  subject {
    common_name  = "*.${data.aws_region.current_region.name}.elb.amazonaws.com"
    organization = "AWS Samples, Inc"
  }  

  validity_period_hours = 8760 //1 year

  allowed_uses = [
    "digital_signature",
    "cert_signing",
    "crl_signing",
  ]
}

resource "local_file" "istio-mtls-root-cert" {
  content  = tls_self_signed_cert.istio-mtls-root-cert.cert_pem
  filename = "${path.module}/certs/istio-mtls-root-cert.cert"
}

resource "aws_acm_certificate" "istio-nlb-root_cert" {
  private_key      = tls_private_key.istio-mtls-root-private-key.private_key_pem
  certificate_body = tls_self_signed_cert.istio-mtls-root-cert.cert_pem
}

resource "tls_private_key" "client-1-mtls-ca-private-key" {
  algorithm = "RSA"
}

resource "local_file" "client-1-mtls-ca-private-key-file" {
  content  = tls_private_key.client-1-mtls-ca-private-key.private_key_pem
  filename = "${path.module}/certs/client-1-mtls-ca-private-key.key"
}

resource "tls_self_signed_cert" "client-1-mtls-ca-cert" {
  private_key_pem = tls_private_key.client-1-mtls-ca-private-key.private_key_pem
  dns_names = ["client-1-aws-samples.com"]
  
  is_ca_certificate = true

  subject {
    common_name  = "client-1-ca-aws-samples.com"
    organization = "AWS Samples, Inc"
  }  
  validity_period_hours = 8760 //1 year
  allowed_uses = [
    "digital_signature",
    "cert_signing",
    "crl_signing",
  ]
}

resource "local_file" "client-1-mtls-ca-cert" {
  content  = tls_self_signed_cert.client-1-mtls-ca-cert.cert_pem
  filename = "${path.module}/certs/client-1-mtls-ca-cert.cert"
}

resource "tls_private_key" "client-1-mtls-private-key" {
  algorithm = "RSA"
}

resource "local_file" "client-1-mtls-private-key-file" {
  content  = tls_private_key.client-1-mtls-private-key.private_key_pem
  filename = "${path.module}/certs/client-1-mtls-private-key.key"
}

resource "tls_cert_request" "client-1-mtls-csr" {
  private_key_pem = tls_private_key.client-1-mtls-private-key.private_key_pem
  dns_names = ["client-1-aws-samples.com"]
  
  subject {
    common_name  = "client-1-aws-samples.com"
    organization = "AWS Samples, Inc"
  }
}

resource "tls_locally_signed_cert" "client-1-mtls-cert" {
  cert_request_pem   = tls_cert_request.client-1-mtls-csr.cert_request_pem
  ca_private_key_pem = tls_private_key.client-1-mtls-ca-private-key.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.client-1-mtls-ca-cert.cert_pem

  validity_period_hours = 8760 //1 year
  allowed_uses = [
    "digital_signature",
    "cert_signing",
    "crl_signing",
  ]
}

resource "local_file" "client-1-mtls-cert-file" {
  content  = tls_locally_signed_cert.client-1-mtls-cert.cert_pem
  filename = "${path.module}/certs/client-1-mtls-cert.cert"
}

output "istio-nlb-root_cert" {
  value = aws_acm_certificate.istio-nlb-root_cert.arn
}