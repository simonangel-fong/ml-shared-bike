# sagemaker-endpoint.tf

# model -> endpoint config -> endpoint. The first two are immutable in the API:
# changing the artifact or the container env forces a new one, so both carry a
# content-derived name and create_before_destroy. The endpoint itself is
# updated in place, so its name is stable and safe to hand to API Gateway.

locals {
  # Fingerprints everything baked into the model. Rolls the name on a retrain
  # or an inference.py change; nothing else touches it.
  model_revision = substr(md5(join("|", [
    var.model_data_url,
    local.serving_image_uri,
    local.inference_hash,
  ])), 0, 8)

  model_name           = "${local.prefix_name}-demand-${local.model_revision}"
  endpoint_config_name = "${local.prefix_name}-demand-${local.model_revision}-${var.endpoint_memory_mb}-${var.endpoint_max_concurrency}"
  endpoint_name        = "${local.prefix_name}-demand"
}

# ##############################
# Model
# ##############################
resource "aws_sagemaker_model" "demand" {
  name               = local.model_name
  execution_role_arn = aws_iam_role.sagemaker_serving.arn

  primary_container {
    image          = local.serving_image_uri
    model_data_url = var.model_data_url

    environment = {
      SAGEMAKER_PROGRAM             = "inference.py"
      SAGEMAKER_SUBMIT_DIRECTORY    = local.serve_source_uri
      SAGEMAKER_CONTAINER_LOG_LEVEL = "20"
      SAGEMAKER_REGION              = local.aws_region

      # The container pip-installs requirements.txt from the submit directory
      # only when this is set; sklearn 1.9.0 is not optional here - 1.4.2
      # cannot load the artifact.
      SAGEMAKER_REQUIREMENTS = "requirements.txt"

      # The py312 image is Debian-based and marks the system Python as
      # externally managed (PEP 668), so the serving stack's
      # `pip install . -r requirements.txt` dies with
      # "error: externally-managed-environment" before gunicorn ever starts -
      # which surfaces only as "the model process exited". pip reads this
      # variable itself; there is no hook to pass the flag on the command line.
      PIP_BREAK_SYSTEM_PACKAGES = "1"

      # Serving runs unprivileged, so pip cannot write to dist-packages and
      # falls back to a user install under $HOME/.local - where the import of
      # "inference" then fails, because the home directory is /home/sbx_userNNNN
      # with a per-container UID that is not on sys.path. Pinning the user base
      # to a fixed writable path makes the install target and the import path
      # agree: Python adds $PYTHONUSERBASE/lib/python3.12/site-packages itself.
      PYTHONUSERBASE = "/tmp/pylibs"
      PIP_USER       = "1"
    }
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_iam_role_policy.sagemaker_serving,
    aws_s3_object.inference_source,
  ]
}

# ##############################
# Endpoint config (serverless)
# ##############################
resource "aws_sagemaker_endpoint_configuration" "demand" {
  name = local.endpoint_config_name

  production_variants {
    variant_name = "AllTraffic"
    model_name   = aws_sagemaker_model.demand.name

    # Scale-to-zero. A model retrained annually and queried by a demo site does
    # not justify an always-on instance.
    serverless_config {
      memory_size_in_mb = var.endpoint_memory_mb
      max_concurrency   = var.endpoint_max_concurrency
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ##############################
# Endpoint
# ##############################
resource "aws_sagemaker_endpoint" "demand" {
  name                 = local.endpoint_name
  endpoint_config_name = aws_sagemaker_endpoint_configuration.demand.name
}

# ##############################
# Logs
# ##############################
# The endpoint creates this group itself on first invocation, with never-expire
# retention. Declaring it keeps the retention managed; the endpoint reuses it.
resource "aws_cloudwatch_log_group" "endpoint" {
  name              = "/aws/sagemaker/Endpoints/${local.endpoint_name}"
  retention_in_days = 14
}
