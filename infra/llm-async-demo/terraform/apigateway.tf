# ---- Amazon API Gateway (REST, Regional) in front of the backend APIs ----
#
# CloudFront /api/* -> API Gateway (this file) -> internet-facing ALB -> BFF -> backend.
# A single greedy {proxy+} resource forwards every /api/* path and query string to the ALB with the
# secret X-Origin-Verify header injected (an ALB listener rule requires it, so the open ALB SG cannot
# be abused directly by IP). The async endpoints return quickly, so the default BUFFERED mode and
# 29s integration cap are fine — the long LLM call runs in the background, not inside a request.

# Shared secret injected by API Gateway and enforced at the ALB listener rule.
resource "random_password" "origin_verify" {
  length  = 32
  special = false
}

resource "aws_api_gateway_rest_api" "this" {
  name = "${var.app_name}-api"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = { Name = "${var.app_name}-api" }
}

# Resource tree: / -> /api -> /api/{proxy+}
resource "aws_api_gateway_resource" "api" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "api"
}

resource "aws_api_gateway_resource" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_resource.api.id
  path_part   = "{proxy+}"
}

# ANY method on the greedy proxy; the path segment is required so it can be mapped to the integration.
resource "aws_api_gateway_method" "proxy_any" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = aws_api_gateway_resource.proxy.id
  http_method   = "ANY"
  authorization = "NONE"

  request_parameters = {
    "method.request.path.proxy" = true
  }
}

# HTTP_PROXY to the public ALB: /api/{proxy} -> http://alb/api/{proxy}. Query strings pass through
# automatically with a proxy integration.
resource "aws_api_gateway_integration" "proxy" {
  rest_api_id             = aws_api_gateway_rest_api.this.id
  resource_id             = aws_api_gateway_resource.proxy.id
  http_method             = aws_api_gateway_method.proxy_any.http_method
  type                    = "HTTP_PROXY"
  integration_http_method = "ANY"
  uri                     = "http://${aws_lb.this.dns_name}/api/{proxy}"
  connection_type         = "INTERNET"
  passthrough_behavior    = "WHEN_NO_MATCH"

  request_parameters = {
    "integration.request.path.proxy"             = "method.request.path.proxy"
    "integration.request.header.X-Origin-Verify" = "'${random_password.origin_verify.result}'"
  }
}

# ---- Deployment + stage ----
resource "aws_api_gateway_deployment" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.api.id,
      aws_api_gateway_resource.proxy.id,
      aws_api_gateway_method.proxy_any.id,
      aws_api_gateway_integration.proxy.id,
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
