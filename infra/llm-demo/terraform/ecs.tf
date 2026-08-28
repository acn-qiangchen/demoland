resource "aws_ecs_cluster" "this" {
  name = "${var.app_name}-cluster"
}

resource "aws_ecs_task_definition" "this" {
  family                   = var.app_name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.container_cpu
  memory                   = var.container_memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([
    {
      # backend — internal only; reachable solely by the bff over loopback (no ALB target).
      name      = var.app_name
      image     = "${aws_ecr_repository.this.repository_url}:${var.image_tag}"
      essential = true

      portMappings = [
        {
          containerPort = 8080
          protocol      = "tcp"
        }
      ]

      # OpenAI key injected from Secrets Manager as an env var (never in the task def in plaintext).
      secrets = [
        {
          name      = "SPRING_AI_OPENAI_API_KEY"
          valueFrom = aws_secretsmanager_secret.openai.arn
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.this.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "backend"
        }
      }
    },
    {
      # bff — ALB-facing relay; reaches the backend over the shared task loopback interface.
      name      = "${var.app_name}-bff"
      image     = "${aws_ecr_repository.bff.repository_url}:${var.image_tag}"
      essential = true

      portMappings = [
        {
          containerPort = 8081
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "LLM_SERVICE_BASE_URL"
          value = "http://localhost:8080"
        }
      ]

      dependsOn = [
        {
          containerName = var.app_name
          condition     = "START"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.this.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "bff"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "this" {
  name            = "${var.app_name}-svc"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets = aws_subnet.public[*].id
    # No NAT gateway; tasks run in public subnets with a public IP to reach ECR + OpenAI.
    assign_public_ip = true
    security_groups  = [aws_security_group.ecs.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.this.arn
    container_name   = "${var.app_name}-bff"
    container_port   = 8081
  }

  # Give tasks time to pass health checks before ELB marks them unhealthy.
  # Two JVMs boot in one task, so allow extra warm-up time.
  health_check_grace_period_seconds = 120

  depends_on = [aws_lb_listener.http]
}
