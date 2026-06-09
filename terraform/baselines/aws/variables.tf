# variables.tf
# Input variables for the security baseline module.
# Keeping region and project name as variables means you can deploy
# the same code to multiple accounts or regions without editing .tf files.

variable "aws_region" {
  type        = string
  description = "AWS region to deploy the baseline into."
  default     = "us-east-1"
}

variable "project_name" {
  type        = string
  description = "Short name used in resource names and default tags."
  default     = "cgep-lab"
}
