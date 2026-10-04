resource "aws_lb" "this" {
  name               = "${var.app_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  idle_timeout = var.alb_idle_timeout

  tags = { Name = "${var.app_name}-alb" }
}

resource "aws_lb_target_group" "this" {
  # name_prefix (<= 6 chars) so an immutable-attribute change can replace the TG without the
  # "ResourceInUse" deadlock (paired with create_before_destroy below).
  name_prefix = "lrtg-"
  port        = 8081
  protocol    = "HTTP"
  vpc_id      = aws_vpc.this.id
  target_type = "ip"

  health_check {
    path                = "/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = { Name = "${var.app_name}-tg" }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  # Default: reject. Only requests carrying the secret X-Origin-Verify header (injected by
  # API Gateway) are forwarded — this is the real access control now that the SG is open.
  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      status_code  = "403"
    }
  }
}

# Forward only when API Gateway's injected secret header matches.
resource "aws_lb_listener_rule" "origin_verify" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 1

  condition {
    http_header {
      http_header_name = "X-Origin-Verify"
      values           = [random_password.origin_verify.result]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}
