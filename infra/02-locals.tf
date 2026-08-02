# locals.tf

locals {

  # ##############################
  # Metadata
  # ##############################
  project     = "ml-shared-bike"
  prefix_name = "${local.project}-${var.env}"
  default_tags = {
    Project   = local.project
    Env       = var.env
    ManagedBy = "Terraform"
  }

  # ##############################
  # Providers
  # ##############################
  aws_region    = "ca-central-1"
  aws_kms_alias = "alias/default-key"
}


