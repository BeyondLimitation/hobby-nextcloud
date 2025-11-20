## 2022-07-17
resource "aws_kinesis_firehose_delivery_stream" "nextcloud-stream" {
  name        = "nextcloud-metricstream"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn           = aws_iam_role.kinesis-role.arn
    bucket_arn         = module.store-metric.s3_bucket_arn
    buffering_interval = 900
  }

  tags = {
    "IaCTool" = "Terraform"
  }
}
