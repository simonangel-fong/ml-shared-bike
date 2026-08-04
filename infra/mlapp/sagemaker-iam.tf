# sagemaker-iam.tf

# Serving gets its own role rather than reusing the mlops training role. The
# training role is *FullAccess on SageMaker and S3; an endpoint that is only
# ever asked to read two objects should not carry that.

data "aws_iam_policy_document" "sagemaker_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["sagemaker.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "sagemaker_serving" {
  name               = "${local.prefix_name}-sagemaker-serving-role"
  assume_role_policy = data.aws_iam_policy_document.sagemaker_assume.json
}

data "aws_s3_bucket" "ml" {
  bucket = var.ml_bucket_name
}

# The bucket is SSE-KMS, so reading the model is a KMS Decrypt as well as a
# GetObject. Without the KMS grant the endpoint fails at model download with an
# opaque "unable to download" and no S3 error.
data "aws_kms_key" "ml" {
  key_id = "alias/${local.prefix_name}"
}

data "aws_iam_policy_document" "sagemaker_serving" {
  statement {
    sid    = "ReadModelArtifacts"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
    ]

    resources = [
      "${data.aws_s3_bucket.ml.arn}/trains/*",
      "${data.aws_s3_bucket.ml.arn}/${local.serve_prefix}*",
    ]
  }

  statement {
    sid       = "ListBucketForModelPrefix"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [data.aws_s3_bucket.ml.arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["trains/*", "${local.serve_prefix}*"]
    }
  }

  statement {
    sid       = "DecryptBucketObjects"
    effect    = "Allow"
    actions   = ["kms:Decrypt", "kms:DescribeKey"]
    resources = [data.aws_kms_key.ml.arn]
  }

  statement {
    sid    = "EndpointLogsAndMetrics"
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
      "cloudwatch:PutMetricData",
    ]

    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "sagemaker_serving" {
  name   = "${local.prefix_name}-sagemaker-serving-policy"
  role   = aws_iam_role.sagemaker_serving.id
  policy = data.aws_iam_policy_document.sagemaker_serving.json
}
