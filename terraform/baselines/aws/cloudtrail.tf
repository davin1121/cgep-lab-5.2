# cloudtrail.tf
# Deploys a multi-region CloudTrail writing to a dedicated S3 bucket.
# Controls satisfied: AU-2 (auditable events), AU-12 (audit record generation),
# AU-10 (non-repudiation via log-file validation).

# The S3 bucket that receives CloudTrail log files.
# force_destroy = true allows terraform destroy to delete it even when
# it contains objects. Leave this false in production.
resource "aws_s3_bucket" "trail" {
  bucket        = "${var.project_name}-cloudtrail-${random_id.suffix.hex}"
  force_destroy = true
}

# SC-28: Encrypt the log bucket at rest with AES-256.
# CloudTrail logs contain API call records that could reveal infrastructure
# details. Encryption ensures they're protected if the bucket is misconfigured.
resource "aws_s3_bucket_server_side_encryption_configuration" "trail" {
  bucket = aws_s3_bucket.trail.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# AC-3: Block all public access vectors on the log bucket.
# CloudTrail logs must never be publicly readable.
resource "aws_s3_bucket_public_access_block" "trail" {
  bucket                  = aws_s3_bucket.trail.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# The bucket policy that allows CloudTrail (an AWS service) to write logs.
# This uses the data source approach: aws_iam_policy_document generates
# valid JSON from HCL, which is safer than writing raw JSON strings.
#
# Two statements are required:
# 1. AWSCloudTrailAclCheck: CloudTrail reads the bucket ACL to verify
#    it has permission to write. Without this, the trail fails to start.
# 2. AWSCloudTrailWrite: CloudTrail writes the actual log files under
#    AWSLogs/<account-id>/...
#
# The aws:SourceArn condition on both statements locks the policy to
# THIS specific trail only. Without it, any CloudTrail in any account
# could write to your bucket if they somehow obtained your bucket name.
# This is a confused deputy attack prevention measure.
data "aws_iam_policy_document" "trail" {
  statement {
    sid     = "AWSCloudTrailAclCheck"
    effect  = "Allow"
    actions = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.trail.arn]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = ["arn:aws:cloudtrail:${var.aws_region}:${data.aws_caller_identity.current.account_id}:trail/cgep-lab-mgmt"]
    }
  }

  statement {
    sid     = "AWSCloudTrailWrite"
    effect  = "Allow"
    actions = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.trail.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = ["arn:aws:cloudtrail:${var.aws_region}:${data.aws_caller_identity.current.account_id}:trail/cgep-lab-mgmt"]
    }
  }
}

# Attach the policy document to the bucket.
resource "aws_s3_bucket_policy" "trail" {
  bucket = aws_s3_bucket.trail.id
  policy = data.aws_iam_policy_document.trail.json

  depends_on = [aws_s3_bucket_public_access_block.trail]
}

# The CloudTrail trail itself.
#
# is_multi_region_trail = true: captures API calls in ALL regions, not just
# us-east-1. Without this, an attacker operating in eu-west-1 would leave
# no trace. FedRAMP and most enterprise baselines require multi-region.
#
# include_global_service_events = true: captures IAM, STS, and Route53 events,
# which are global and not tied to a specific region.
#
# enable_log_file_validation = true: CloudTrail writes a digest file every hour
# containing the SHA-256 hash and digital signature of every log file from that
# hour. An auditor (or your verify script) can detect if a log file was deleted
# or modified after it was written. This is the AU-10 control: non-repudiation.
resource "aws_cloudtrail" "mgmt" {
  name                          = "cgep-lab-mgmt"
  s3_bucket_name                = aws_s3_bucket.trail.id
  is_multi_region_trail         = true
  include_global_service_events = true
  enable_log_file_validation    = true

  depends_on = [aws_s3_bucket_policy.trail]
}
