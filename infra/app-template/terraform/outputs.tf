output "cloudfront_domain_name" {
  description = "Public URL host for the demo (open https://<this>)."
  value       = aws_cloudfront_distribution.this.domain_name
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID (used for cache invalidation)."
  value       = aws_cloudfront_distribution.this.id
}

output "ecr_repository_url" {
  description = "ECR repository URL to push the backend image to."
  value       = aws_ecr_repository.this.repository_url
}

output "ecr_bff_repository_url" {
  description = "ECR repository URL to push the bff image to."
  value       = aws_ecr_repository.bff.repository_url
}

output "ecs_cluster_name" {
  description = "ECS cluster name (used to force a new deployment)."
  value       = aws_ecs_cluster.this.name
}

output "ecs_service_name" {
  description = "ECS service name (used to force a new deployment)."
  value       = aws_ecs_service.this.name
}

output "s3_bucket_name" {
  description = "S3 bucket holding the static frontend."
  value       = aws_s3_bucket.frontend.id
}
