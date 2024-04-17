output "pca_certificate" {
  description = "ACM PCA certificate"
  value = length(data.aws_acmpca_certificate_authority.this) > 0 ? data.aws_acmpca_certificate_authority.this[0].certificate : length(aws_acmpca_certificate_authority.this) > 0 ? aws_acmpca_certificate_authority.this[0].certificate : null
}