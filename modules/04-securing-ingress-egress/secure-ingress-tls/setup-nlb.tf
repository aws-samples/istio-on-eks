data "aws_region" "current_region" {}

resource "tls_private_key" "istio-tls-root-private-key" {
  algorithm = "RSA"
}

resource "local_file" "istio-tls-root-private-key-file" {
  content  = tls_private_key.istio-tls-root-private-key.private_key_pem
  filename = "${path.module}/certs/istio-tls-root-private-key.key"
}

resource "tls_self_signed_cert" "istio-tls-root-cert" {
  private_key_pem = tls_private_key.istio-tls-root-private-key.private_key_pem
  
  dns_names = ["aws-samples.com", "*.elb.${data.aws_region.current_region.name}.amazonaws.com"]
  
  subject {
    common_name  = "*.elb.${data.aws_region.current_region.name}.amazonaws.com"
    organization = "AWS Samples, Inc"
  }  
  

  validity_period_hours = 8760 //1 year

  allowed_uses = [
    "digital_signature",
    "cert_signing",
    "crl_signing",
  ]
}

resource "local_file" "istio-tls-root-cert" {
  content  = tls_self_signed_cert.istio-tls-root-cert.cert_pem
  filename = "${path.module}/certs/istio-tls-root-cert.cert"
}

resource "aws_acm_certificate" "istio-nlb-root_cert" {
  private_key      = tls_private_key.istio-tls-root-private-key.private_key_pem
  certificate_body = tls_self_signed_cert.istio-tls-root-cert.cert_pem
}

output "istio-nlb-root_cert" {
  value = aws_acm_certificate.istio-nlb-root_cert.arn
}