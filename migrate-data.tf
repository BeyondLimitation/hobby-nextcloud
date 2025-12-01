resource "aws_s3_bucket" "efs2s3" {
  bucket = "lee-345003923266-migration"

  region = var.region

  tags = {
    "IaCTool" = "Terraform"
  }
}