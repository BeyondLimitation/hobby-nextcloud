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

