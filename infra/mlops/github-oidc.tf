# github-oidc.tf

locals {
  github_branch = "master"
  # IDs are stable across renames, which is the point:
  #   gh api repos/simonangel-fong/ml-shared-bike --jq '{id, owner_id: .owner.id}'
  github_owner    = "simonangel-fong"
  github_owner_id = "64545430"
  github_repo     = "ml-shared-bike"
  github_repo_id  = "1314382375"

  github_sub = join("", [
    "repo:${local.github_owner}@${local.github_owner_id}",
    "/${local.github_repo}@${local.github_repo_id}",
    ":ref:refs/heads/${local.github_branch}",
  ])
}

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

    # Scoped to repo and branch.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [local.github_sub]
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
}

resource "aws_iam_role_policy" "github_actions" {
  name   = "${local.prefix_name}-github-actions-policy"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.github_actions.json
}
