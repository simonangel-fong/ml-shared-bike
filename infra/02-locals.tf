# locals.tf

locals {

  # ##############################
  # Metadata
  # ##############################
  prefix_name = "${var.project}-${var.env}"
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
}


