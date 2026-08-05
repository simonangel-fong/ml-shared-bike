# providers.tf

# ##############################
# Versions
# ##############################
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }

  backend "s3" {}
}

# ##############################
# Providers
# ##############################
provider "aws" {
  region = local.aws_region

  default_tags {
    tags = local.default_tags
  }
}

# CloudFront reads viewer certificates from us-east-1 only, whatever region the
# distribution serves from.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = local.default_tags
  }
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

data "aws_caller_identity" "current" {}
