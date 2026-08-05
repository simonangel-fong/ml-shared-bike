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
