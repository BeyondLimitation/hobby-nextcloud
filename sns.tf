# Create SNS Topic
resource "aws_sns_topic" "nextcloud-notrunning" {
  name   = "NextCloud-NotRunning"

  tags = {
    "IaCTool" = "Terraform"
  }
}

resource "aws_sns_topic_policy" "proper-one" {
  arn = aws_sns_topic.nextcloud-notrunning.arn
  policy = templatefile("./iam/sns/allow_events.tpl.json", { nextcloud-notrunning = aws_sns_topic.nextcloud-notrunning.arn })
}

# Create SNS Topic Subscription. Send to the E-mail specified
resource "aws_sns_topic_subscription" "email-alert" {
  topic_arn = aws_sns_topic.nextcloud-notrunning.arn
  protocol  = "email"
  endpoint  = var.email
}