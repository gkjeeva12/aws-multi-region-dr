locals {
  create_dns = var.hosted_zone_id != "" && var.record_name != ""
}

# ------------------------------------------------------------------
# Web tier (ALB + target group + launch template + Auto Scaling)
# ------------------------------------------------------------------
module "primary_web" {
  source = "./modules/web_tier"

  project       = var.project
  name          = "east"
  instance_type = var.instance_type
  min_size      = var.primary_desired_capacity
  max_size      = var.primary_desired_capacity
  desired       = var.primary_desired_capacity
}

module "recovery_web" {
  source = "./modules/web_tier"

  providers = {
    aws = aws.recovery
  }

  project       = var.project
  name          = "west"
  instance_type = var.instance_type
  min_size      = var.recovery_desired_capacity
  max_size      = var.recovery_max_size
  desired       = var.recovery_desired_capacity
}

# ------------------------------------------------------------------
# DynamoDB Global Table (primary table with a replica in the recovery region)
# ------------------------------------------------------------------
resource "aws_dynamodb_table" "app" {
  name         = "${var.project}-table"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  replica {
    region_name = var.recovery_region
  }
}

# ------------------------------------------------------------------
# S3 buckets with Cross-Region Replication
# ------------------------------------------------------------------
resource "random_id" "suffix" {
  byte_length = 3
}

resource "aws_s3_bucket" "primary" {
  bucket        = "${var.project}-primary-${random_id.suffix.hex}"
  force_destroy = true
}

resource "aws_s3_bucket" "replica" {
  provider      = aws.recovery
  bucket        = "${var.project}-replica-${random_id.suffix.hex}"
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "primary" {
  bucket = aws_s3_bucket.primary.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "replica" {
  provider = aws.recovery
  bucket   = aws_s3_bucket.replica.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "primary" {
  bucket                  = aws_s3_bucket.primary.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "replica" {
  provider                = aws.recovery
  bucket                  = aws_s3_bucket.replica.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_iam_policy_document" "s3_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "replication" {
  name               = "${var.project}-s3-replication"
  assume_role_policy = data.aws_iam_policy_document.s3_assume.json
}

data "aws_iam_policy_document" "replication" {
  statement {
    actions   = ["s3:GetReplicationConfiguration", "s3:ListBucket"]
    resources = [aws_s3_bucket.primary.arn]
  }
  statement {
    actions = [
      "s3:GetObjectVersionForReplication",
      "s3:GetObjectVersionAcl",
      "s3:GetObjectVersionTagging",
    ]
    resources = ["${aws_s3_bucket.primary.arn}/*"]
  }
  statement {
    actions   = ["s3:ReplicateObject", "s3:ReplicateDelete", "s3:ReplicateTags"]
    resources = ["${aws_s3_bucket.replica.arn}/*"]
  }
}

resource "aws_iam_role_policy" "replication" {
  name   = "${var.project}-s3-replication"
  role   = aws_iam_role.replication.id
  policy = data.aws_iam_policy_document.replication.json
}

resource "aws_s3_bucket_replication_configuration" "primary_to_replica" {
  depends_on = [
    aws_s3_bucket_versioning.primary,
    aws_s3_bucket_versioning.replica,
  ]

  bucket = aws_s3_bucket.primary.id
  role   = aws_iam_role.replication.arn

  rule {
    id     = "replicate-to-recovery"
    status = "Enabled"

    filter {}

    delete_marker_replication {
      status = "Enabled"
    }

    destination {
      bucket        = aws_s3_bucket.replica.arn
      storage_class = "STANDARD"
    }
  }
}

# ------------------------------------------------------------------
# Route 53 health check on the primary ALB
# ------------------------------------------------------------------
resource "aws_route53_health_check" "primary" {
  fqdn              = module.primary_web.alb_dns_name
  port              = 80
  type              = "HTTP"
  resource_path     = "/health"
  request_interval  = 30
  failure_threshold = 3

  tags = {
    Name = "${var.project}-east-health"
  }
}

# ------------------------------------------------------------------
# Optional: Route 53 DNS failover records (needs a domain you own)
# ------------------------------------------------------------------
resource "aws_route53_record" "primary" {
  count = local.create_dns ? 1 : 0

  zone_id         = var.hosted_zone_id
  name            = var.record_name
  type            = "A"
  set_identifier  = "primary"
  health_check_id = aws_route53_health_check.primary.id

  failover_routing_policy {
    type = "PRIMARY"
  }

  alias {
    name                   = module.primary_web.alb_dns_name
    zone_id                = module.primary_web.alb_zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "secondary" {
  count = local.create_dns ? 1 : 0

  zone_id         = var.hosted_zone_id
  name            = var.record_name
  type            = "A"
  set_identifier = "secondary"

  failover_routing_policy {
    type = "SECONDARY"
  }

  alias {
    name                   = module.recovery_web.alb_dns_name
    zone_id                = module.recovery_web.alb_zone_id
    evaluate_target_health = true
  }
}

# ------------------------------------------------------------------
# CloudWatch alarm + SNS email alert (us-east-1)
# ------------------------------------------------------------------
resource "aws_sns_topic" "alerts" {
  provider = aws.monitoring
  name     = "${var.project}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  provider  = aws.monitoring
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_metric_alarm" "primary_down" {
  provider = aws.monitoring

  alarm_name          = "${var.project}-east-down"
  alarm_description   = "Route 53 health check for the primary region is unhealthy"
  namespace           = "AWS/Route53"
  metric_name         = "HealthCheckStatus"
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "LessThanThreshold"

  dimensions = {
    HealthCheckId = aws_route53_health_check.primary.id
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
}
