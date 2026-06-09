# outputs.tf
# Outputs surface key values after terraform apply completes.
# Use these in the verification steps to confirm the right resources
# were created and to copy ARNs into documentation.

output "cloudtrail_arn" {
  description = "ARN of the multi-region management trail (AU-2/AU-12/AU-10)."
  value       = aws_cloudtrail.mgmt.arn
}

output "cloudtrail_bucket" {
  description = "S3 bucket receiving CloudTrail log files."
  value       = aws_s3_bucket.trail.id
}

output "security_hub_arn" {
  description = "ARN of the Security Hub hub resource (RA-5/SI-4)."
  value       = aws_securityhub_account.this.id
}
