# security_hub.tf
# Enables Security Hub and subscribes to two standards:
# - NIST 800-53 Rev 5: maps findings to the controls auditors ask about
# - AWS Foundational Security Best Practices (FSBP): AWS-native best practices
# Controls satisfied: RA-5 (vulnerability scanning), SI-4 (system monitoring)

# aws_securityhub_account enables Security Hub in the current account/region.
# This is the prerequisite for everything else in this file.
# If Security Hub is already enabled (from a previous experiment or org
# automation), terraform apply will return ResourceConflictException.
# Fix: terraform import aws_securityhub_account.this <ACCOUNT_ID>
resource "aws_securityhub_account" "this" {
  enable_default_standards = false
}

# Subscribe to NIST 800-53 Rev 5.
# This is the standard that maps directly to FedRAMP, FISMA, and most
# enterprise compliance programs. Each finding in Security Hub that comes
# from this standard includes the specific control ID (e.g., SC-28, AU-2).
# That makes it trivial to pull a list of failing controls and put them
# directly into a Plan of Action and Milestones (POA&M).
resource "aws_securityhub_standards_subscription" "nist_800_53" {
  standards_arn = "arn:aws:securityhub:${var.aws_region}::standards/nist-800-53/v/5.0.0"
  depends_on    = [aws_securityhub_account.this]
}

# Subscribe to AWS Foundational Security Best Practices (FSBP).
# This standard covers AWS-specific configurations that NIST doesn't spell
# out explicitly, like S3 Block Public Access, IMDSv2 on EC2, and root
# account MFA. In practice both standards fire on the same resources but
# from different angles. Running both gives broader coverage.
resource "aws_securityhub_standards_subscription" "fsbp" {
  standards_arn = "arn:aws:securityhub:${var.aws_region}::standards/aws-foundational-security-best-practices/v/1.0.0"
  depends_on    = [aws_securityhub_account.this]
}
