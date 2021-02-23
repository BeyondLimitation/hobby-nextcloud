terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = " ~> 3.5"
    }
  }
}

resource "aws_vpc" "vpc-nextcloud" {
  cidr_block       = "10.10.0.0/16"
  instance_tenancy = "default"

  enable_dns_support   = true
  enable_dns_hostnames = true

}

resource "aws_subnet" "public-1" {
  vpc_id                  = aws_vpc.vpc-nextcloud.id
  cidr_block              = "10.10.0.0/18"
  map_public_ip_on_launch = true
}

resource "aws_subnet" "public-2" {
  vpc_id                  = aws_vpc.vpc-nextcloud.id
  cidr_block              = "10.10.64.0/18"
  map_public_ip_on_launch = true
}

resource "aws_subnet" "private-1" {
  vpc_id     = aws_vpc.vpc-nextcloud.id
  cidr_block = "10.10.128.0/18"
}

resource "aws_subnet" "private-2" {
  vpc_id     = aws_vpc.vpc-nextcloud.id
  cidr_block = "10.10.192.0/18"
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

  owners = ["099720109477"] # Canonical
}

resource "aws_instance" "simple1" {
  ami           = data.aws_ami.ubuntu-bionic.id
  instance_type = "t3.micro"

  subnet_id = aws_subnet.public-1.id
}
