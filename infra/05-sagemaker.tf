# sagemaker.tf


# ##############################
# VPC: Default
# ##############################
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }

  tags = {
    Tier   = "Default"
    Subnet = "Private"
  }
}

data "aws_kms_key" "default" {
  key_id = local.aws_kms_alias
}

# ##############################
# IAM: Sagemaker
# ##############################
resource "aws_iam_role" "sagemaker_execution" {
  name = "${local.prefix_name}-sagemaker-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "sagemaker.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "sagemaker_full_access" {
  role       = aws_iam_role.sagemaker_execution.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess"
}


# Security group for the notebook
resource "aws_security_group" "sagemaker" {
  name        = "${local.prefix_name}-sagemaker-notebook"
  description = "Security group for SageMaker notebook instances and Studio apps"
  vpc_id      = data.aws_vpc.default.id

  # # Required for SageMaker Studio apps to mount the domain EFS volume
  # ingress {
  #   from_port = 2049
  #   to_port   = 2049
  #   protocol  = "tcp"
  #   self      = true
  # }

  # # Required for SageMaker Studio apps to mount the domain EFS volume
  # egress {
  #   from_port = 2049
  #   to_port   = 2049
  #   protocol  = "tcp"
  #   self      = true
  # }

  # # Allow outbound HTTPS for AWS API calls and pip installs
  # egress {
  #   from_port   = 443
  #   to_port     = 443
  #   protocol    = "tcp"
  #   cidr_blocks = ["0.0.0.0/0"]
  # }

  # # Allow outbound to S3 VPC endpoint if you have one
  # egress {
  #   from_port       = 443
  #   to_port         = 443
  #   protocol        = "tcp"
  #   prefix_list_ids = [aws_vpc_endpoint.s3.prefix_list_id]
  # }
}


# ##############################
# Sagemaker: domain
# ##############################
resource "aws_sagemaker_domain" "ml" {
  domain_name = local.prefix_name
  vpc_id      = data.aws_vpc.default.id
  subnet_ids  = data.aws_subnets.private.ids
  auth_mode   = "IAM"

  default_user_settings {
    execution_role = aws_iam_role.sagemaker_execution.arn

    # security_groups = [aws_security_group.sagemaker.id]

    # sharing_settings {
    #   notebook_output_option = "Allowed"
    #   s3_output_path         = "s3://${aws_s3_bucket.ml_data.id}/studio-output/"
    # }

    # jupyter_server_app_settings {
    #   default_resource_spec {
    #     instance_type = "system"
    #   }
    # }

    # kernel_gateway_app_settings {
    #   default_resource_spec {
    #     instance_type = "ml.t3.medium"
    #   }
    # }
  }

  # default_space_settings {
  #   execution_role  = aws_iam_role.sagemaker_execution.arn
  #   security_groups = [aws_security_group.sagemaker.id]
  # }
}

# User profiles for team members
resource "aws_sagemaker_user_profile" "data_scientist" {
  for_each = var.data_scientists

  domain_id         = aws_sagemaker_domain.ml.id
  user_profile_name = each.key

  user_settings {
    execution_role = aws_iam_role.sagemaker_execution.arn
  }
}
