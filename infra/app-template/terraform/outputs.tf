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

output "s3_bucket_name" {
  description = "S3 bucket holding the static frontend."
  value       = aws_s3_bucket.frontend.id
}
