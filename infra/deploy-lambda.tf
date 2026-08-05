# deploy-lambda.tf

locals {
  lambda_name      = "${local.prefix_name}-api"
  lambda_image_uri = "${aws_ecr_repository.api.repository_url}:${var.lambda_image_tag}"
}

# ##############################
# IAM
# ##############################
data "aws_iam_policy_document" "lambda_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${local.lambda_name}-role-lambda"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

# Logs only.
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# ##############################
# Lambda
# ##############################
resource "aws_lambda_function" "api" {
  count = var.enable_deployment ? 1 : 0

  function_name = local.lambda_name
  role          = aws_iam_role.lambda.arn
  package_type  = "Image"
  image_uri     = local.lambda_image_uri

  timeout = 30
  # by testing, memory < 3G leads to init phase timeout
  memory_size = 3008

  depends_on = [aws_cloudwatch_log_group.lambda]
}

# log
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.lambda_name}"
  retention_in_days = 7
}

# Test:
#   awscurl --service lambda --region ca-central-1 -X POST -d @payload.json <url>
# Or skip the URL entirely and invoke directly:
#   aws lambda invoke --function-name <name> --payload file://payload.json out.json
resource "aws_lambda_function_url" "api" {
  count = var.enable_deployment ? 1 : 0

  function_name      = aws_lambda_function.api[0].function_name
  authorization_type = "AWS_IAM"
}
