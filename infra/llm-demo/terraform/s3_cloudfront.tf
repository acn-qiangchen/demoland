data "aws_caller_identity" "current" {}

# ---- Private S3 bucket holding the static frontend (index.html) ----
resource "aws_s3_bucket" "frontend" {
  bucket        = "${var.app_name}-frontend-${data.aws_caller_identity.current.account_id}"
  force_destroy = true

  tags = { Name = "${var.app_name}-frontend" }
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket                  = aws_s3_bucket.frontend.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---- Origin Access Control so only CloudFront can read the bucket ----
resource "aws_cloudfront_origin_access_control" "frontend" {
  name                              = "${var.app_name}-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

locals {
  s3_origin_id    = "${var.app_name}-s3"
  apigw_origin_id = "${var.app_name}-apigw"
}

resource "aws_cloudfront_distribution" "this" {
  enabled             = true
  default_root_object = "index.html"
  comment             = "${var.app_name} — static frontend + /api/* to API Gateway"
  price_class         = "PriceClass_100"

  # Origin 1: private S3 bucket (static frontend)
  origin {
    domain_name              = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_id                = local.s3_origin_id
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend.id
  }

  # Origin 2: API Gateway (REST, Regional). CloudFront -> execute-api over HTTPS.
  # origin_path prepends the stage so viewer /api/chat -> /prod/api/chat at the API.
  origin {
    domain_name = "${aws_api_gateway_rest_api.this.id}.execute-api.${var.aws_region}.amazonaws.com"
    origin_id   = local.apigw_origin_id
    origin_path = "/${aws_api_gateway_stage.this.stage_name}"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
      # CloudFront's origin read timeout maxes at 60s without a service-quota increase.
      # Fine for typical OpenAI first-token latency; raise the quota if you see truncated streams.
      origin_read_timeout = 60
    }
  }

  # Default behavior: everything -> S3 static content.
  default_cache_behavior {
    target_origin_id       = local.s3_origin_id
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]

    # AWS managed "CachingOptimized" policy.
    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6"
  }

  # /api/* -> API Gateway, caching disabled, all methods (incl. POST) forwarded.
  ordered_cache_behavior {
    path_pattern           = "/api/*"
    target_origin_id       = local.apigw_origin_id
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods         = ["GET", "HEAD"]

    # AWS managed "CachingDisabled" policy.
    cache_policy_id = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
    # AWS managed "AllViewerExceptHostHeader" origin request policy — forwards everything
    # except the viewer Host header. Forwarding the viewer Host to execute-api returns 403,
    # so the Host must be dropped (CloudFront then sends the execute-api Host).
    origin_request_policy_id = "b689b0a8-53d0-40ab-baf2-68738e2966ac"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    # Default *.cloudfront.net certificate — no custom domain needed.
    cloudfront_default_certificate = true
  }

  tags = { Name = "${var.app_name}-cdn" }
}

# ---- Bucket policy: allow only this CloudFront distribution to read objects ----
data "aws_iam_policy_document" "frontend" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.frontend.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.this.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  policy = data.aws_iam_policy_document.frontend.json
}
