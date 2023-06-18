# System Manager #
# Write System Manager Document
resource "aws_ssm_document" "amazon-efs-utils" {
  name          = "NextCloud-Install-EFSUtils"
  document_type = "Command"

  content = file("./system-manager/document-installpkg.json")

  tags = {
    IaCTool = "Terraform"
  }
}

# Run the document. Install 'amazon-efs-utils' package on ubuntu 18.04 LTS.
resource "aws_ssm_association" "install" {
  name = aws_ssm_document.amazon-efs-utils.name

  targets {
    key    = "InstanceIds"
    values = [aws_instance.nextcloud-instance.id]
  }
}

# Try Mount efs file system '${efs_fs_id}'. Mount Point: /mnt/efs/'${efs_fs_id}'
resource "aws_ssm_document" "try-mount" {
  name          = "Try-Mount"
  document_type = "Command"

  content = templatefile("./system-manager/document-mount-efs.json", { efs_fs_id = aws_efs_file_system.efs4nextcloud.id })

  tags = {
    IaCTool = "Terraform"
  }
}

# Run document. Mount EFS
resource "aws_ssm_association" "mount-efs" {
  name = aws_ssm_document.try-mount.name

  targets {
    key    = "InstanceIds"
    values = [aws_instance.nextcloud-instance.id]
  }

  depends_on = [aws_ssm_association.install, aws_instance.nextcloud-instance]
}


resource "aws_ssm_document" "run-install-agent" {
  name          = "NextCloud-Install-CloudWatchAgent"
  document_type = "Command"

  content = file("./system-manager/document-installagent.json")

  tags = {
    IaCTool = "Terraform"
  }
}

# Run the document. Install CloudWatch Agent software on NextCloud.
resource "aws_ssm_association" "install-agent" {
  name = aws_ssm_document.run-install-agent.name

  targets {
    key    = "InstanceIds"
    values = [aws_instance.nextcloud-instance.id]
  }
}

resource "aws_ssm_parameter" "agent-config" {
  # name must starts with "AmazonCloudWatch-"
  name  = "AmazonCloudWatch-NextCloud"
  type  = "String"
  value = file("./system-manager/parameter-store/AmazonCloudWatch-NextCloud.json")

  tags = {
    "IaCTool" = "Terraform"
  }
}

# System Manager#
# Upload 'config.json' file to Parameter Store

# Run Command
resource "aws_ssm_document" "run-agent" {
  name          = "NextCloud-Run-CloudWatchAgent"
  document_type = "Command"

  content = templatefile("./system-manager/document-manageagent.tpl.json", { action = "fetch-config", mode = "ec2", cwaconfig = aws_ssm_parameter.agent-config.name })

  tags = {
    IaCTool = "Terraform"
  }
}

resource "aws_ssm_association" "run-agent" {
  name = aws_ssm_document.run-agent.name

  targets {
    key    = "InstanceIds"
    values = [aws_instance.nextcloud-instance.id]
  }
}