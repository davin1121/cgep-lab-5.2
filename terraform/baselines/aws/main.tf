# main.tf
# Root configuration for the Lab 5.2 AWS security services baseline.
# Declares the providers, generates a random bucket suffix, and pulls
# the caller identity so other files can reference the account ID.

terraform {
  required_version = ">= 1.6"
  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 5.0" }
    random = { source = "hashicorp/random", version = "~> 3.6" }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project         = var.project_name
      Environment     = "security-baseline"
      ManagedBy       = "terraform"
      ComplianceScope = "cgep-lab"
    }
  }
}

# random_id generates a short hex string appended to bucket names.
# S3 bucket names are globally unique across all AWS accounts.
# Without a suffix, "cgep-lab-cloudtrail" would collide with anyone
# else running this lab.
resource "random_id" "suffix" {
  byte_length = 4
}

# data sources pull live information from AWS without creating anything.
# aws_caller_identity gives us the account ID, which is required inside
# the CloudTrail bucket policy's ARN conditions.
data "aws_caller_identity" "current" {}
