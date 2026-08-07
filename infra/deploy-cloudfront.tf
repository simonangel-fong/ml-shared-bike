# deploy-cloudfront.tf

locals {
  apigw_domain = var.enable_deployment ? replace(aws_apigatewayv2_api.this[0].api_endpoint, "https://", "") : ""
}

# ##############################
# Certificate
# ##############################
data "aws_acm_certificate" "this" {
  count = var.enable_deployment ? 1 : 0

  domain      = var.acm_certificate_domain
  provider    = aws.us_east_1 # provider us-east-1 
  statuses    = ["ISSUED"]
  most_recent = true
}

# ##############################
# Policies
# ##############################
# turns off caching
data "aws_cloudfront_cache_policy" "no_cache" {
  name = "Managed-CachingDisabled"
}

# keeping the cache key as light as possible: no Headers,Cookies,Query Strings
data "aws_cloudfront_cache_policy" "optimized" {
  name = "Managed-CachingOptimized"
}

# forward
resource "aws_cloudfront_origin_request_policy" "api" {
  name    = "${local.prefix_name}-api-origin"
  comment = "Forward everything except Host to the api gateway"

  cookies_config {
    cookie_behavior = "none"
  }
  headers_config {
    header_behavior = "whitelist"
    headers {
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

  # The site is what a visitor gets by default; the api is a path under it.
  default_root_object = "index.html"

  # origin: api
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

  # origin: s3
  origin {
    origin_id                = "s3web"
    domain_name              = aws_s3_bucket.ml.bucket_regional_domain_name
    origin_path              = "/web"
    origin_access_control_id = aws_cloudfront_origin_access_control.s3[0].id
  }

  # /: the static site. Cached.
  default_cache_behavior {
    target_origin_id = "s3web"

    allowed_methods = ["GET", "HEAD", "OPTIONS"]
    cached_methods  = ["GET", "HEAD"]

    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    cache_policy_id = data.aws_cloudfront_cache_policy.optimized.id
  }

  # /api/*: api gateway, uncached.
  ordered_cache_behavior {
    path_pattern     = "/api/*"
    target_origin_id = "apigw"

    allowed_methods = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods  = ["GET", "HEAD"]

    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    cache_policy_id          = data.aws_cloudfront_cache_policy.no_cache.id
    origin_request_policy_id = aws_cloudfront_origin_request_policy.api.id
  }

  custom_error_response {
    error_caching_min_ttl = 10
    error_code            = 404
    response_code         = 200           # Changes the browser status to 200
    response_page_path    = "/error.html" # Path to your error HTML asset
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
