variable "app_name" {
  description = "Logical name of the demo app; used as a prefix for all resource names."
  type        = string
  default     = "osaga-demo"
}

variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "image_tag" {
  description = "Container image tag to run (pushed to the ECR repo)."
  type        = string
  default     = "latest"
}

variable "task_cpu" {
  description = "Fargate task CPU units (512 = 0.5 vCPU)."
  type        = number
  default     = 512
}

variable "task_memory" {
  description = "Fargate task memory in MiB."
  type        = number
  default     = 1024
}

variable "log_retention_days" {
  description = "CloudWatch log retention for the task's log group."
  type        = number
  default     = 7
}
