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

  # ##############################
  # OIDC: github
  # ##############################
  github_branch = "master"
  # IDs are stable across renames, which is the point:
  #   gh api repos/simonangel-fong/ml-shared-bike --jq '{id, owner_id: .owner.id}'
  github_owner    = "simonangel-fong"
  github_owner_id = "64545430"
  github_repo     = "Project-Toronto-Shared-Bike-ML"
  github_repo_id  = "1314382375"

  github_repo_id_prefix = join("", [
    "repo:${local.github_owner}@${local.github_owner_id}",
    "/${local.github_repo}@${local.github_repo_id}",
  ])

  github_subs = [
    "${local.github_repo_id_prefix}:ref:refs/heads/${local.github_branch}",
    "${local.github_repo_id_prefix}:pull_request",
  ]
}


