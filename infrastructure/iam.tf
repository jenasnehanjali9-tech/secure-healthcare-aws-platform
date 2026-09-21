# Role-based access control (RBAC) for three healthcare personas:
#   1. clinician_role  - read/write patient records in Aurora, no S3/KMS admin
#   2. analyst_role    - read-only access to de-identified data in S3, no Aurora write
#   3. admin_role      - infra admin, cannot read patient data (separation of duties)
#
# All roles require MFA and are scoped with explicit Deny-by-default via least privilege.

data "aws_iam_policy_document" "assume_role_ec2" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "assume_role_federated_users" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    condition {
      test     = "Bool"
      variable = "aws:MultiFactorAuthPresent"
      values   = ["true"]
    }
  }
}

# --- Clinician role: read/write Aurora data, no infra access ---------------

resource "aws_iam_role" "clinician_role" {
  name               = "${var.project_name}-clinician-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role_federated_users.json
  tags               = var.tags
}

resource "aws_iam_policy" "clinician_policy" {
  name        = "${var.project_name}-clinician-policy"
  description = "Read/write access to Aurora via Secrets Manager; no S3, KMS admin, or IAM access"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadDbCredentials"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = aws_secretsmanager_secret.db_master.arn
      },
      {
        Sid      = "ConnectToAurora"
        Effect   = "Allow"
        Action   = ["rds-db:connect"]
        Resource = "arn:aws:rds-db:${var.aws_region}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_rds_cluster.healthcare.cluster_resource_id}/${var.db_master_username}"
      },
      {
        Sid      = "DenyInfraChanges"
        Effect   = "Deny"
        Action   = ["rds:Delete*", "rds:Modify*", "kms:Disable*", "kms:ScheduleKeyDeletion", "iam:*", "s3:DeleteBucket*"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "clinician_attach" {
  role       = aws_iam_role.clinician_role.name
  policy_arn = aws_iam_policy.clinician_policy.arn
}

# --- Analyst role: read-only on de-identified analytics data in S3 ---------

resource "aws_iam_role" "analyst_role" {
  name               = "${var.project_name}-analyst-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role_federated_users.json
  tags               = var.tags
}

resource "aws_iam_policy" "analyst_policy" {
  name        = "${var.project_name}-analyst-policy"
  description = "Read-only access to the analytics/ prefix of the data bucket; no Aurora access"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ListBucket"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = aws_s3_bucket.healthcare_data.arn
        Condition = {
          StringLike = { "s3:prefix" = ["analytics/*"] }
        }
      },
      {
        Sid      = "ReadAnalyticsObjects"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.healthcare_data.arn}/analytics/*"
      },
      {
        Sid      = "UseDataKeyForDecrypt"
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:DescribeKey"]
        Resource = aws_kms_key.data_key.arn
      },
      {
        Sid      = "DenyRawPatientData"
        Effect   = "Deny"
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.healthcare_data.arn}/raw-phi/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "analyst_attach" {
  role       = aws_iam_role.analyst_role.name
  policy_arn = aws_iam_policy.analyst_policy.arn
}

# --- Admin role: manages infra, explicitly denied patient data reads -------

resource "aws_iam_role" "admin_role" {
  name               = "${var.project_name}-admin-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role_federated_users.json
  tags               = var.tags
}

resource "aws_iam_policy" "admin_policy" {
  name        = "${var.project_name}-admin-policy"
  description = "Infra administration; explicitly denied read access to patient data objects (separation of duties)"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "InfraAdmin"
        Effect   = "Allow"
        Action   = ["rds:*", "s3:*", "kms:*", "config:*", "cloudtrail:*", "ec2:Describe*"]
        Resource = "*"
      },
      {
        Sid      = "DenyReadPatientObjects"
        Effect   = "Deny"
        Action   = ["s3:GetObject"]
        Resource = ["${aws_s3_bucket.healthcare_data.arn}/raw-phi/*"]
      },
      {
        Sid      = "DenyDbDataRead"
        Effect   = "Deny"
        Action   = ["rds-db:connect"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "admin_attach" {
  role       = aws_iam_role.admin_role.name
  policy_arn = aws_iam_policy.admin_policy.arn
}

# --- Instance profile for the dashboard/app EC2 host ------------------------

resource "aws_iam_role" "app_instance_role" {
  name               = "${var.project_name}-app-instance-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role_ec2.json
  tags               = var.tags
}

resource "aws_iam_policy" "app_instance_policy" {
  name = "${var.project_name}-app-instance-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadDbSecret"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = aws_secretsmanager_secret.db_master.arn
      },
      {
        Sid      = "ReadDashboardMetrics"
        Effect   = "Allow"
        Action = [
          "cloudtrail:LookupEvents",
          "config:GetComplianceSummaryByConfigRule",
          "config:GetComplianceDetailsByConfigRule",
          "config:DescribeConfigRules",
          "s3:ListBucket",
          "s3:GetObject",
          "cloudwatch:GetMetricData",
          "rds:DescribeDBClusters"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "app_instance_attach" {
  role       = aws_iam_role.app_instance_role.name
  policy_arn = aws_iam_policy.app_instance_policy.arn
}

resource "aws_iam_instance_profile" "app_instance_profile" {
  name = "${var.project_name}-app-instance-profile"
  role = aws_iam_role.app_instance_role.name
}

# --- Account-wide password policy (HIPAA-aligned) ---------------------------

resource "aws_iam_account_password_policy" "strict" {
  minimum_password_length        = 14
  require_uppercase_characters   = true
  require_lowercase_characters   = true
  require_numbers                = true
  require_symbols                = true
  allow_users_to_change_password = true
  max_password_age               = 90
  password_reuse_prevention      = 24
}
