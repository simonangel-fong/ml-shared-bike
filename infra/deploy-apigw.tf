# deploy-apigw.tf

# HTTP API in front of the prediction Lambda.
#
# HTTP API (v2) rather than REST API (v1): roughly a third the cost, native
# CORS, and none of the v1 features (request validators, usage plans, WAF
# integration) are wanted here. The route is a single POST.
#
# The function URL in deploy-lambda.tf stays for direct testing; this is the
# path the browser front end will use in phase 4.

locals {
  api_name = "${local.prefix_name}-api-gw"
}

resource "aws_apigatewayv2_api" "this" {
  count = local.lambda_enabled ? 1 : 0

  name          = local.api_name
  protocol_type = "HTTP"
  description   = "Prediction API for the annual demand model"

  # The front end is served from a different origin (CloudFront in phase 4), so
  # the browser preflights. Without this the call fails in the browser while
  # working fine from curl.
  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["POST", "OPTIONS"]
    allow_headers = ["content-type"]
    max_age       = 300
  }
}

# AWS_PROXY passes the whole request through and expects the function to return
# {statusCode, headers, body} - which handler.py already does, so no mapping
# templates are involved.
resource "aws_apigatewayv2_integration" "lambda" {
  count = local.lambda_enabled ? 1 : 0

  api_id                 = aws_apigatewayv2_api.this[0].id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.api[0].invoke_arn
  payload_format_version = "2.0"

  # Comfortably over the ~3.2s cold start; a warm call is ~18ms.
  timeout_milliseconds = 29000
}

resource "aws_apigatewayv2_route" "predict" {
  count = local.lambda_enabled ? 1 : 0

  api_id    = aws_apigatewayv2_api.this[0].id
  route_key = "POST /predict"
  target    = "integrations/${aws_apigatewayv2_integration.lambda[0].id}"
}

# $default with auto_deploy: no manual deployment step, and the stage adds no
# path prefix, so the URL stays https://<id>.execute-api.../predict.
resource "aws_apigatewayv2_stage" "default" {
  count = local.lambda_enabled ? 1 : 0

  api_id      = aws_apigatewayv2_api.this[0].id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.apigw.arn
    format = jsonencode({
      requestId       = "$context.requestId"
      httpMethod      = "$context.httpMethod"
      path            = "$context.path"
      status          = "$context.status"
      responseLatency = "$context.responseLatency"
      integrationErr  = "$context.integrationErrorMessage"
    })
  }
}

resource "aws_cloudwatch_log_group" "apigw" {
  name              = "/aws/apigateway/${local.api_name}"
  retention_in_days = 7
}

# API Gateway is a service principal, not a caller with an IAM role, so it needs
# its own invoke permission. source_arn scopes it to this API rather than any
# gateway in the account.
resource "aws_lambda_permission" "apigw" {
  count = local.lambda_enabled ? 1 : 0

  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api[0].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this[0].execution_arn}/*/*"
}
