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

# Create IAM Role, Policy #
# IAM Role. Only a specific EC2 Instance will assume this.
data "aws_iam_policy_document" "EFS-AllowAll" {
  statement {
    # required
    sid = "AllowEFSAccess"
    # All elasticfilesystem actions.
    actions = ["elasticfilesystem:*"]
    # Allow
    effect = "Allow"

    resources = [aws_efs_mount_target.mount_target.file_system_arn]
  }
}

resource "aws_iam_policy" "nextcloud-policy" {
  name   = "EC2_NextCloudPolicy"
  policy = data.aws_iam_policy_document.EFS-AllowAll.json

}

resource "aws_iam_policy" "certbot" {
  name   = "Certbot-Policy"
  policy = file("./iam/nextcloud-certbot.json")
}

resource "aws_iam_role" "nextcloud-role" {
  name               = "NextCloud_InstanceRole"
  assume_role_policy = file("./iam/assumerolepolicy.json")

  tags = {
    IaCTool = "Terraform"
  }
}

## 2022-07-16##
# Get Amazon CloudWatch Log Group name
data "aws_cloudwatch_log_group" "flow_log_group" {
  name = format("/aws/vpc-flow-log/%s", module.vpc.vpc_id)
}

# Policy Document 
resource "aws_iam_policy" "metricstreams-firehosetos3" {
  name   = "NextCloud-MetricStreams-FirehoseToS3"
  policy = templatefile("./iam/metricstreams-s3.tpl.json", { region = var.region, account-id = var.account-id, s3-bucket-arn = module.store-metric.s3_bucket_arn, log-group = data.aws_cloudwatch_log_group.flow_log_group.name })

  tags = {
    "IaCTool" = "Terraform"
  }
}

# Allow Kinesis Service to assume role
resource "aws_iam_role" "kinesis-role" {
  name               = "NextCloud-Kinesis-AssumeRole"
  assume_role_policy = file("./iam/assumerole-kinesis.json")

  tags = {
    "IaCTool" = "Terraform"
  }
}
# Attach Policy to Role
resource "aws_iam_role_policy_attachment" "kinesis-attach" {
  role       = aws_iam_role.kinesis-role.name
  policy_arn = aws_iam_policy.metricstreams-firehosetos3.arn
}

# Policy. For CloudWatch
resource "aws_iam_policy" "metricstreams-putrecords" {
  name   = "NextCloud-FirehosePutRecord"
  policy = templatefile("./iam/firehose-putrecords.tpl.json", { firehose = aws_kinesis_firehose_delivery_stream.nextcloud-stream.arn })

  tags = {
    "IaCTool" = "Terraform"
  }
}

# Role. For CloudWatch
resource "aws_iam_role" "cloudwatch-role" {
  name               = "NextCloud-CloudWatchRole"
  assume_role_policy = templatefile("./iam/assumerole-cloudwatch.tpl.json", { account-id = var.account-id })

  tags = {
    "IaCTool" = "Terraform"
  }
}

resource "aws_iam_role_policy_attachment" "cloudwatch-attach" {
  role       = aws_iam_role.cloudwatch-role.name
  policy_arn = aws_iam_policy.metricstreams-putrecords.arn
}

############
resource "aws_iam_role_policy_attachment" "attach-first" {
  role       = aws_iam_role.nextcloud-role.name
  policy_arn = aws_iam_policy.nextcloud-policy.arn
}

resource "aws_iam_role_policy_attachment" "attach-second" {
  role       = aws_iam_role.nextcloud-role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# For CloudWatch Agent. Allows to send data to CloudWatch Service
resource "aws_iam_role_policy_attachment" "attach-third" {
  role       = aws_iam_role.nextcloud-role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_role_policy_attachment" "attach-fourth" {
  role       = aws_iam_role.nextcloud-role.name
  policy_arn = aws_iam_policy.certbot.arn
}
# This resource will be used for EC2 Instance.
resource "aws_iam_instance_profile" "nextcloud-instance-profile" {
  name = "NextCloud-Profile"
  role = aws_iam_role.nextcloud-role.name
}


#  Create EFS and EFS mount target  #
# Create EFS
resource "aws_efs_file_system" "efs4nextcloud" {
  creation_token = "efs4nextcloud"
  encrypted      = true

  # Add tags
  tags = {
    Name    = "efs4nextcloud"
    IaCTool = "Terraform"
  }

}

# Mount target in Private Subnet.
resource "aws_efs_mount_target" "mount_target" {
  file_system_id  = aws_efs_file_system.efs4nextcloud.id
  subnet_id       = module.vpc.private_subnets[0]
  security_groups = [module.nextcloud-ng.security_group_id]
}

# EFS File System Policy. Allow EC2 instance to mount file system only if it has'NextCloud_InstanceRole' Role.
resource "aws_efs_file_system_policy" "nextcloud_policy" {
  file_system_id = aws_efs_file_system.efs4nextcloud.id

  policy = templatefile("./iam/efs-policy.tpl.json", { nextcloud-role = aws_iam_role.nextcloud-role.arn, efs-fs-arn = aws_efs_mount_target.mount_target.file_system_arn })

  depends_on = [
    aws_iam_role.nextcloud-role
  ]
}

# System Manager #
# Write System Manager Document
resource "aws_ssm_document" "amazon-efs-utils" {
  name          = "NextCloud-Install-EFSUtils"
  document_type = "Command"

  content = file("./system-manager/document-installpkg.json")

  tags = {
    IaCTool = "Terraform"
  }
}

# Run the document. Install 'amazon-efs-utils' package on ubuntu 18.04 LTS.
resource "aws_ssm_association" "install" {
  name = aws_ssm_document.amazon-efs-utils.name

  targets {
    key    = "InstanceIds"
    values = [aws_instance.nextcloud-instance.id]
  }
}

# Try Mount efs file system '${efs_fs_id}'. Mount Point: /mnt/efs/'${efs_fs_id}'
resource "aws_ssm_document" "try-mount" {
  name          = "Try-Mount"
  document_type = "Command"

  content = templatefile("./system-manager/document-mount-efs.json", { efs_fs_id = aws_efs_file_system.efs4nextcloud.id })

  tags = {
    IaCTool = "Terraform"
  }
}

# Run document. Mount EFS
resource "aws_ssm_association" "mount-efs" {
  name = aws_ssm_document.try-mount.name

  targets {
    key    = "InstanceIds"
    values = [aws_instance.nextcloud-instance.id]
  }

  depends_on = [aws_ssm_association.install, aws_instance.nextcloud-instance]
}


resource "aws_ssm_document" "run-install-agent" {
  name          = "NextCloud-Install-CloudWatchAgent"
  document_type = "Command"

  content = file("./system-manager/document-installagent.json")

  tags = {
    IaCTool = "Terraform"
  }
}

# Run the document. Install CloudWatch Agent software on NextCloud.
resource "aws_ssm_association" "install-agent" {
  name = aws_ssm_document.run-install-agent.name

  targets {
    key    = "InstanceIds"
    values = [aws_instance.nextcloud-instance.id]
  }
}

# Create EC2 Instance #
# Instance Network Setting. Associate AWS Elastic IP to instance.
resource "aws_eip" "eip" {
  vpc = true

  instance   = aws_instance.nextcloud-instance.id
  depends_on = [module.vpc]

  tags = {
    IaCTool = "Terraform"
  }
}

# 이 AMI는 더 이상 지원되지 않음. AWS MarketPlace에서 제거됨.
# data "aws_ami" "nextcloud_ami" {
#   most_recent = true

#   owners = ["679593333241"] # IVCISA

#   filter {
#     name   = "name"
#     values = ["ivcisa-nextcloud-20.0.0-linux-ubuntu*"]
#   }

#   filter {
#     name   = "virtualization-type"
#     values = ["hvm"]
#   }

# }

# Cloud-init user_data. Create folder for EFS mount point.
data "template_cloudinit_config" "config" {
  base64_encode = true

  part {
    content_type = "text/cloud-config"
    content      = templatefile("./cloud-init/user-data/setting.tpl", { efs_fs_id = aws_efs_file_system.efs4nextcloud.id })
  }
}

# Create Instance
resource "aws_instance" "nextcloud-instance" {
  ami           = "ami-07d16c043aa8e5153"
  instance_type = "t3.micro"
  key_name      = "key4test"

  subnet_id              = module.vpc.public_subnets[0]
  vpc_security_group_ids = [module.nextcloud-ng.security_group_id]

  # Instance Profile. EC2에 역할 부여.
  iam_instance_profile = aws_iam_instance_profile.nextcloud-instance-profile.name

  # Enable EC2 Termination Protection
  disable_api_termination = true

  # Create Directory. EFS 마운트에 쓸 디랙토리가 생성됨.
  user_data_base64 = data.template_cloudinit_config.config.rendered

  # Wait Until EFS Mount target is ready
  depends_on = [
    aws_efs_mount_target.mount_target,
  ]

  # Terraform Lifecycle
  lifecycle {
    ignore_changes = [tags, vpc_security_group_ids, ami, user_data_base64]
  }

  tags = {
    Name    = "My NextCloud"
    IaCTool = "Terraform"
  }
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
