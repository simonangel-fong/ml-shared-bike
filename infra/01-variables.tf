# variables.tf

# ##############################
# Metadata
# ##############################
variable "env" {
  default = "ml"
}

variable "project" {
  default = "toronto-shared-bike"
}

# One switch for the whole serving stack: lambda, api gateway, cloudfront, dns.
# Off leaves the ecr repo and iam behind, so an image can be pushed before the
# function that runs it exists.
variable "enable_deployment" {
  description = "Create the serving stack. Requires an image already pushed at lambda_image_tag."
  type        = bool
  default     = true
}

# ##############################
# Lambda
# ##############################
variable "lambda_image_tag" {
  description = "Tag of the API image in the project ECR repo."
  type        = string
  default     = "latest"
}

# ##############################
# Custom domain
# ##############################
variable "domain_name" {
  description = "Public hostname for the API."
  type        = string
  default     = ""
}

# Looked up rather than passed as an arn: the cert is long lived and owned
# elsewhere, and a name is easier to read than a uuid.
variable "acm_certificate_domain" {
  description = "Domain of the ACM cert to look up in us-east-1. Must cover domain_name."
  type        = string
  default     = ""
}

# ##############################
# Cloudflare
# ##############################
variable "cloudflare_zone_id" {
  description = "Zone id for the domain."
  type        = string
  default     = ""
}

variable "cloudflare_api_token" {
  description = "Token with Zone:DNS:Edit."
  type        = string
  default     = ""
  sensitive   = true
}
