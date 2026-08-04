# github-oidc.tf
#
# Lets GitHub Actions submit training jobs with no long-lived AWS keys: the
# workflow exchanges a short-lived OIDC token for this role.

locals {
  github_repo   = "simonangel-fong/ml-shared-bike"
  github_branch = "master"
}

# ##############################
# OIDC provider
# ##############################
# One provider per URL per account, created outside this stack. Referenced
# rather than managed here so applying does not fight whatever owns it.
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

    # Scoped to one repo and one branch. Without this any GitHub repo could
    # assume the role - it is the security boundary of the whole setup.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${local.github_repo}:ref:refs/heads/${local.github_branch}"]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name               = "${local.prefix_name}-github-actions-role"
  assume_role_policy = data.aws_iam_policy_document.github_assume.json

  tags = local.default_tags
}

# ##############################
# IAM: CI permissions
# ##############################
# Narrower than the execution role: CI submits jobs and reads results, it does
# not train. The training container runs as sagemaker_execution.
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

  # CI does not train - it hands the execution role to SageMaker, which does.
  # Submission fails without this, and the error does not name PassRole.
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
}

resource "aws_iam_role_policy" "github_actions" {
  name   = "${local.prefix_name}-github-actions-policy"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.github_actions.json
}
