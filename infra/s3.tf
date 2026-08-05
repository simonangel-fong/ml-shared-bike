# s3.tf

# bucket structure:
# data/:            ml data
# data/raw/:        raw data export from data warehouse
# data/featured/:   featured data for ml
# data/split/:      split data for ml
# trains/:          training artifacts

locals {
  bucket_name = "${local.prefix_name}-${random_string.suffix.result}"
  bucket_prefix = [
    "data/",          # ml data
    "data/raw/",      # raw data export from data warehouse
    "data/featured/", # featured data for ml
    "data/split/",    # split data for ml
    "trains/",        # training artifacts
  ]
}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# ##############################
# S3
# ##############################
resource "aws_s3_bucket" "ml" {
  bucket        = local.bucket_name
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "ml" {
  bucket = aws_s3_bucket.ml.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "ml" {
  bucket = aws_s3_bucket.ml.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.this.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_versioning" "ml" {
  bucket = aws_s3_bucket.ml.id

  versioning_configuration {
    status = "Enabled"
  }
}

# ##############################
# prefixes keys
# ##############################
resource "aws_s3_object" "prefixes" {
  for_each = toset(local.bucket_prefix)

  bucket = aws_s3_bucket.ml.id
  key    = each.value
}

# ##############################
# Bucket policy
# ##############################
# SSE covers encryption at rest; this covers in transit.
data "aws_iam_policy_document" "ml_bucket" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.ml.arn, "${aws_s3_bucket.ml.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  # CloudFront reads the site through Origin Access Control, so the bucket
  # stays private. Scoped to web/* and to this distribution: the same bucket
  # holds training data and model artifacts, which must not become reachable
  # over the internet just because a website was added to it.
  dynamic "statement" {
    for_each = var.enable_deployment ? [1] : []

    content {
      sid       = "AllowCloudFrontReadWeb"
      effect    = "Allow"
      actions   = ["s3:GetObject"]
      resources = ["${aws_s3_bucket.ml.arn}/web/*"]

      principals {
        type        = "Service"
        identifiers = ["cloudfront.amazonaws.com"]
      }

      condition {
        test     = "StringEquals"
        variable = "AWS:SourceArn"
        values   = [aws_cloudfront_distribution.this[0].arn]
      }
    }
  }
}

resource "aws_s3_bucket_policy" "ml" {
  bucket = aws_s3_bucket.ml.id
  policy = data.aws_iam_policy_document.ml_bucket.json

  depends_on = [aws_s3_bucket_public_access_block.ml]
}

# ##############################
# Lifecycle
# ##############################
# Versioning 
resource "aws_s3_bucket_lifecycle_configuration" "ml" {
  bucket = aws_s3_bucket.ml.id

  # Failed multipart uploads are invisible to `s3 ls` but still billed.
  rule {
    id     = "abort-incomplete-multipart"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }

  rule {
    id     = "archive-raw-data"
    status = "Enabled"

    filter {
      prefix = "data/raw/"
    }

    transition {
      days          = 90
      storage_class = "STANDARD_IA"
    }
  }

  depends_on = [aws_s3_bucket_versioning.ml]
}
