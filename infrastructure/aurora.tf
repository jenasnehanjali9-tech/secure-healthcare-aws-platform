resource "random_password" "db_master_password" {
  length      = 24
  special     = true
  min_upper   = 2
  min_lower   = 2
  min_numeric = 2
  # Aurora/RDS master passwords cannot contain / @ " or space
  override_special = "!#$%^&*()-_=+"
}

# Store the generated master password in Secrets Manager instead of state/output,
# so credentials are never printed or checked into version control.
resource "aws_secretsmanager_secret" "db_master" {
  name       = "${var.project_name}/aurora/master-credentials"
  kms_key_id = aws_kms_key.data_key.key_id

  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "db_master" {
  secret_id = aws_secretsmanager_secret.db_master.id
  secret_string = jsonencode({
    username = var.db_master_username
    password = random_password.db_master_password.result
    engine   = "aurora-postgresql"
    dbname   = var.db_name
  })
}

resource "aws_rds_cluster_parameter_group" "aurora" {
  name        = "${var.project_name}-aurora-pg"
  family      = "aurora-postgresql15"
  description = "Force SSL and log all connections for the healthcare Aurora cluster"

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  parameter {
    name  = "log_connections"
    value = "1"
  }

  tags = var.tags
}

resource "aws_rds_cluster" "healthcare" {
  cluster_identifier     = "${var.project_name}-aurora"
  engine                 = "aurora-postgresql"
  engine_version         = "15.4"
  database_name          = var.db_name
  master_username        = var.db_master_username
  master_password        = random_password.db_master_password.result
  db_subnet_group_name   = aws_db_subnet_group.aurora.name
  vpc_security_group_ids = [aws_security_group.aurora_sg.id]

  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.aurora.name

  storage_encrypted = true
  kms_key_id         = aws_kms_key.data_key.arn

  backup_retention_period      = 14
  preferred_backup_window      = "03:00-04:00"
  preferred_maintenance_window = "sun:04:30-sun:05:30"

  deletion_protection      = true
  skip_final_snapshot      = false
  final_snapshot_identifier = "${var.project_name}-aurora-final-snapshot"

  enabled_cloudwatch_logs_exports = ["postgresql"]

  copy_tags_to_snapshot = true

  tags = merge(var.tags, { Name = "${var.project_name}-aurora" })
}

resource "aws_rds_cluster_instance" "healthcare_writer" {
  identifier         = "${var.project_name}-aurora-instance-1"
  cluster_identifier = aws_rds_cluster.healthcare.id
  instance_class     = "db.t3.medium" # smallest Aurora-supported class; fine for a class project
  engine             = aws_rds_cluster.healthcare.engine
  engine_version     = aws_rds_cluster.healthcare.engine_version

  publicly_accessible          = false
  performance_insights_enabled = true
  performance_insights_kms_key_id = aws_kms_key.data_key.arn

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "aurora_postgresql" {
  name              = "/aws/rds/cluster/${var.project_name}-aurora/postgresql"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.data_key.arn

  tags = var.tags
}
