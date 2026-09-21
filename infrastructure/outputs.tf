output "aurora_cluster_endpoint" {
  description = "Aurora cluster writer endpoint"
  value       = aws_rds_cluster.healthcare.endpoint
}

output "aurora_reader_endpoint" {
  value = aws_rds_cluster.healthcare.reader_endpoint
}

output "healthcare_data_bucket" {
  value = aws_s3_bucket.healthcare_data.bucket
}

output "access_logs_bucket" {
  value = aws_s3_bucket.access_logs.bucket
}

output "config_bucket" {
  value = aws_s3_bucket.config_bucket.bucket
}

output "kms_data_key_arn" {
  value = aws_kms_key.data_key.arn
}

output "cloudtrail_arn" {
  value = aws_cloudtrail.main.arn
}

output "db_secret_arn" {
  description = "Secrets Manager ARN holding the Aurora master credentials"
  value       = aws_secretsmanager_secret.db_master.arn
}

output "clinician_role_arn" {
  value = aws_iam_role.clinician_role.arn
}

output "analyst_role_arn" {
  value = aws_iam_role.analyst_role.arn
}

output "admin_role_arn" {
  value = aws_iam_role.admin_role.arn
}

output "app_instance_profile_name" {
  value = aws_iam_instance_profile.app_instance_profile.name
}

output "app_security_group_id" {
  value = aws_security_group.app_sg.id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}
