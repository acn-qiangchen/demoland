terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  # Local state on purpose: this is a one-time, run-once-by-a-human bootstrap that
  # must exist BEFORE any OIDC-based workflow can authenticate. Keep terraform.tfstate
  # for this module somewhere safe (it only records the OIDC provider + IAM role).
}

provider "aws" {
  region = var.aws_region
}
