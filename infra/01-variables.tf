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

variable "enable_deployment" {
  description = "Create the serving stack. Requires an image already pushed at lambda_image_tag."
  type        = bool
  default     = true
}

# ##############################
# Lambda Docker image tag
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
