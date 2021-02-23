provider "aws" {
  region = "ap-northeast-2"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "2.75.0"

  name = "nextcloud-terraform"

  azs             = ["ap-northeast-2a", "ap-northeast-2b"]
  cidr            = "10.10.0.0/16"
  public_subnets  = ["10.10.0.0/18", "10.10.64.0/18"]
  private_subnets = ["10.10.128.0/18", "10.10.192.0/18"]

  enable_dns_hostnames = true
  enable_dns_support   = true
}

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

  subnet_id = module.vpc.public_subnets[0]
}
