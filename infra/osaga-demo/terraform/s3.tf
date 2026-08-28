# Random suffix keeps the two bucket names globally unique per deploy.
resource "random_id" "suffix" {
  byte_length = 4
}

# ---- Input bucket: uploads here trigger the pipeline ----
resource "aws_s3_bucket" "input" {
  bucket        = "${var.app_name}-input-${random_id.suffix.hex}"
  force_destroy = true # demo: allow terraform destroy to remove a non-empty bucket

  tags = { Name = "${var.app_name}-input" }
}

# Emit S3 events to the default EventBridge bus so the "Object Created" rule can fire.
resource "aws_s3_bucket_notification" "input" {
  bucket      = aws_s3_bucket.input.id
  eventbridge = true
}

# ---- Output bucket: transformed CSVs land here (under processed/) ----
resource "aws_s3_bucket" "output" {
  bucket        = "${var.app_name}-output-${random_id.suffix.hex}"
  force_destroy = true

  tags = { Name = "${var.app_name}-output" }
}
