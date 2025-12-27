## 2022-07-16 ##
# Create S3 Bucket
module "store-metric" {
  source = "terraform-aws-modules/s3-bucket/aws"
  bucket = "lee-bucket4metricstreams"
  acl    = "private"

  lifecycle_rule = [{
    id      = "Log-autodelete"
    enabled = true
    expiration = {
      expired_object_delete_marker = true
    }
  }]

  force_destroy = true
  tags = {
    "IaCTool" = "Terraform"
  }
}