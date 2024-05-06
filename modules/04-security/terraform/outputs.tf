output "configure_kubectl" {
  description = "Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig"
  value       = "aws eks --region ${var.aws_region} update-kubeconfig --name ${module.eks.cluster_name}"
}

output "ca_cert_export_path" {
  description = "CA certificate has been exported at the following location."
  value = "${path.module}/${local_file.lb_ingress_cert.filename}"
}

output "next_steps" {
    description = "Next steps"
    value = <<EOT
The stack has created all the dependencies for setting up
  * peer authentication using AWS Private CA,
  * request authentication using Keycloak, and
  * request authorization using Open Policy Agent.

Refer to README.md for next steps.

Remember to set the right region like below when executing AWS CLI commands or helper scripts.

export AWS_REGION=${var.aws_region}

EOT
}