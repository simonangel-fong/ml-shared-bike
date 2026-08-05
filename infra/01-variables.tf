# variables.tf

# ##############################
# Metadata
# ##############################
variable "env" {
  default = "ml"
}

variable "project" {
  default = "toronto-shared-bike"
}

# ##############################
# Sagemaker Deployment
# ##############################
variable "model_artifact_uri" {
  description = "S3 URI of the model.tar.gz to serve. Empty disables the endpoint."
  type        = string
  default     = ""
}

variable "inference_image" {
  description = "ECR URI of the serving container."
  type        = string
  default     = "341280168497.dkr.ecr.ca-central-1.amazonaws.com/sagemaker-scikit-learn:1.2-1-cpu-py3"
}
