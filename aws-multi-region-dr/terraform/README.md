# AWS Multi-Region Disaster Recovery - Terraform

Terraform for the warm-standby DR architecture: primary region **us-east-1**, recovery region **us-west-2**.

## What it creates

| Area | Resources |
|---|---|
| Web tier (both regions) | Security groups, launch template (Amazon Linux 2023 + Apache User Data), ALB, target group (`/health`), Auto Scaling Group. Uses the **default VPC**. |
| Data | DynamoDB table with a Global Tables replica in the recovery region; versioned S3 buckets in both regions with cross-region replication and an IAM replication role |
| Monitoring | Route 53 health check on the primary ALB, CloudWatch alarm on `HealthCheckStatus`, SNS email alert |
| Optional automation | Lambda that scales up the recovery Auto Scaling Group when the alarm fires (`enable_lambda = true`) |
| Optional DNS failover | Route 53 Primary/Secondary failover records (needs a domain you own) |

Primary runs 2 servers, recovery runs 1 (warm standby). Both are changeable in `variables.tf`.

## Prerequisites
- Terraform 1.5 or newer
- AWS CLI configured (`aws configure`) with permissions to create the resources above

## Usage
```bash
cp terraform.tfvars.example terraform.tfvars   # set alert_email
terraform init
terraform validate
terraform plan
terraform apply
```
After apply, open the **confirmation email** from AWS SNS and click Confirm, otherwise no alerts arrive. Allow 3 to 5 minutes for the servers to become healthy, then open `primary_alb_url` and `recovery_alb_url` from the outputs.

## Test failover
Simulate a primary outage:
```bash
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name dr-demo-asg-east \
  --min-size 0 --max-size 0 --desired-capacity 0 --region us-east-1
```
In a few minutes the ALB returns 503, the health check turns Unhealthy, the alarm fires and the email arrives. The recovery URL keeps serving. Restore:
```bash
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name dr-demo-asg-east \
  --min-size 2 --max-size 2 --desired-capacity 2 --region us-east-1
```
If `enable_lambda = true`, the recovery group is scaled to `recovery_failover_capacity` when the alarm fires; scale it back down yourself afterwards.

## Optional: automatic DNS failover
If you own a domain with a Route 53 hosted zone, set `hosted_zone_id` and `record_name` in `terraform.tfvars`. Terraform then creates a Primary record (Virginia ALB, with the health check) and a Secondary record (Oregon ALB). Users must use that name, not the ALB address, for the redirect to work.

## Notes
- The CloudWatch alarm, SNS topic and Lambda are always created in **us-east-1**, because Route 53 health check metrics exist only there.
- The Auto Scaling Groups ignore `desired_capacity` changes, so manual or Lambda scaling is not reverted by `terraform apply`.
- S3 buckets use `force_destroy = true` so `terraform destroy` removes them even when they contain files.
- Cost: the two ALBs and the EC2 instances are the main charges. Destroy when you are done.

## Destroy
```bash
terraform destroy
```

## Structure
```
.
├── versions.tf            providers (primary, recovery, monitoring)
├── variables.tf
├── main.tf                web tiers, DynamoDB, S3 replication, health check, alarm, DNS
├── lambda.tf              optional recovery Lambda
├── outputs.tf
├── terraform.tfvars.example
└── modules/web_tier/      ALB, target group, launch template, Auto Scaling
```
