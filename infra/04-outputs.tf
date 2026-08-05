# outputs.tf

output "sagemaker_execution_role_arn" {
  value = aws_iam_role.sagemaker_execution.arn
}

output "ml_bucket_name" {
  value = aws_s3_bucket.ml.id
}

output "github_actions_role_arn" {
  value = aws_iam_role.github_actions.arn
}

output "api_ecr_repository_url" {
  description = "docker build/push target for the prediction API image"
  value       = aws_ecr_repository.api.repository_url
}

output "api_function_url" {
  description = "IAM-signed lambda url for direct testing; null until an image is pushed"
  value       = try(aws_lambda_function_url.api[0].function_url, null)
}

output "api_predict_url" {
  description = "public prediction endpoint via api gateway"
  value       = try("${aws_apigatewayv2_api.this[0].api_endpoint}/predict", null)
}
