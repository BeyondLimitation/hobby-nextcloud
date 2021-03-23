provider "aws" {
  region = "ap-northeast-2"
}

# Create VPC #

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "2.75.0"

  # Note! Internet Gateway automatically created with name of VPC. Then it will be attached to this VPC.
  name = "nextcloud-terraform"

  azs             = ["ap-northeast-2a", "ap-northeast-2b"]
  cidr            = "10.10.0.0/16"
  public_subnets  = ["10.10.0.0/18", "10.10.64.0/18"]
  private_subnets = ["10.10.128.0/18", "10.10.192.0/18"]

  # Enable DNS hostname and DNS resolution. These are required for EFS mount.
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    IacTool = "Terraform"
  }
}

# Create Security Group#

# Security group module 
module "nextcloud-ng" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "3.18.0"

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
    IacTool = "Terraform"
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
  assume_role_policy = file("./assumerolepolicy.json")

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

# This resource will be used for EC2 Instance.
resource "aws_iam_instance_profile" "nextcloud-instance-profile" {
  name = "NextCloud-Profile"
  role = aws_iam_role.nextcloud-role.name
}


#  Create EFS and EFS mount target  #

resource "aws_efs_file_system" "efs4nextcloud" {
  creation_token = "efs4nextcloud"
  encrypted      = true

  tags = {
    Name = "efs4nextcloud"
  }
}

resource "aws_efs_mount_target" "mount_target" {
  file_system_id  = aws_efs_file_system.efs4nextcloud.id
  subnet_id       = module.vpc.private_subnets[0]
  security_groups = [module.nextcloud-ng.this_security_group_id]
}

resource "aws_efs_file_system_policy" "nextcloud_policy" {
  file_system_id = aws_efs_file_system.efs4nextcloud.id

  policy = templatefile("./efs-policy.json.tpl", { nextcloud-role = aws_iam_role.nextcloud-role.arn, efs-fs-arn = aws_efs_mount_target.mount_target.file_system_arn })
  depends_on = [
    aws_iam_role.nextcloud-role
  ]
}

# System Manager #

resource "aws_ssm_document" "amazon-efs-utils" {
  name          = "NextCloud-Install-EFSUtils"
  document_type = "Package"

  content = file("./document-installpkg.json")
}

resource "aws_ssm_association" "install" {
  name = aws_ssm_document.amazon-efs-utils.name

  targets {
    key = "InstanceIds"
    values = [aws_instance.simple1.id]
  }
}

# Create EC2 Instance #
# Ubuntu Bionic. Ubuntu 18.04 LTS AMI
data "aws_ami" "ubuntu-bionic" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-bionic-18.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"]
}

# Cloud-init user_data
data "template_cloudinit_config" "config" {
  base64_encode = true

  part {
    content_type = "text/cloud-config"
    content      = templatefile("./setting.tpl", { efs_mt_fqdn = aws_efs_mount_target.mount_target.dns_name })
  }
}

resource "aws_instance" "simple1" {
  ami           = data.aws_ami.ubuntu-bionic.id
  instance_type = "t3.micro"
  key_name      = "key4test"

  subnet_id       = module.vpc.public_subnets[0]
  security_groups = [module.nextcloud-ng.this_security_group_id]
  # Instance Profile. EC2에 역할 부여.
  iam_instance_profile = aws_iam_instance_profile.nextcloud-instance-profile.name

  # Package setting
  user_data_base64 = data.template_cloudinit_config.config.rendered
  tags = {
    Name    = "시험용."
    IaCTool = "Terraform"
  }
  # Wait Until EFS Mount target is ready
  depends_on = [
    aws_efs_mount_target.mount_target,
  ]
}
