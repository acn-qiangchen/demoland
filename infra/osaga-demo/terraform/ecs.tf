resource "aws_ecs_cluster" "this" {
  name = "${var.app_name}-cluster"
}

# Task definition only — there is NO ECS service. Tasks are launched on demand by
# Step Functions (ecs:runTask.sync). The container env below holds defaults; the real
# INPUT_BUCKET / INPUT_KEY / OUTPUT_BUCKET / OUTPUT_KEY values arrive per-run as
# ContainerOverrides from the state machine.
resource "aws_ecs_task_definition" "this" {
  family                   = var.app_name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([
    {
      name      = var.app_name
      image     = "${aws_ecr_repository.this.repository_url}:${var.image_tag}"
      essential = true

      # Defaults so the container definition is valid; overridden at RunTask time.
      environment = [
        { name = "INPUT_BUCKET", value = aws_s3_bucket.input.bucket },
        { name = "OUTPUT_BUCKET", value = aws_s3_bucket.output.bucket },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.this.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "task"
        }
      }
    }
  ])
}
