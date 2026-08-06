# Toronto Shared Bike MLOps Project - IaC with Terraform

[Back](../README.md)

- [Toronto Shared Bike MLOps Project - IaC with Terraform](#toronto-shared-bike-mlops-project---iac-with-terraform)
  - [IaC with Terraform](#iac-with-terraform)

---

## IaC with Terraform

```sh
# init with remote backend
terraform -chdir=infra init -backend-config=backend.hcl
terraform -chdir=infra fmt && terraform -chdir=infra validate

terraform -chdir=infra plan
terraform -chdir=infra apply -auto-approve

terraform -chdir=infra output sagemaker_execution_role_arn
terraform -chdir=infra output s3_bucket_name

terraform -chdir=infra destroy -auto-approve
```
