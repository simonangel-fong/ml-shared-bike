# github-oidc.tf



# ##############################
# OIDC provider
# ##############################
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

# ##############################
# IAM: CI role
# ##############################
data "aws_iam_policy_document" "github_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = local.github_subs
    }
  }
}

resource "aws_iam_role" "github_actions_oidc" {
  name               = "${local.prefix_name}-github-actions-oidc-role"
  assume_role_policy = data.aws_iam_policy_document.github_assume.json

  tags = local.default_tags
}

# ##############################
# IAM: CI permissions
# ##############################
data "aws_iam_policy_document" "github_actions" {
  statement {
    sid    = "SubmitAndPollTrainingJobs"
    effect = "Allow"

    actions = [
      "sagemaker:CreateTrainingJob",
      "sagemaker:DescribeTrainingJob",
      "sagemaker:StopTrainingJob",
      "sagemaker:AddTags",
      "sagemaker:ListTrainingJobs",
    ]

    resources = ["*"]
  }

  statement {
    sid       = "PassExecutionRoleToSageMaker"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.sagemaker_execution.arn]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["sagemaker.amazonaws.com"]
    }
  }

  statement {
    sid       = "ListMlBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.ml.arn]
  }

  # Uploads sourcedir.tar.gz under trains/ and reads the split and results.
  statement {
    sid    = "ReadWriteTrainingObjects"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:PutObject",
    ]

    resources = [
      "${aws_s3_bucket.ml.arn}/data/split/*",
      "${aws_s3_bucket.ml.arn}/trains/*",
    ]
  }

  # The bucket is SSE-KMS, so object access needs the key as well.
  statement {
    sid    = "UseBucketKey"
    effect = "Allow"

    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey",
      "kms:DescribeKey",
    ]

    resources = [aws_kms_key.this.arn]
  }

  # Streaming job logs back into the workflow output.
  statement {
    sid    = "ReadTrainingLogs"
    effect = "Allow"

    actions = [
      "logs:GetLogEvents",
      "logs:DescribeLogStreams",
      "logs:DescribeLogGroups",
    ]

    resources = ["*"]
  }

  # deployment scope
  statement {
    sid    = "DeployStack"
    effect = "Allow"

    actions = [
      "ecr:*",
      "lambda:*",
      "apigateway:*",
      "cloudfront:*",
      "s3:*",
      "iam:*",
      "kms:*",
      "logs:*",
      "acm:*",
    ]

    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "github_actions" {
  name   = "${local.prefix_name}-github-actions-policy"
  role   = aws_iam_role.github_actions_oidc.id
  policy = data.aws_iam_policy_document.github_actions.json
}
