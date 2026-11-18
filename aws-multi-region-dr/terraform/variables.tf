variable "project" {
  description = "Name prefix for all resources"
  type        = string
  default     = "dr-demo"
}

variable "primary_region" {
  description = "Primary region"
  type        = string
  default     = "us-east-1"
}

variable "recovery_region" {
  description = "Recovery (standby) region"
  type        = string
  default     = "us-west-2"
}

variable "instance_type" {
  description = "EC2 instance type for the web servers"
  type        = string
  default     = "t3.micro"
}

variable "primary_desired_capacity" {
  description = "Number of web servers in the primary region"
  type        = number
  default     = 2
}

variable "recovery_desired_capacity" {
  description = "Number of standby web servers in the recovery region (warm standby)"
  type        = number
  default     = 1
}

variable "recovery_max_size" {
  description = "Maximum size of the recovery Auto Scaling Group"
  type        = number
  default     = 4
}

variable "recovery_failover_capacity" {
  description = "Capacity the optional Lambda scales the recovery group to when the alarm fires"
  type        = number
  default     = 2
}

variable "alert_email" {
  description = "Email address that receives the CloudWatch alarm notifications (you must confirm the subscription email)"
  type        = string
}

variable "enable_lambda" {
  description = "Create the optional Lambda that scales up the recovery region when the alarm fires"
  type        = bool
  default     = false
}

variable "hosted_zone_id" {
  description = "OPTIONAL. Route 53 hosted zone ID of a domain you own. Set together with record_name to create DNS failover records."
  type        = string
  default     = ""
}

variable "record_name" {
  description = "OPTIONAL. Full record name for failover, e.g. app.example.com"
  type        = string
  default     = ""
}
