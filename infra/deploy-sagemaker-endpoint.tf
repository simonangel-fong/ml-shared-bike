# deploy-sagemaker-endpoint.tf

locals {
  sagemaker_endpoint_enabled  = var.model_artifact_uri != ""
  sagemaker_endpoint_revision = local.sagemaker_endpoint_enabled ? substr(sha1("${var.model_artifact_uri}${data.archive_file.inference_code[0].output_md5}"), 0, 8) : ""
}

# ##############################
# Inference code
# ##############################
data "archive_file" "inference_code" {
  count = local.sagemaker_endpoint_enabled ? 1 : 0

  type        = "tar.gz"
  source_dir  = "${path.module}/../app/inference/"
  output_path = "${path.module}/.terraform/tmp/sourcedir.tar.gz"
  excludes    = ["__pycache__"]
}

resource "aws_s3_object" "inference_code" {
  count = local.sagemaker_endpoint_enabled ? 1 : 0

  bucket = aws_s3_bucket.ml.id
  key    = "inference/sourcedir-${data.archive_file.inference_code[0].output_md5}.tar.gz"
  source = data.archive_file.inference_code[0].output_path
  etag   = data.archive_file.inference_code[0].output_md5
}

# ##############################
# Model
# ##############################
resource "aws_sagemaker_model" "this" {
  count = local.sagemaker_endpoint_enabled ? 1 : 0

  name               = "${local.prefix_name}-${local.sagemaker_endpoint_revision}"
  execution_role_arn = aws_iam_role.sagemaker_execution.arn

  primary_container {
    image          = var.inference_image
    model_data_url = var.model_artifact_uri

    environment = {
      SAGEMAKER_PROGRAM             = "inference.py"
      SAGEMAKER_SUBMIT_DIRECTORY    = "s3://${aws_s3_bucket.ml.id}/${aws_s3_object.inference_code[0].key}"
      SAGEMAKER_CONTAINER_LOG_LEVEL = "20"
      SAGEMAKER_REGION              = local.aws_region
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ##############################
# Endpoint
# ##############################
resource "aws_sagemaker_endpoint_configuration" "this" {
  count = local.sagemaker_endpoint_enabled ? 1 : 0

  name        = "${local.prefix_name}-${local.sagemaker_endpoint_revision}"
  kms_key_arn = aws_kms_key.this.arn

  production_variants {
    variant_name = "AllTraffic"
    model_name   = aws_sagemaker_model.this[0].name

    serverless_config {
      memory_size_in_mb = 2048
      max_concurrency   = 2
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_sagemaker_endpoint" "this" {
  count = local.sagemaker_endpoint_enabled ? 1 : 0

  name                 = "${local.prefix_name}"
  endpoint_config_name = aws_sagemaker_endpoint_configuration.this[0].name
}
