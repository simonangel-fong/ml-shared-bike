# deploy-cloudfront.tf

locals {
  apigw_domain = var.enable_deployment ? replace(aws_apigatewayv2_api.this[0].api_endpoint, "https://", "") : ""
}

# ##############################
# Certificate
# ##############################
# us-east-1 provider: CloudFront accepts viewer certificates from there only.
data "aws_acm_certificate" "this" {
  count    = var.enable_deployment ? 1 : 0
  provider = aws.us_east_1

  domain      = var.acm_certificate_domain
  statuses    = ["ISSUED"]
  most_recent = true
}

# ##############################
# Policies
# ##############################
# Predictions are keyed on the request body, which CloudFront does not include
# in its cache key - caching would serve one caller's result to another.
# The managed policy rather than an equivalent of our own: a custom policy with
# zero TTLs is rejected outright.
data "aws_cloudfront_cache_policy" "no_cache" {
  name = "Managed-CachingDisabled"
}

# Host is deliberately absent: api gateway routes on it, and forwarding the
# CloudFront hostname gives a 403.
resource "aws_cloudfront_origin_request_policy" "api" {
  name    = "${local.prefix_name}-api-origin"
  comment = "Forward everything except Host to the api gateway"

  cookies_config {
    cookie_behavior = "none"
  }
  headers_config {
    header_behavior = "whitelist"
    headers {
      # The two access-control-request-* headers are what make a preflight a
      # preflight. Without them api gateway sees a plain OPTIONS, answers a
      # bare 204 with no CORS headers, and every browser POST fails as
      # "Failed to fetch" while curl works.
      items = [
        "content-type",
        "origin",
        "accept",
        "access-control-request-method",
        "access-control-request-headers",
      ]
    }
  }
  query_strings_config {
    query_string_behavior = "all"
  }
}

# ##############################
# Distribution
# ##############################
resource "aws_cloudfront_distribution" "this" {
  count = var.enable_deployment ? 1 : 0

  enabled         = true
  comment         = "${local.prefix_name} prediction api"
  is_ipv6_enabled = true
  aliases         = [var.domain_name]

  # NA + Europe; the audience is Toronto.
  price_class = "PriceClass_100"

  origin {
    origin_id   = "apigw"
    domain_name = local.apigw_domain

    custom_origin_config {
      origin_protocol_policy = "https-only"
      http_port              = 80
      https_port             = 443
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id = "apigw"

    # OPTIONS so the browser preflight reaches the gateway rather than being
    # rejected at the edge.
    allowed_methods = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods  = ["GET", "HEAD"]

    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    cache_policy_id          = data.aws_cloudfront_cache_policy.no_cache.id
    origin_request_policy_id = aws_cloudfront_origin_request_policy.api.id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = data.aws_acm_certificate.this[0].arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}
