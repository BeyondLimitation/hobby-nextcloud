provider "aws" {
  region = "ap-northeast-2"
}

locals {
  user_data = <<EOF
#!/bin/bash
sudo apt install -y nfs-common
echo "nfs-common is installed!" > $HOME/yes.txt
EOF
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
}

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
}

#  Create EFS and EFS mount target  #

resource "aws_efs_file_system" "efs4nextcloud" {
  creation_token = "efs4nextcloud"
  encrypted      = true
}

resource "aws_efs_mount_target" "mount_target" {
  file_system_id = aws_efs_file_system.efs4nextcloud.id
  subnet_id      = module.vpc.private_subnets[0]
  security_groups = [module.nextcloud-ng.this_security_group_id]
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

resource "aws_instance" "simple1" {
  ami           = data.aws_ami.ubuntu-bionic.id
  instance_type = "t3.micro"
  key_name      = "key4test"

  subnet_id       = module.vpc.public_subnets[0]
  security_groups = [module.nextcloud-ng.this_security_group_id]
  
  # Package setting
  user_data_base64 = base64encode(local.user_data)
  tags = {
    Name = "시험용."
  }
}
