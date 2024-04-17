terraform {
  required_version = ">= 1.3"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.44.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.13.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.27"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.14.0"
    }

    null = {
      source = "hashicorp/null"
      version = "3.2.2"
    }

    random = {
      source = "hashicorp/random"
      version = "3.6.0"
    }

    time = {
      source = "hashicorp/time"
      version = "0.11.1"
    }

    local = {
      source = "hashicorp/local"
      version = "2.5.1"
    }
  }

  # ##  Used for end-to-end testing on project; update to suit your needs
  # backend "s3" {
  #   bucket = "terraform-ssp-github-actions-state"
  #   region = "us-west-2"
  #   key    = "e2e/istio/terraform.tfstate"
  # }
}