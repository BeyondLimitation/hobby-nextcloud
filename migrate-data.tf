resource "aws_s3_bucket" "efs2s3" {
  bucket = "lee-migration"

  region = var.region

  tags = {
    "IaCTool" = "Terraform"
  }
}