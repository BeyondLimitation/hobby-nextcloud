# Create SNS Topic
resource "aws_sns_topic" "nextcloud-notrunning" {
  name = "NextCloud-NotRunning"
}

# Create SNS Topic Subscription. Send to the E-mail specified
resource "aws_sns_topic_subscription" "email-alert" {
  topic_arn = aws_sns_topic.nextcloud-notrunning.arn
  protocol  = "email"
  endpoint  = var.email
}