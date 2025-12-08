// 데이터 마이그레이션. EFS 데이터 저장용
resource "aws_s3_bucket" "efs2s3" {
  bucket = "lee-345003923266-migration"

  region = var.region

  tags = {
    "IaCTool" = "Terraform"
  }
}
# S3 Bucket 정책.
resource "aws_s3_bucket_policy" "lee-345003923266-migration" {
  bucket = aws_s3_bucket.efs2s3.id
  policy = templatefile("./iam/s3/s3-bucket-policy.tpl.json", { account-id = var.account-id, role = var.role })
}

resource "aws_datasync_location_efs" "datasync-mount-target-src" {
  efs_file_system_arn = aws_efs_file_system.efs4nextcloud.arn

  ec2_config {
    security_group_arns = [module.nextcloud-ng.security_group_arn]
    subnet_arn          = module.vpc.private_subnet_arns[0]
  }
}

## Create Role for DataSync
resource "aws_iam_role" "nextcloud-migration-access" {
  name               = var.role
  assume_role_policy = file("./iam/assumerole-datasync.json")
  tags = {
    "IaCTool" : "Terraform"
  }
}
# Create Policy Document for "nextcloud-migration-access"
resource "aws_iam_policy" "nextcloud-migration-access" {
  name   = "nextcloud-migration-access-policy"
  policy = templatefile("./iam/s3/migration.tpl.json", { bucket-name = "lee-345003923266-migration" })

  description = "This gives an access to the bucket 'lee-345003923266-migration'"
  tags = {
    "IaCTool" : "Terraform"
  }
}
# Attach Policy 'extcloud-migration-access-policy' to the role 'nextcloud-migration-access'
resource "aws_iam_role_policy_attachment" "attach-policy" {
  role       = aws_iam_role.nextcloud-migration-access.name
  policy_arn = aws_iam_policy.nextcloud-migration-access.arn
}
# resource "aws_datasync_location_s3" "datasync-mount-target-dest" {
#   s3_bucket_arn = aws_s3_bucket.efs2s3.arn
#   subdirectory = ""

#   s3_config {
#     bucket_access_role_arn = ""
#   }
# }

