terraform {
  backend "remote" {
    organization = "Lee-personal-project"
    workspaces {
      name = "hobby-nextcloud"
    }
  }
}

provider "aws" {
  region = var.region
}

### NextCloud Infra ###
# Create VPC, 2 public and 2 private subnets.
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "3.11.0"

  # Note! Internet Gateway automatically created with same name of the VPC. Then it will be attached to this VPC.
  name = "nextcloud-terraform"

  azs             = var.azs
  cidr            = var.vpc_cidr
  public_subnets  = var.public_subnets
  private_subnets = var.private_subnets

  # Enable DNS hostname and DNS resolution. These are required for EFS mount.
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Tag. Terraform made this resource.
  tags = {
    IaCTool = "Terraform"
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

resource "aws_iam_role" "nextcloud-role" {
  name               = "NextCloud_InstanceRole"
  assume_role_policy = file("./iam/assumerolepolicy.json")

  tags = {
    IaCTool = "Terraform"
  }
}

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
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentAdminPolicy"
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

  policy = templatefile("./iam/efs-policy.tpl.json", { nextcloud-role = aws_iam_role.nextcloud-role.arn, efs-fs-arn = aws_efs_mount_target.mount_target.file_system_arn, datasync-role = aws_iam_role.datasync-role.arn })

  depends_on = [
    aws_iam_role.nextcloud-role, aws_iam_role.datasync-role
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

# Get AMI.
data "aws_ami" "nextcloud_ami" {
  most_recent = true

  owners = ["679593333241"] # IVCISA

  filter {
    name   = "name"
    values = ["ivcisa-nextcloud-20.0.0-linux-ubuntu*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

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
  ami           = data.aws_ami.nextcloud_ami.id
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


### NextCloud Data Backup ###
# Create S3 Bucket#
# Create Bucket. Saving logs.
module "s3-log4nextcloud" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "2.10.0"

  bucket = "lee-nextcloud-log"
  acl    = "log-delivery-write"

  tags = {
    IaCTool = "Terraform"
  }
}
# Create Bucket. Save nextcloud data uploaded by user and nextcloud server data.
module "s3-nextcloud" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "2.10.0"

  # Set Bucket name, 'nextcloud-data'
  bucket = "lee-nextcloud-data"
  # Set Policy. Allow DataSync Service to read and write objects in bucket.

  # Save log to this directory of this bucket
  logging = {
    target_bucket = module.s3-log4nextcloud.s3_bucket_id
    target_prefix = "log/"
  }

  # Enable S3 Server Side Encryption(SSE-S3)
  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }

  tags = {
    IaCTool = "Terraform"
  }
}

# Set S3 Bucket Policy.
resource "aws_s3_bucket_policy" "allow-datasync" {
  # S3 Bucket.
  bucket = module.s3-nextcloud.s3_bucket_id

  # Policy. Read './iam/s3-allow-datasybc.tpl.json' for detail.
  policy = templatefile("./iam/s3-allow-datasync.tpl.json", { nextcloud-s3-arn = module.s3-nextcloud.s3_bucket_arn })
}

##Create VPC Endpoint. This makes connection between Backup Server(EC2) and S3 private ##
# Create Security Group for Endpoint
module "endpoint-sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "4.4.0"

  name        = "backup-sg"
  description = "Security group for DataSync Agent. Allow ssh, http traffics inbound and outbound"
  vpc_id      = module.vpc.vpc_id

  # 인바운드 규칙
  ingress_cidr_blocks = [module.vpc.private_subnets_cidr_blocks[0], module.vpc.private_subnets_cidr_blocks[1]]
  ingress_rules       = ["nfs-tcp"]

  # 아웃바운드 규칙
  egress_cidr_blocks = ["0.0.0.0/0"]
  egress_rules       = ["all-all"]

  tags = {
    IaCTool = "Terraform"
  }
}

#Create Endpoint
resource "aws_vpc_endpoint" "nextcloud-backup-endpoint" {
  vpc_id       = module.vpc.vpc_id
  service_name = "com.amazonaws.ap-northeast-2.s3"
  # Interface Endpoint
  vpc_endpoint_type = "Interface"

  security_group_ids = [module.endpoint-sg.security_group_id]
  subnet_ids         = [module.vpc.private_subnets[0], module.vpc.private_subnets[1]]

  tags = {
    Name    = "NextCloud Backup Endpoint"
    IaCTool = "Terraform"
  }
}

## Create Service Role ##

# Create IAM Role for Datasync. This is assumed by DataSync Service.
resource "aws_iam_role" "datasync-role" {
  name               = "DataSyncRole"
  assume_role_policy = file("./iam/assumerole-datasync.json")

  tags = {
    IaCTool = "Terraform"
  }
}

# Create Policy for the role, 'DataSyncRole'.
resource "aws_iam_policy" "datasync-policy" {
  name        = "EFS-AllowDataSync"
  description = "This allow DataSync Service to read-only access to specific file system only"

  policy = templatefile("./iam/efs-allow-datasync.tpl.json", { efs-fs-arn = aws_efs_mount_target.mount_target.file_system_arn, nextcloud-data = module.s3-nextcloud.s3_bucket_arn, datasync-role = aws_iam_role.datasync-role.arn })
  tags = {
    IaCTool = "Terraform"
  }
}

# Attach policy docs to the role.
resource "aws_iam_role_policy_attachment" "attach-datasync" {
  role       = aws_iam_role.datasync-role.name
  policy_arn = aws_iam_policy.datasync-policy.arn
}

## DataSync ##
# This returns the ARN.
data "aws_security_group" "nextcloudsg-arn" {
  id = module.nextcloud-ng.security_group_id
}
# Create DataSync location. source.
resource "aws_datasync_location_efs" "efs4nextcloud_loc" {
  efs_file_system_arn = aws_efs_file_system.efs4nextcloud.arn
  ec2_config {
    security_group_arns = [data.aws_security_group.nextcloudsg-arn.arn]
    subnet_arn          = module.vpc.private_subnet_arns[0]
  }

  tags = {
    IaCTool = "Terraform"
  }
}

# Create DataSync location. destination
resource "aws_datasync_location_s3" "s3-nextcloud" {
  s3_bucket_arn = module.s3-nextcloud.s3_bucket_arn
  subdirectory  = "/mirror"

  s3_config {
    bucket_access_role_arn = aws_iam_role.datasync-role.arn
  }

  tags = {
    IaCTool = "Terraform"
  }
}

resource "aws_datasync_task" "migrate" {
  source_location_arn      = aws_datasync_location_efs.efs4nextcloud_loc.arn
  destination_location_arn = aws_datasync_location_s3.s3-nextcloud.arn
  name                     = "Migration"

  schedule {
    schedule_expression = "cron(0 0 */15 * ? * )"
  }

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
  dashboard_body = templatefile("./cloudwatch/dashboard-nextcloud.tpl.json", { aws-region = var.region, fs-id = aws_efs_file_system.efs4nextcloud.id })
}

# Add CloudWatch Log Group, "NextCloud-Log"
resource "aws_cloudwatch_log_group" "nextcloud-log-group" {
  name = "NextCloud_Infra"

  tags = {
    "IaCTool" = "Terraform"
  }
}

# Add Log Stream, "EC2"
resource "aws_cloudwatch_log_stream" "ec2" {
  name           = "nextcloud_ec2"
  log_group_name = aws_cloudwatch_log_group.nextcloud-log-group.name
}