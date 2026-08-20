variable "aws_region" {
  description = "AWS region for the bootstrap provider (IAM is global; region only affects the API endpoint)."
  type        = string
  default     = "us-east-1"
}

variable "github_owner" {
  description = "GitHub org/user that owns the repo allowed to assume the role."
  type        = string
  default     = "acn-qiangchen"
}

variable "github_repo" {
  description = "GitHub repository name allowed to assume the role."
  type        = string
  default     = "demoland"
}

variable "role_name" {
  description = "Name of the IAM role the GitHub Actions workflows assume via OIDC."
  type        = string
  default     = "demoland-github-actions-deploy"
}

variable "create_oidc_provider" {
  description = <<-EOT
    Create the GitHub OIDC provider. Set to false if your account already has a
    provider for token.actions.githubusercontent.com (only one is allowed per account) —
    then this module reuses the existing one.
  EOT
  type        = bool
  default     = true
}
