# AWS Security Services Baseline: CloudTrail + Security Hub + Config

## What This Is

This lab deploys the AWS-native compliance backbone using Terraform. It stands up a multi-region CloudTrail trail with log-file validation, enables Security Hub subscribed to NIST 800-53 Rev 5 and AWS Foundational Security Best Practices, and deploys AWS Config for continuous resource configuration recording. The result is a continuously running detection layer that produces audit evidence without any manual effort after the initial deployment.

## Why This Matters

Labs 4.3 and 4.4 built a preventive control: the GRC pipeline blocks non-compliant infrastructure before it reaches AWS. This lab builds the detective control layer that runs after deployment and continuously evaluates what is actually running in the account against the same NIST 800-53 controls.

In a FedRAMP or SOC 2 audit, the assessor asks two separate questions. First, how do you prevent non-compliant changes from being deployed? Second, how do you know your environment is compliant right now? The GRC pipeline answers the first. This baseline answers the second. You need both.

The `evidence/lab-5-2/security-hub-findings.json` file captured at the end of this lab is a 525 KB JSON artifact containing Security Hub's evaluation of every NIST 800-53 control it could assess against the account. That file, signed and locked in the vault from Lab 2.5, is what you hand to an assessor for continuous monitoring evidence.

## Controls Satisfied

| Service | Controls | How |
|---|---|---|
| CloudTrail | AU-2, AU-12, AU-10 | Records every API call in all regions. Log-file validation (SHA-256 digest every hour, signed by AWS) detects tampering after the fact. |
| Security Hub + NIST 800-53 | RA-5, SI-4 | Continuously evaluates ~300 NIST controls against account resources and surfaces findings with control IDs and remediation guidance. |
| AWS Config | CM-2, CM-6, CM-8 | Snapshots every resource configuration change and maintains a full history of what every resource looked like at any point in time. |

## Architecture

```
CloudTrail (multi-region, log-file validation)
     |
     v
S3 bucket (cgep-lab-cloudtrail-*)
     AU-2 / AU-12 / AU-10

AWS Config recorder --> S3 bucket (cgep-lab-config-*)
     CM-2 / CM-6 / CM-8

Security Hub (NIST 800-53 Rev 5 + FSBP)
     <-- findings from Config, native checks
     RA-5 / SI-4
```

## Key Design Decisions

**Multi-region trail.** `is_multi_region_trail = true` captures API calls in every AWS region, not just us-east-1. Without this, an attacker or misconfiguration in eu-west-1 leaves no audit record. FedRAMP requires multi-region coverage.

**Log-file validation.** `enable_log_file_validation = true` makes CloudTrail write a digest file every hour containing the SHA-256 hash of every log file from that hour, signed by an AWS-managed key. This satisfies AU-10 (non-repudiation): an auditor can prove a specific log file existed and has not been modified since it was written.

**`aws:SourceArn` condition on the bucket policy.** Both statements in the CloudTrail bucket policy include an `aws:SourceArn` condition scoped to the exact trail ARN. Without this, any CloudTrail trail in any AWS account could write logs to this bucket if they obtained the bucket name. This is a confused deputy attack prevention that most online CloudTrail examples omit.

**`enable_default_standards = false` on Security Hub.** When importing an existing Security Hub account into Terraform, the provider defaults to `enable_default_standards = true`, which forces a resource replacement and cascades into recreating all standards subscriptions. Setting this explicitly to `false` matches the imported state and eliminates the replace cycle.

**Config is optional.** Many org-managed AWS accounts have a Service Control Policy (SCP) that denies `config:*` in member accounts because Config is centrally managed at the org level. The Terraform code for Config is included but commented-out instructions are provided for accounts where it is SCP-blocked. In this lab, Config deployed successfully.

## Verification Results

```
CloudTrail:
  IsLogging: true
  LatestDeliveryTime: 2026-06-08T19:59:42.902000-07:00

Security Hub:
  HubArn: arn:aws:securityhub:us-east-1:743281284782:hub/default
  Standards: NIST 800-53 v5.0.0 (READY), FSBP v1.0.0 (READY)

Evidence artifact:
  evidence/lab-5-2/security-hub-findings.json (525 KB, 50 findings)
```

## How to Reproduce

**Prerequisites:** AWS account with admin rights, Terraform >= 1.6, AWS CLI configured.

**1. Clone and init:**
```bash
git clone https://github.com/davin1121/cgep-lab-5.2.git
cd cgep-lab-5.2/terraform/baselines/aws
terraform init
```

**2. Apply:**
```bash
terraform apply -auto-approve
```

If Security Hub is already enabled, import it first:
```bash
terraform import aws_securityhub_account.this <ACCOUNT_ID>
terraform apply -auto-approve
```

If standards subscriptions time out (they take 5-15 minutes to activate):
```bash
terraform untaint aws_securityhub_standards_subscription.nist_800_53
terraform untaint aws_securityhub_standards_subscription.fsbp
# wait for: aws securityhub get-enabled-standards to show READY
terraform apply -auto-approve
```

**3. Wait 15-30 minutes**, then capture findings:
```bash
mkdir -p evidence/lab-5-2
aws securityhub get-findings --region us-east-1 --max-results 50 \
  > evidence/lab-5-2/security-hub-findings.json
```

**4. Verify:**
```bash
aws cloudtrail get-trail-status --name cgep-lab-mgmt --region us-east-1 \
  --query "{IsLogging:IsLogging,LatestDeliveryTime:LatestDeliveryTime}"

aws securityhub describe-hub --region us-east-1 --query HubArn
```

**Cleanup:**
```bash
aws securityhub get-findings --region us-east-1 --max-results 50 \
  > evidence/lab-5-2/security-hub-findings.json
terraform state rm aws_securityhub_account.this
terraform destroy -auto-approve
```
