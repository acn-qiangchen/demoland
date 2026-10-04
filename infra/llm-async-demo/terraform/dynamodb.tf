# DynamoDB job store. One item per job, keyed by jobId, with a ttl attribute (epoch seconds) so
# demo jobs expire automatically.
resource "aws_dynamodb_table" "jobs" {
  name         = "${var.app_name}-jobs"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "jobId"

  attribute {
    name = "jobId"
    type = "S"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  tags = { Name = "${var.app_name}-jobs" }
}
