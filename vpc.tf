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

  # Enable VPC Flow Log and Save Flow Logs to S3.
  enable_flow_log                      = true
  create_flow_log_cloudwatch_log_group = true
  create_flow_log_cloudwatch_iam_role  = true
  flow_log_max_aggregation_interval    = 60

  vpc_flow_log_tags = {
    "IaCTool" = "Terraform",
    "Name"    = "NextCloud-Log"
  }

  # Tag. Terraform made this resource.
  tags = {
    IaCTool = "Terraform"
  }
}