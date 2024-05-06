locals {
  setup_workshop_mesh_resources_file_pattern = "../../00-setup-mesh-resources/*.yaml"
}

resource "kubernetes_namespace_v1" "workshop" {
  metadata {
    name = "workshop"
    labels = {
      "istio-injection" = "enabled"
    }
  }
  depends_on = [null_resource.istio_addons]
}

resource "helm_release" "workshop" {
  name      = "mesh-basic"
  chart     = "../../01-getting-started"
  namespace = kubernetes_namespace_v1.workshop.metadata[0].name
}

data "local_file" "setup_workshop_mesh_resources" {
  for_each = fileset(path.module, local.setup_workshop_mesh_resources_file_pattern)
  
  filename = each.value

  depends_on = [ helm_release.workshop ]
}

resource "kubectl_manifest" "setup_workshop_mesh_resources" {
  for_each = fileset(path.module, local.setup_workshop_mesh_resources_file_pattern)

  yaml_body = data.local_file.setup_workshop_mesh_resources[each.value].content
}

resource "null_resource" "patch_productapp_gateway" {
  provisioner "local-exec" {
    command     = "kubectl patch gateway/productapp-gateway -n ${kubernetes_namespace_v1.workshop.metadata[0].name} --type=json --patch='${jsonencode(
      [
        {
          op = "add"
          path = "/spec/servers/-"
          value = {
            hosts = ["*"]
            port = {
              name = "https"
              number = 443
              protocol = "HTTP"
            }
          }
        }
      ]
    )}'"
    interpreter = ["/bin/bash", "-c"]
    environment = {
      AWS_REGION = var.aws_region
    }
  }
  depends_on = [helm_release.workshop]
}