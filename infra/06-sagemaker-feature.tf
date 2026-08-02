# sagemaker-feature.tf

# ##############################
# SageMaker: Feature Store
# ##############################
resource "aws_glue_catalog_database" "features" {
  name = "${local.prefix_name}-features"
}

# resource "aws_sagemaker_feature_group" "customer_features" {
#   feature_group_name             = "customer-features"
#   record_identifier_feature_name = "customer_id"
#   event_time_feature_name        = "event_time"
#   role_arn                       = aws_iam_role.sagemaker_execution.arn

#   feature_definition {
#     feature_name = "customer_id"
#     feature_type = "String"
#   }

#   feature_definition {
#     feature_name = "event_time"
#     feature_type = "String"
#   }

#   # Online store for real-time feature serving
#   online_store_config {
#     enable_online_store = true

#     security_config {
#       kms_key_id = data.aws_kms_key.default.arn
#     }
#   }

#   # Offline store for batch training
#   offline_store_config {
#     s3_storage_config {
#       s3_uri                 = "s3://${aws_s3_bucket.ml_data.id}/features/"
#       kms_key_id             = data.aws_kms_key.default.arn
#       resolved_output_s3_uri = "s3://${aws_s3_bucket.ml_data.id}/features/resolved/"
#     }

#     table_format = "Glue"

#     data_catalog_config {
#       catalog    = "AwsDataCatalog"
#       database   = aws_glue_catalog_database.features.name
#       table_name = "customer_features"
#     }
#   }

# }


