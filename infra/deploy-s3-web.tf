# deploy-s3-web.tf

# The site content is NOT here. Terraform owns the plumbing - the bucket, the
# OAC, the bucket policy - and .github/workflows/app-frontend.yml owns what is
# in web/, via `aws s3 cp`.
#
# Both owning it would mean the next `terraform apply` silently reverts whatever
# CI last uploaded, which looks like a deploy that vanished.


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
