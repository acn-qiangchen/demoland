variable "app_name" {
  description = "Logical name of the demo app; used as a prefix for all resource names."
  type        = string
  default     = "llm-async-demo"
}

variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "image_tag" {
  description = "Container image tag to deploy (pushed to the ECR repo)."
  type        = string
  default     = "latest"
}

variable "openai_api_key" {
  description = "OpenAI API key, stored in Secrets Manager and injected into the ECS task."
  type        = string
  sensitive   = true
}

variable "container_cpu" {
  description = "Fargate task CPU units (256 = 0.25 vCPU). Sized for two JVMs (backend + bff) in one task."
  type        = number
  default     = 1024
}

variable "container_memory" {
  description = "Fargate task memory in MiB. Sized for two JVMs (backend + bff) in one task."
  type        = number
  default     = 2048
}

variable "desired_count" {
  description = "Number of ECS service tasks to run."
  type        = number
  default     = 1
}

variable "redis_node_type" {
  description = "ElastiCache Redis node type for the job store."
  type        = string
  default     = "cache.t3.micro"
}

variable "alb_idle_timeout" {
  description = <<-EOT
    ALB idle timeout in seconds. Tuned deliberately LOW so the ALB is the binding timeout on the
    synchronous /api/chat/sync path: it sits below the API Gateway BUFFERED cap (29s) and CloudFront
    origin read (60s), and below the bff read-timeout (60s). A long blocking sync request is cut here
    (client sees a 504), demonstrating exactly what the async submit + poll pattern avoids — every
    async request returns well under this limit.
  EOT
  type        = number
  default     = 20
}
