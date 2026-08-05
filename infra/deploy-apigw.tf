# deploy-apigw.tf

# ##############################
# API Gateway: HTTP API (v2), a third the cost of REST, native CORS
# ##############################
resource "aws_apigatewayv2_api" "this" {
  count = var.enable_deployment ? 1 : 0

  name          = local.app_name
  protocol_type = "HTTP"
  description   = "Prediction API for the annual demand model"

  cors_configuration {
    allow_origins = ["*"]
    # GET for /stations, POST for /forecast and /predict.
    allow_methods = ["GET", "POST", "OPTIONS"]
    allow_headers = ["content-type"]
    max_age       = 300
  }
}

# integration with lambda
resource "aws_apigatewayv2_integration" "lambda" {
  count = var.enable_deployment ? 1 : 0

  api_id                 = aws_apigatewayv2_api.this[0].id
  integration_type       = "AWS_PROXY" # AWS_PROXY: expects {statusCode, headers, body}
  integration_uri        = aws_lambda_function.api[0].invoke_arn
  payload_format_version = "2.0"

  # Comfortably over the ~3.2s cold start; a warm call is ~18ms.
  timeout_milliseconds = 29000
}

# loop paths
resource "aws_apigatewayv2_route" "routes" {
  for_each = var.enable_deployment ? toset([
    "POST /forecast",
    "POST /predict",
    "GET /stations",
    "POST /api/forecast",
    "POST /api/predict",
    "GET /api/stations",
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

# ##############################
# Log group: api gateway
# ##############################
resource "aws_cloudwatch_log_group" "apigw" {
  name              = "/aws/apigateway/${local.app_name}"
  retention_in_days = 7
}
