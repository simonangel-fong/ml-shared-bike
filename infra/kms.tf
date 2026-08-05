# kms.tf

# ##############################
# KMS
# ##############################
resource "aws_kms_key" "this" {
  description             = "${local.prefix_name} sagemaker encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 7
  policy                  = data.aws_iam_policy_document.kms.json
}

resource "aws_kms_alias" "this" {
  name          = "alias/${local.prefix_name}"
  target_key_id = aws_kms_key.this.key_id
}

# ##############################
# IAM Policy
# ##############################
data "aws_iam_policy_document" "kms" {
  # Without this the key becomes unmanageable.
  statement {
    sid       = "AllowAccountAdmin"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  # allow assume role
  statement {
    sid    = "AllowAssumeRole"
    effect = "Allow"

    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]

    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.sagemaker_execution.arn]
    }
  }

  # allow sagemaker
  statement {
    sid    = "AllowSageMakerService"
    effect = "Allow"

    actions = [
      "kms:CreateGrant",
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:GenerateDataKey*",
    ]

    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["sagemaker.amazonaws.com"]
    }
  }

  # CloudFront reads the site objects, which are SSE-KMS encrypted like
  # everything else in the bucket. Without this the bucket policy grants
  # GetObject and S3 still answers 403, because the decrypt is refused.
  dynamic "statement" {
    for_each = var.enable_deployment ? [1] : []

    content {
      sid       = "AllowCloudFrontDecryptWeb"
      effect    = "Allow"
      actions   = ["kms:Decrypt"]
      resources = ["*"]

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

