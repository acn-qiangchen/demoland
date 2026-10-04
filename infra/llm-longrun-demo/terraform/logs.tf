resource "aws_cloudwatch_log_group" "this" {
  name              = "/ecs/${var.app_name}"
  retention_in_days = 7

  tags = { Name = "${var.app_name}-logs" }
}
