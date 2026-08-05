# deploy-dns.tf

resource "cloudflare_record" "api" {
  count = var.enable_deployment ? 1 : 0

  zone_id = var.cloudflare_zone_id
  name    = var.domain_name
  type    = "CNAME"
  content = aws_cloudfront_distribution.this[0].domain_name
  ttl     = 1 # automatic

  # Not proxied: Cloudflare in front of CloudFront sends its own SNI, which
  # does not match the distribution alias, and CloudFront answers 403. It reads
  # as a certificate problem and is not one.
  proxied = false

  comment = "Managed by Terraform - prediction api via CloudFront"
}
