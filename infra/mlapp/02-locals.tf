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
  aws_region = "ca-central-1"

  # ##############################
  # Serving
  # ##############################
  # Same image the training job ran on. sklearn 1.4-2 is the tag; the container
  # pip-installs app/inference/requirements.txt over it to reach 1.9.0, which is
  # what model.skops was written by. py312 because sklearn 1.9 needs >= 3.11.
  serving_image_uri = "341280168497.dkr.ecr.${local.aws_region}.amazonaws.com/sagemaker-scikit-learn:1.4-2-py312-cpu-py3"

  # Where the packaged inference code lands in the existing ml bucket.
  serve_prefix      = "serve/"
  serve_source_key  = "${local.serve_prefix}sourcedir.tar.gz"
  serve_source_uri  = "s3://${var.ml_bucket_name}/${local.serve_source_key}"
  inference_src_dir = "${path.module}/../../app/inference"
}


