# deploy-apigw.tf

# HTTP API (v2) rather than REST: a third the cost, native CORS, and none of the
# v1 features are wanted for a single POST route.

locals {
  api_name = "${local.prefix_name}-api-gw"
}

resource "aws_apigatewayv2_api" "this" {
  count = var.enable_deployment ? 1 : 0

  name          = local.api_name
  protocol_type = "HTTP"
  description   = "Prediction API for the annual demand model"

  # The front end is a different origin, so the browser preflights. Without
  # this the call fails in the browser while working fine from curl.
  cors_configuration {
    allow_origins = ["*"]
    # GET for /stations, POST for /forecast and /predict.
    allow_methods = ["GET", "POST", "OPTIONS"]
    allow_headers = ["content-type"]
    max_age       = 300
  }
}

# AWS_PROXY expects {statusCode, headers, body}, which handler.py returns - so
# there are no mapping templates.
resource "aws_apigatewayv2_integration" "lambda" {
  count = var.enable_deployment ? 1 : 0

  api_id                 = aws_apigatewayv2_api.this[0].id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.api[0].invoke_arn
  payload_format_version = "2.0"

  # Comfortably over the ~3.2s cold start; a warm call is ~18ms.
  timeout_milliseconds = 29000
}

# /forecast takes {station_id, date, hour} and derives the rest; /predict takes
# all 17 features. Same integration - the handler routes on rawPath.
resource "aws_apigatewayv2_route" "routes" {
  for_each = var.enable_deployment ? toset([
    "POST /forecast",
    "POST /predict",
    "GET /stations",
  ]) : toset([])

  api_id    = aws_apigatewayv2_api.this[0].id
  route_key = each.value
  target    = "integrations/${aws_apigatewayv2_integration.lambda[0].id}"
}

# $default with auto_deploy: no deployment step, and no stage prefix in the path.
resource "aws_apigatewayv2_stage" "default" {
  count = var.enable_deployment ? 1 : 0

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

# A service principal needs its own invoke permission; source_arn scopes it to
# this api rather than any gateway in the account.
resource "aws_lambda_permission" "apigw" {
  count = var.enable_deployment ? 1 : 0

  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api[0].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this[0].execution_arn}/*/*"
}
