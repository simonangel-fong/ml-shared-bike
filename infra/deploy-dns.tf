# deploy-dns.tf

resource "cloudflare_record" "api" {
  # if deploy enabled
  count = var.enable_deployment ? 1 : 0

  zone_id = var.cloudflare_zone_id
  name    = var.domain_name
  type    = "CNAME"
  content = aws_cloudfront_distribution.this[0].domain_name
  ttl     = 1 # automatic

  proxied = false

  comment = "Toronto shared bike machine learning website."
}
