output "input_bucket_name" {
  description = "Upload a CSV here to trigger the pipeline."
  value       = aws_s3_bucket.input.bucket
}

output "output_bucket_name" {
  description = "Transformed CSVs are written here under processed/."
  value       = aws_s3_bucket.output.bucket
}

output "ecr_repository_url" {
  description = "ECR repository URL to push the batch image to."
  value       = aws_ecr_repository.this.repository_url
}

output "state_machine_arn" {
  description = "ARN of the saga Step Functions state machine."
  value       = aws_sfn_state_machine.this.arn
}

output "ecs_cluster_name" {
  description = "ECS cluster the batch tasks run in."
  value       = aws_ecs_cluster.this.name
}

output "task_definition_arn" {
  description = "Fargate task definition launched by Step Functions."
  value       = aws_ecs_task_definition.this.arn
}
