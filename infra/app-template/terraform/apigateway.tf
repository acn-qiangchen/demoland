# ---- Amazon API Gateway (REST, Regional) in front of the backend APIs ----
#
# CloudFront /api/* -> API Gateway (this file) -> internet-facing ALB -> BFF -> backend.
# Both integrations use HTTP_PROXY to the public ALB and inject a secret header
# (X-Origin-Verify) that an ALB listener rule requires, so the open ALB SG cannot be
# abused directly by IP. STREAM response mode is used on both integrations to lift the
# 29s BUFFERED timeout cap and to passthrough the SSE (text/event-stream) response.

# Shared secret injected by API Gateway and enforced at the ALB listener rule.
resource "random_password" "origin_verify" {
  length  = 32
  special = false
}

resource "aws_api_gateway_rest_api" "this" {
  name = "${var.app_name}-api"

  # Regional (5-min idle) behind CloudFront — edge-optimized's 30s idle would cut streams.
  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = { Name = "${var.app_name}-api" }
}

# Resource tree: / -> /api -> /api/chat -> /api/chat/rest
resource "aws_api_gateway_resource" "api" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "api"
}

resource "aws_api_gateway_resource" "chat" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_resource.api.id
  path_part   = "chat"
}

resource "aws_api_gateway_resource" "chat_rest" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_resource.chat.id
  path_part   = "rest"
}

# ---- Methods ----
resource "aws_api_gateway_method" "chat_post" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = aws_api_gateway_resource.chat.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "chat_rest_post" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = aws_api_gateway_resource.chat_rest.id
  http_method   = "POST"
  authorization = "NONE"
}

# ---- Integrations (HTTP_PROXY to the public ALB, secret header injected) ----

# SSE stream: POST /api/chat -> ALB /api/chat
resource "aws_api_gateway_integration" "chat" {
  rest_api_id             = aws_api_gateway_rest_api.this.id
  resource_id             = aws_api_gateway_resource.chat.id
  http_method             = aws_api_gateway_method.chat_post.http_method
  type                    = "HTTP_PROXY"
  integration_http_method = "POST"
  uri                     = "http://${aws_lb.this.dns_name}/api/chat"
  connection_type         = "INTERNET"
  passthrough_behavior    = "WHEN_NO_MATCH"

  # STREAM lifts the 29s BUFFERED cap and passes text/event-stream frames through.
  response_transfer_mode = "STREAM"
  timeout_milliseconds   = 900000

  request_parameters = {
    "integration.request.header.X-Origin-Verify" = "'${random_password.origin_verify.result}'"
  }
}

# Blocking REST/JSON: POST /api/chat/rest -> ALB /api/chat/rest
resource "aws_api_gateway_integration" "chat_rest" {
  rest_api_id             = aws_api_gateway_rest_api.this.id
  resource_id             = aws_api_gateway_resource.chat_rest.id
  http_method             = aws_api_gateway_method.chat_rest_post.http_method
  type                    = "HTTP_PROXY"
  integration_http_method = "POST"
  uri                     = "http://${aws_lb.this.dns_name}/api/chat/rest"
  connection_type         = "INTERNET"
  passthrough_behavior    = "WHEN_NO_MATCH"

  # BUFFERED (the default) — classic REST semantics: API Gateway buffers the whole JSON
  # response before returning it, which keeps caching / body transforms / clean error status
  # available. Trade-off: the integration timeout is capped at 29s, so a blocking LLM answer
  # that runs longer than this will 504. (The SSE integration above uses STREAM to avoid that.)
  response_transfer_mode = "BUFFERED"
  timeout_milliseconds   = 29000

  request_parameters = {
    "integration.request.header.X-Origin-Verify" = "'${random_password.origin_verify.result}'"
  }
}

# ---- Deployment + stage ----
resource "aws_api_gateway_deployment" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id

  # Redeploy whenever the resource/method/integration config changes.
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.api.id,
      aws_api_gateway_resource.chat.id,
      aws_api_gateway_resource.chat_rest.id,
      aws_api_gateway_method.chat_post.id,
      aws_api_gateway_method.chat_rest_post.id,
      aws_api_gateway_integration.chat.id,
      aws_api_gateway_integration.chat_rest.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "this" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  deployment_id = aws_api_gateway_deployment.this.id
  stage_name    = "prod"
}
