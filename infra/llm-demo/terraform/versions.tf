terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # >= 6.25 required for aws_api_gateway_integration.response_transfer_mode (SSE streaming).
      version = "~> 6.25"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Partial backend config: bucket / key / region / dynamodb_table are supplied
  # at `terraform init` time via -backend-config (see the deploy workflow).
  backend "s3" {}
}

provider "aws" {
  region = var.aws_region
}
