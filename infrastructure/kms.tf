# One CMK for data-at-rest (Aurora + S3) and one for CloudTrail log encryption,
# separated so a compromise of the app-data key can't be used to tamper with audit logs.

data "aws_caller_identity" "current" {}

resource "aws_kms_key" "data_key" {
  description             = "CMK for healthcare data at rest (Aurora, S3)"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnableRootAccountFullAccess"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid    = "AllowServiceUse"
        Effect = "Allow"
        Principal = {
          Service = ["rds.amazonaws.com", "s3.amazonaws.com"]
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(var.tags, { Name = "${var.project_name}-data-key" })
}

resource "aws_kms_alias" "data_key_alias" {
  name          = "alias/${var.project_name}-data-key"
  target_key_id = aws_kms_key.data_key.key_id
}

resource "aws_kms_key" "cloudtrail_key" {
  description             = "CMK for CloudTrail log file encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnableRootAccountFullAccess"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid    = "AllowCloudTrailEncrypt"
        Effect = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action = [
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
        Condition = {
          StringLike = {
            "kms:EncryptionContext:aws:cloudtrail:arn" = "arn:aws:cloudtrail:*:${data.aws_caller_identity.current.account_id}:trail/*"
          }
        }
      },
      {
        Sid    = "AllowCloudTrailDecrypt"
        Effect = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action   = "kms:Decrypt"
        Resource = "*"
        Condition = {
          "Null" = { "kms:EncryptionContext:aws:cloudtrail:arn" = "false" }
        }
      }
    ]
  })

  tags = merge(var.tags, { Name = "${var.project_name}-cloudtrail-key" })
}

resource "aws_kms_alias" "cloudtrail_key_alias" {
  name          = "alias/${var.project_name}-cloudtrail-key"
  target_key_id = aws_kms_key.cloudtrail_key.key_id
}
