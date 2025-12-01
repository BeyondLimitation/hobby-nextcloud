resource "aws_s3_bucket" "efs2s3" {
  bucket = "lee-345003923266-migration"

  region = var.region

  tags = {
    "IaCTool" = "Terraform"
  }
}

resource "aws_datasync_location_efs" "datasync-mount-target" {
  efs_file_system_arn = aws_efs_file_system.efs4nextcloud.arn

  ec2_config {
    security_group_arns = [module.nextcloud-ng.security_group_arn]
    subnet_arn          = module.vpc.private_subnet_arns[0]
  }
}