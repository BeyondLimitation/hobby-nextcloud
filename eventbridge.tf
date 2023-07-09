resource "aws_cloudwatch_event_rule" "nextcloud-notrunning" {
  name        = "NextCloud-NotRunning"
  description = "The instance is not running. Send current status via email"

  # Load Event Pattern JSON file.
  event_pattern = templatefile("eventbridge/nextcloud-notrunning.tmp.json", { nextcloud-instance = aws_instance.nextcloud-instance.id })

  tags = {
    "IaCTool" = "Terraform"
  }
}

# Add Event Rule target
resource "aws_cloudwatch_event_target" "email-alert" {
  rule = aws_cloudwatch_event_rule.nextcloud-notrunning.name
  arn  = aws_sns_topic.nextcloud-notrunning.arn

  input_transformer {
    input_paths = {
      instance-id = "$.detail.instance-id",
      state       = "$.detail.state"
    }
    input_template = "\"Instance <instance-id> is in <state>\""
  }
}