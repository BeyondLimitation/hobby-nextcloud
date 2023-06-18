## 2022-07-16 ##
# Create S3 Bucket
module "store-metric" {
  source = "terraform-aws-modules/s3-bucket/aws"
  bucket = "lee-bucket4metricstreams"
  acl    = "private"

  lifecycle_rule = [{
    id      = "Log-autodelete"
    enabled = true
    expiration = {
      days                         = 180
      expired_object_delete_marker = true
    }
  }]

  tags = {
    "IaCTool" = "Terraform"
  }
}

# Create Security Group#
# Security group module 
module "nextcloud-ng" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "4.4.0"

  name        = "nextcloud-ng"
  description = "Security group for nextcloud application. Allow ssh, http/https and nfs traffics inbound and outbound"
  vpc_id      = module.vpc.vpc_id

  # 인바운드 규칙
  ingress_cidr_blocks = ["0.0.0.0/0"]
  ingress_rules       = ["https-443-tcp", "http-80-tcp", "ssh-tcp"]
  ingress_with_cidr_blocks = [
    { # Rule 1
      rule        = "nfs-tcp"
      cidr_blocks = module.vpc.private_subnets_cidr_blocks[0]
    },
    { # Rule 2
      rule        = "nfs-tcp"
      cidr_blocks = module.vpc.public_subnets_cidr_blocks[0]
    }
  ]

  # 아웃바운드 규칙
  egress_cidr_blocks = ["0.0.0.0/0"]
  egress_rules       = ["https-443-tcp", "http-80-tcp", "ssh-tcp"]
  egress_with_cidr_blocks = [
    { # Rule 1
      rule        = "nfs-tcp"
      cidr_blocks = module.vpc.private_subnets_cidr_blocks[0]
    }
  ]

  tags = {
    IaCTool = "Terraform"
  }
}

## 2022-07-16##
# Get Amazon CloudWatch Log Group name
data "aws_cloudwatch_log_group" "flow_log_group" {
  name = format("/aws/vpc-flow-log/%s", module.vpc.vpc_id)
}

# Create CloudFormation Stack #
# Crete Stack. This is for snapshotting NextCloud EC2 Instance.
resource "aws_cloudformation_stack" "Nextcloud-ServerBackup" {
  name          = "NextCloudSnapshot"
  template_body = file("./cloudformation/stack-ec2_backup.json")

  tags = {
    IaCTool = "Terraform"
  }
}


# 2022-05-12 #
# Route53

data "aws_route53_zone" "myworld" {
  zone_id = "Z1044780QS7P5JPQT0A8"
  tags = {
    IaCTool = "Terraform"
  }
}

# Add "A Record"
resource "aws_route53_record" "nextcloud" {
  zone_id = data.aws_route53_zone.myworld.zone_id
  name    = "nextcloud.${data.aws_route53_zone.myworld.name}"
  type    = "A"
  ttl     = "300"
  records = ["3.35.95.62"]
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

# System Manager#
# Upload 'config.json' file to Parameter Store

resource "aws_ssm_parameter" "agent-config" {
  # name must starts with "AmazonCloudWatch-"
  name  = "AmazonCloudWatch-NextCloud"
  type  = "String"
  value = file("./system-manager/parameter-store/AmazonCloudWatch-NextCloud.json")

  tags = {
    "IaCTool" = "Terraform"
  }
}

# Run Command
resource "aws_ssm_document" "run-agent" {
  name          = "NextCloud-Run-CloudWatchAgent"
  document_type = "Command"

  content = templatefile("./system-manager/document-manageagent.tpl.json", { action = "fetch-config", mode = "ec2", cwaconfig = aws_ssm_parameter.agent-config.name })

  tags = {
    IaCTool = "Terraform"
  }
}

resource "aws_ssm_association" "run-agent" {
  name = aws_ssm_document.run-agent.name

  targets {
    key    = "InstanceIds"
    values = [aws_instance.nextcloud-instance.id]
  }
}

## 2022-07-17
resource "aws_kinesis_firehose_delivery_stream" "nextcloud-stream" {
  name        = "nextcloud-metricstream"
  destination = "s3"

  s3_configuration {
    role_arn        = aws_iam_role.kinesis-role.arn
    bucket_arn      = module.store-metric.s3_bucket_arn
    buffer_interval = 900
  }

  tags = {
    "IaCTool" = "Terraform"
  }
}
