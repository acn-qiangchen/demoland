output "role_arn" {
  description = "Pass this as the `aws_role_arn` input when running the deploy/destroy workflows."
  value       = aws_iam_role.deploy.arn
}

output "oidc_provider_arn" {
  description = "ARN of the GitHub OIDC identity provider used by the role's trust policy."
  value       = local.oidc_provider_arn
}
