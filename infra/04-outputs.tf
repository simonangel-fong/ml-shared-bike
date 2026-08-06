# outputs.tf

# ##############################
# Sagemaker
# ##############################
output "sagemaker_execution_role_arn" {
  value = aws_iam_role.sagemaker_execution.arn
}

# ##############################
# S3
# ##############################
output "s3_bucket_name" {
  value = aws_s3_bucket.ml.id
}

# ##############################
# GitHub actions
# ##############################
output "github_actions_role_arn" {
  value = aws_iam_role.github_actions.arn
}

# ##############################
# ECR
# ##############################
output "ecr_repository_url" {
  description = "docker build/push target for the prediction API image"
  value       = aws_ecr_repository.api.repository_url
}

# ##############################
# Lambda
# ##############################
output "lambda_function_url" {
  description = "IAM-signed lambda url for direct testing; null until an image is pushed"
  value       = try(aws_lambda_function_url.api[0].function_url, null)
}

# ##############################
# API GTW
# ##############################
output "api_gtw_url" {
  description = "api gateway base url; routes are /stations, /forecast, /predict"
  value       = try(aws_apigatewayv2_api.this[0].api_endpoint, null)
}

# ##############################
# Cloudfront
# ##############################
output "cloudfront_domain" {
  description = "cloudfront distribution domain; the dns target"
  value       = try(aws_cloudfront_distribution.this[0].domain_name, null)
}

output "cloudfront_predict_url" {
  description = "prediction endpoint through cloudfront"
  value       = try("https://${aws_cloudfront_distribution.this[0].domain_name}/predict", null)
}

# ##############################
# DNS
# ##############################
output "dns_site_url" {
  description = "the public site"
  value       = var.domain_name != "" ? "https://${var.domain_name}" : null
}


