output "vpc_id" {
  description = "생성된 VPC의 ID"
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  description = "VPC의 CIDR"
  value       = module.vpc.vpc_cidr_block
}

output "public_subnets" {
  description = "Public subnet 들의 ID 목록"
  value       = module.vpc.public_subnets_cidr_blocks
}

output "private_subnets" {
  description = "Private subnet 들의 ID 목록"
  value       = module.vpc.private_subnets_cidr_blocks
}

output "EFS_MountTarget_FQDN" {
  description = "EFS File System의 FQDN. 마운트를 위해 필요함"
  value       = aws_efs_mount_target.mount_target.dns_name
}

output "VPC_Interface_Endpoint_ID" {
  description = "NextCloud Backup 서버에서 사용할 VPC Interface Endpoint ID"
  value       = aws_vpc_endpoint.nextcloud-backup-endpoint.id
}

output "my_ami" {
  description = "내가 구독한 IVCISA의 Nextcloud AMI."
  value       = data.aws_ami.nextcloud_ami.id
}

output "nextcloud-data-bucket" {
  description = "Nextcloud의 데이터 백업용 Bucket의 ID"
  value       = module.s3-nextcloud.s3_bucket_id
}

output "nextcloud-log-bucket" {
  description = "Nextcloud 데이터 백업용 Bucket Log를 저장하는 Bucket ID"
  value       = module.s3-log4nextcloud.s3_bucket_id
}