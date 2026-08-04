```sh
terraform -chdir=infra init -backend-config=backend.hcl
terraform -chdir=infra fmt && terraform -chdir=infra validate

terraform -chdir=infra plan
terraform -chdir=infra apply -auto-approve

terraform -chdir=infra output sagemaker_execution_role_arn
terraform -chdir=infra output ml_bucket_name

terraform -chdir=infra destroy -auto-approve
```
