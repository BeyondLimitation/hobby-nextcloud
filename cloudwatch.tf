## 2022-07-16##
# Get Amazon CloudWatch Log Group name
data "aws_cloudwatch_log_group" "flow_log_group" {
  name = format("/aws/vpc-flow-log/%s", module.vpc.vpc_id)
}

# 2022-06-20 #
## CloudWatch ##
# Add a "NextCloud" Dashboard
resource "aws_cloudwatch_dashboard" "nextcloud-board" {
  dashboard_name = "NextCloud"
  dashboard_body = templatefile("./cloudwatch/dashboard-nextcloud.tpl.json", { aws-region = var.region, fs-id = aws_efs_file_system.efs4nextcloud.id, instance-id = aws_instance.nextcloud-instance.id, instance-ami = "ami-07d16c043aa8e5153", instance-type = aws_instance.nextcloud-instance.instance_type, log-group = data.aws_cloudwatch_log_group.flow_log_group.name })
}

## 2022-07-20
# Create CloudWatch Metric Stream
resource "aws_cloudwatch_metric_stream" "metric-stream" {
  name          = "NextCloud-Metric-Stream"
  role_arn      = aws_iam_role.cloudwatch-role.arn
  firehose_arn  = aws_kinesis_firehose_delivery_stream.nextcloud-stream.arn
  output_format = "json"

  include_filter {
    namespace = "CWAgent"
  }
  include_filter {
    namespace = "AWS/EFS"
  }
}