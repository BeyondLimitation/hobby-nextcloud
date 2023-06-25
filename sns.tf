# Create SNS Topic
resource "aws_sns_topic" "user_updates" {
  name = "NextCloud-NotRunning"
}

