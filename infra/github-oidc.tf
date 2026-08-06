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

    # Scoped to this repo, by id rather than name so a rename cannot silently
    # widen it. Two subjects: the default branch, and pull requests against it.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = local.github_subs
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

  # ##############################
  # Deployment
  # ##############################
  # Deliberately broad to start with. `terraform apply` touches every resource
  # in this stack and a policy enumerated up front is wrong in both directions:
  # it breaks on the first resource nobody predicted, and the fix is a commit
  # that CI itself cannot deploy.
  #
  # To narrow it: run the three workflows, read the CloudTrail events they
  # actually produce, and replace this with those actions. Until that has been
  # done, treat a compromise of this workflow as a compromise of the stack.
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
      # acm:* rather than the two obvious reads: the aws_acm_certificate data
      # source also calls GetCertificate, which an enumerated list missed and
      # only failed once CI ran. Narrow this from CloudTrail, not from guesses.
      "acm:*",
    ]

    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "github_actions" {
  name   = "${local.prefix_name}-github-actions-policy"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.github_actions.json
}
