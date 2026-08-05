# deploy-lambda.tf

# ##############################
# IAM: lambda role
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
  name               = "${local.app_name}-role-lambda"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

# Logs only.
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# ##############################
# IAM: allow apigw invoke lambda
# ##############################
resource "aws_lambda_permission" "apigw" {
  count = var.enable_deployment ? 1 : 0

  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api[0].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this[0].execution_arn}/*/*"
}

# ##############################
# Lambda
# ##############################
resource "aws_lambda_function" "api" {
  count = var.enable_deployment ? 1 : 0

  function_name = local.app_name
  role          = aws_iam_role.lambda.arn
  package_type  = "Image"
  image_uri     = local.lambda_image_uri

  timeout = 30
  # by testing, memory < 3G leads to init phase timeout
  memory_size = 3008

  depends_on = [aws_cloudwatch_log_group.lambda]
}

# ##############################
# Function URL: 
# aws lambda invoke --function-name <name> --payload file://payload.json out.json
# ##############################
resource "aws_lambda_function_url" "api" {
  count = var.enable_deployment ? 1 : 0

  function_name      = aws_lambda_function.api[0].function_name
  authorization_type = "AWS_IAM"
}

# ##############################
# Log group: Lambda
# ##############################
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.app_name}"
  retention_in_days = 7
}
