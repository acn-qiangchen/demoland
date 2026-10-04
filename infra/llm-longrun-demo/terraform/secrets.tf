resource "aws_secretsmanager_secret" "openai" {
  name                    = "${var.app_name}-openai-api-key"
  description             = "OpenAI API key injected into the ${var.app_name} ECS task"
  recovery_window_in_days = 0 # allow immediate re-create on destroy/redeploy
}

resource "aws_secretsmanager_secret_version" "openai" {
  secret_id     = aws_secretsmanager_secret.openai.id
  secret_string = var.openai_api_key
}
