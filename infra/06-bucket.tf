# bucket.tf
resource "random_string" "bucket_suffix" {
  length  = 6
  upper   = false
  special = false
}

# ##############################
# IAM: Sagemaker access S3
# ##############################
resource "aws_iam_role_policy" "sagemaker_s3_access" {
  name = "${local.prefix_name}-sagemaker-s3-access"
  role = aws_iam_role.sagemaker_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
          "s3:DeleteObject"
        ]
        Resource = [
          "${aws_s3_bucket.ml_data.arn}",
          "${aws_s3_bucket.ml_data.arn}/*",
          "${aws_s3_bucket.model_artifacts.arn}",
          "${aws_s3_bucket.model_artifacts.arn}/*"
        ]
      }
    ]
  })
}

# ##############################
# Bucket: data
# ##############################
resource "aws_s3_bucket" "ml_data" {
  bucket = "${local.prefix_name}-data-${random_string.bucket_suffix.result}"

  tags = merge(local.default_tags, {
    tier = "TrainingData"
  })
}

resource "aws_s3_bucket_server_side_encryption_configuration" "ml_data" {
  bucket = aws_s3_bucket.ml_data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = data.aws_kms_key.default.arn
    }
  }
}

# keys for stages
resource "aws_s3_object" "data_folders" {
  for_each = toset(["raw/", "processed/", "features/", "training/", "validation/", "test/"])

  bucket = aws_s3_bucket.ml_data.id
  key    = each.value
}

# ##############################
# Bucket: Model artifacts
# ##############################
resource "aws_s3_bucket" "model_artifacts" {
  bucket = "${local.prefix_name}-model-artifacts-${random_string.bucket_suffix.result}"

  tags = merge(local.default_tags, {
    tier = "ModelArtifacts"
  })
}

resource "aws_s3_bucket_versioning" "model_artifacts" {
  bucket = aws_s3_bucket.model_artifacts.id

  versioning_configuration {
    status = "Enabled"
  }
}
