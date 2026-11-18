output "primary_alb_url" {
  description = "Primary (Virginia) load balancer URL"
  value       = "http://${module.primary_web.alb_dns_name}"
}

output "recovery_alb_url" {
  description = "Recovery (Oregon) load balancer URL"
  value       = "http://${module.recovery_web.alb_dns_name}"
}

output "primary_asg_name" {
  value = module.primary_web.asg_name
}

output "recovery_asg_name" {
  value = module.recovery_web.asg_name
}

output "dynamodb_table" {
  value = aws_dynamodb_table.app.name
}

output "primary_bucket" {
  value = aws_s3_bucket.primary.bucket
}

output "replica_bucket" {
  value = aws_s3_bucket.replica.bucket
}

output "health_check_id" {
  value = aws_route53_health_check.primary.id
}

output "alarm_name" {
  value = aws_cloudwatch_metric_alarm.primary_down.alarm_name
}

output "failover_dns_name" {
  description = "Failover record name (empty if no domain was configured)"
  value       = local.create_dns ? var.record_name : ""
}
