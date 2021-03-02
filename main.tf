provider "aws" {
  region = "ap-northeast-2"
}

# Create VPC
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

resource "aws_security_group" "allow-ssh" {
  name = "Allow_SSH"
  description = "Allow SSH inbound traffic"
  vpc_id = module.vpc.vpc_id

  ingress {
    description = "Allow SSH traffic from everywhere"
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "allow-http" {
  name = "Allow_HTTP"
  description = "Allow HTTP inbound traffic"
  vpc_id = module.vpc.vpc_id

  ingress {
    description = "Allow HTTP traffic from everywhere"
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
resource "aws_security_group" "allow-https" {
  name = "Allow_HTTPS"
  description = "Allow HTTPS inbound traffic"
  vpc_id = module.vpc.vpc_id

  ingress {
    description = "Allow HTTPS traffic from everywhere"
    from_port = 443
    to_port = 443
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 443
    to_port = 443
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
resource "aws_security_group" "allow-nfs" {
  name = "Allow_NFS"
  description = "Allow NFS inbound traffic"
  vpc_id = module.vpc.vpc_id

  ingress {
    description = "Allow NFS traffic from everywhere"
    from_port = 2049
    to_port = 2049
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 2049
    to_port = 2049
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

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

  subnet_id              = module.vpc.public_subnets[0]
  security_groups = [aws_security_group.allow-ssh.id, aws_security_group.allow-http.id, aws_security_group.allow-https.id, aws_security_group.allow-nfs.id]
}
