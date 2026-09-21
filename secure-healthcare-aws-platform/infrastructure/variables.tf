variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project/name prefix used for tagging and resource naming"
  type        = string
  default     = "secure-healthcare-platform"
}

variable "environment" {
  description = "Deployment environment (dev/test/prod)"
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.20.0.0/16"
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (Aurora lives here, no public access)"
  type        = list(string)
  default     = ["10.20.1.0/24", "10.20.2.0/24"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (bastion/dashboard access only)"
  type        = list(string)
  default     = ["10.20.101.0/24", "10.20.102.0/24"]
}

variable "db_master_username" {
  description = "Master username for the Aurora cluster"
  type        = string
  default     = "hc_admin"
}

variable "db_name" {
  description = "Default database name"
  type        = string
  default     = "healthcaredb"
}

variable "allowed_dashboard_cidr" {
  description = "CIDR allowed to reach the dashboard / bastion (lock this down to your IP)"
  type        = string
  default     = "0.0.0.0/0" # CHANGE THIS before applying in a real account
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days for CloudTrail/Config logs"
  type        = number
  default     = 365
}

variable "tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default = {
    Project     = "secure-healthcare-platform"
    Compliance  = "HIPAA-aligned"
    ManagedBy   = "terraform"
  }
}
