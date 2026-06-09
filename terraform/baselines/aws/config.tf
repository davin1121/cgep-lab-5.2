# config.tf
# Deploys AWS Config: a continuous configuration recorder that snapshots
# every resource and evaluates compliance rules.
# Controls satisfied: CM-2 (baseline config), CM-6 (config settings), CM-8 (inventory)
#
# WARNING: Many org-managed AWS accounts block this with a Service Control Policy (SCP):
#   "Effect": "Deny", "Action": "config:*"
# If terraform apply returns AccessDeniedException with "explicit deny in a service
# control policy", comment out this entire file. The Security Hub finding
# "AWS Config should be enabled" becomes your evidence that the gap exists.

# S3 bucket for Config to deliver configuration snapshots and history.
resource "aws_s3_bucket" "config" {
  bucket        = "${var.project_name}-config-${random_id.suffix.hex}"
  force_destroy = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "config" {
  bucket = aws_s3_bucket.config.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "config" {
  bucket                  = aws_s3_bucket.config.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# IAM role that Config assumes to read your resources and write to S3.
# Config needs to describe, list, and get every resource type in your account.
# The AWSConfigRole managed policy grants exactly those permissions.
resource "aws_iam_role" "config" {
  name = "${var.project_name}-config-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "config.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "config" {
  role       = aws_iam_role.config.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}

# Allow Config to write snapshots and history to the S3 bucket.
resource "aws_iam_role_policy" "config_s3" {
  name = "config-s3-delivery"
  role = aws_iam_role.config.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:PutObject", "s3:GetBucketAcl"]
      Resource = [
        aws_s3_bucket.config.arn,
        "${aws_s3_bucket.config.arn}/*"
      ]
    }]
  })
}

# The configuration recorder tells Config what to record.
# recording_group with all_supported = true records every supported resource
# type. include_global_resource_types = true adds IAM users, roles, and
# policies to the inventory (the CM-8 requirement).
resource "aws_config_configuration_recorder" "this" {
  name     = "${var.project_name}-recorder"
  role_arn = aws_iam_role.config.arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }
}

# The delivery channel tells Config where to send snapshots and how often.
# s3_bucket_name is required. Without a delivery channel the recorder
# starts but never writes anything anywhere.
resource "aws_config_delivery_channel" "this" {
  name           = "${var.project_name}-delivery"
  s3_bucket_name = aws_s3_bucket.config.id
  depends_on     = [aws_config_configuration_recorder.this]
}

# Start the recorder. Terraform creates the recorder and channel above
# but the recorder is paused by default. This resource turns it on.
resource "aws_config_configuration_recorder_status" "this" {
  name       = aws_config_configuration_recorder.this.name
  is_enabled = true
  depends_on = [aws_config_delivery_channel.this]
}
