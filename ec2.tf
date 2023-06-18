# Create EC2 Instance #
# Instance Network Setting. Associate AWS Elastic IP to instance.
resource "aws_eip" "eip" {
  vpc = true

  instance   = aws_instance.nextcloud-instance.id
  depends_on = [module.vpc]

  tags = {
    IaCTool = "Terraform"
  }
}

# Cloud-init user_data. Create folder for EFS mount point.
data "template_cloudinit_config" "config" {
  base64_encode = true

  part {
    content_type = "text/cloud-config"
    content      = templatefile("./cloud-init/user-data/setting.tpl", { efs_fs_id = aws_efs_file_system.efs4nextcloud.id })
  }
}

# Launch Instance
resource "aws_instance" "nextcloud-instance" {
  ami           = "ami-07d16c043aa8e5153"
  instance_type = "t3.micro"
  key_name      = "key4test"

  subnet_id              = module.vpc.public_subnets[0]
  vpc_security_group_ids = [module.nextcloud-ng.security_group_id]

  # Instance Profile. EC2에 역할 부여.
  iam_instance_profile = aws_iam_instance_profile.nextcloud-instance-profile.name

  # Enable EC2 Termination Protection
  disable_api_termination = true

  # Create Directory. EFS 마운트에 쓸 디랙토리가 생성됨.
  user_data_base64 = data.template_cloudinit_config.config.rendered

  # Wait Until EFS Mount target is ready
  depends_on = [
    aws_efs_mount_target.mount_target,
  ]

  # Terraform Lifecycle
  lifecycle {
    ignore_changes = [tags, vpc_security_group_ids, ami, user_data_base64]
  }

  tags = {
    Name    = "My NextCloud"
    IaCTool = "Terraform"
  }
}