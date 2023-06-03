
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