terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Partial backend config: bucket / key / region / dynamodb_table are supplied
  # at `terraform init` time via -backend-config (see the deploy workflow).
  backend "s3" {}
}

provider "aws" {
  region = var.aws_region
}
