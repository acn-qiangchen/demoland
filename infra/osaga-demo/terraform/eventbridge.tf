# S3 "Object Created" on the input bucket → start a Step Functions execution.
# S3 emits these to the default event bus because the input bucket has EventBridge
# notifications enabled (see s3.tf).
resource "aws_cloudwatch_event_rule" "input_created" {
  name        = "${var.app_name}-input-created"
  description = "Trigger the osaga-demo saga when an object is uploaded to the input bucket."

  event_pattern = jsonencode({
    source      = ["aws.s3"]
    detail-type = ["Object Created"]
    detail = {
      bucket = {
        name = [aws_s3_bucket.input.bucket]
      }
    }
  })

  tags = { Name = "${var.app_name}-input-created" }
}

resource "aws_cloudwatch_event_target" "start_saga" {
  rule     = aws_cloudwatch_event_rule.input_created.name
  arn      = aws_sfn_state_machine.this.arn
  role_arn = aws_iam_role.events.arn

  # Reshape the S3 event into the state machine's input contract: { inputBucket, inputKey }.
  input_transformer {
    input_paths = {
      bucket = "$.detail.bucket.name"
      key    = "$.detail.object.key"
    }
    input_template = <<EOF
{"inputBucket": <bucket>, "inputKey": <key>}
EOF
  }
}
