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
# Lambda deployment
# ##############################
variable "lambda_image_tag" {
  description = "Tag of the API image in the project ECR repo. Empty until one is pushed, which leaves the function uncreated."
  type        = string
  default     = ""
}
