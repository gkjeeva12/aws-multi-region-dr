terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

# Primary region (default provider)
provider "aws" {
  region = var.primary_region
}

# Recovery region
provider "aws" {
  alias  = "recovery"
  region = var.recovery_region
}

# Route 53 health check metrics are published only in us-east-1,
# so the alarm, SNS topic and Lambda live there.
provider "aws" {
  alias  = "monitoring"
  region = "us-east-1"
}
