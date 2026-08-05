# deploy-s3-web.tf

# ##############################
# S3 object
# ##############################
resource "aws_s3_object" "web_index" {
  count = var.enable_deployment ? 1 : 0

  bucket = aws_s3_bucket.ml.id
  key    = "web/index.html"

  source      = "${path.module}/../app/web/index.html"
  source_hash = filemd5("${path.module}/../app/web/index.html")

  kms_key_id             = aws_kms_key.this.arn
  server_side_encryption = "aws:kms"

  content_type = "text/html; charset=utf-8"
}


# ##############################
# Origin access
# ##############################
# OAC: bucket stays private; allow distribution read;
resource "aws_cloudfront_origin_access_control" "s3" {
  count = var.enable_deployment ? 1 : 0

  name                              = "${local.prefix_name}-web"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}
