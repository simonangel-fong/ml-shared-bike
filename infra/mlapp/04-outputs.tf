# outputs.tf

output "sagemaker_endpoint_name" {
  description = "invoke target for phase 3 api gateway"
  value       = aws_sagemaker_endpoint.demand.name
}

output "sagemaker_endpoint_arn" {
  value = aws_sagemaker_endpoint.demand.arn
}

output "sagemaker_model_name" {
  value = aws_sagemaker_model.demand.name
}

output "sagemaker_serving_role_arn" {
  value = aws_iam_role.sagemaker_serving.arn
}

output "serving_model_data_url" {
  description = "artifact currently behind the endpoint"
  value       = var.model_data_url
}
