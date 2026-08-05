# locals.tf

locals {

  # ##############################
  # Metadata
  # ##############################
  prefix_name = "${var.project}-${var.env}"
  app_name    = "${local.prefix_name}-api"
  default_tags = {
    Project   = var.project
    Env       = var.env
    ManagedBy = "Terraform"
  }

  # ##############################
  # Providers
  # ##############################
  aws_region    = "ca-central-1"
  aws_kms_alias = "alias/default-key"

  # ##############################
  # Lambda
  # ##############################
  lambda_name      = "${local.prefix_name}-api"
  lambda_image_uri = "${aws_ecr_repository.api.repository_url}:${var.lambda_image_tag}"

}


