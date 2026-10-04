# ---- Amazon API Gateway (REST, Regional) in front of the backend APIs ----
#
# CloudFront /api/* -> API Gateway (this file) -> internet-facing ALB -> BFF -> backend.
# Two integrations share one ALB origin and both inject the secret X-Origin-Verify header (an ALB
# listener rule requires it, so the open ALB SG cannot be abused directly by IP):
#
#   * An explicit /api/chat POST in STREAM mode — the SSE path (fix 1). STREAM lifts the 29s BUFFERED
#     cap and passes the text/event-stream frames through so tokens surface progressively.
#   * A greedy /api/{proxy+} ANY in the default BUFFERED mode — everything else (/api/chat/sync,
#     /api/chat/async, /api/jobs/{id}). The sync baseline returns slowly but the ALB idle timeout cuts
#     it first (the whole point of the demo); the async submit/poll calls return quickly, so the 29s
#     BUFFERED cap is never the binding limit.
#
# Routing precedence: API Gateway matches the exact path /api/chat to the explicit resource, and every
# deeper path (/api/chat/sync, /api/jobs/*) to the greedy {proxy+}.

# Shared secret injected by API Gateway and enforced at the ALB listener rule.
resource "random_password" "origin_verify" {
  length  = 32
  special = false
}

resource "aws_api_gateway_rest_api" "this" {
  name = "${var.app_name}-api"

  # Regional (5-min idle) behind CloudFront — edge-optimized's 30s idle would cut SSE streams.
  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = { Name = "${var.app_name}-api" }
}

# Resource tree: / -> /api -> { /api/chat (explicit), /api/{proxy+} (greedy) }
resource "aws_api_gateway_resource" "api" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "api"
}

# Explicit /api/chat for the SSE stream (STREAM integration below).
resource "aws_api_gateway_resource" "chat" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_resource.api.id
  path_part   = "chat"
}

# Greedy catch-all for everything deeper under /api.
resource "aws_api_gateway_resource" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_resource.api.id
  path_part   = "{proxy+}"
}

# ---- Methods ----

resource "aws_api_gateway_method" "chat_post" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = aws_api_gateway_resource.chat.id
  http_method   = "POST"
  authorization = "NONE"
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

# Everything else: ANY /api/{proxy} -> http://alb/api/{proxy}. Query strings pass through
# automatically with a proxy integration. BUFFERED (default) is fine — the async endpoints return
# quickly, and the sync baseline is cut by the ALB idle timeout before the 29s cap matters.
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

  # Redeploy whenever the resource/method/integration config changes.
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.api.id,
      aws_api_gateway_resource.chat.id,
      aws_api_gateway_resource.proxy.id,
      aws_api_gateway_method.chat_post.id,
      aws_api_gateway_method.proxy_any.id,
      aws_api_gateway_integration.chat.id,
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
