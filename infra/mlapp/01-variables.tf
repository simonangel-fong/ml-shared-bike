# variables.tf

variable "env" {
  default = "ml"
}

variable "project" {
  default = "toronto-shared-bike"
}

# ##############################
# Phase 2: model / endpoint
# ##############################

# Owned by infra/mlops. Referenced by name, not by remote state, so the two
# stacks stay independently appliable.
variable "ml_bucket_name" {
  description = "existing ml bucket holding the training artifacts"
  type        = string
  default     = "toronto-shared-bike-ml-ud3m7h"
}

# Retraining means pointing this at the new job's output/model.tar.gz and
# applying - Terraform then rolls a new model + endpoint config in place.
variable "model_data_url" {
  description = "s3 uri of the trained model.tar.gz to serve"
  type        = string
  default     = "s3://toronto-shared-bike-ml-ud3m7h/trains/annual-demand-q80-2026-08-04-22-00-42-965/output/model.tar.gz"

  validation {
    condition     = endswith(var.model_data_url, "/output/model.tar.gz")
    error_message = "must be a training job's output/model.tar.gz, not the sourcedir tarball."
  }
}

variable "endpoint_memory_mb" {
  description = "serverless endpoint memory; must fit sklearn + pandas + the pipeline"
  type        = number
  default     = 3072
}

variable "endpoint_max_concurrency" {
  description = "serverless endpoint max concurrent invocations"
  type        = number
  default     = 5
}
