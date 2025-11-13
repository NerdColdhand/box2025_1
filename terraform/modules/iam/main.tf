variable "project_name" {
  type = string
}

variable "users" {
  type = map(object({
    name        = string
    policy_type = string
  }))
}

variable "s3_bucket_arn" {
  type = string
}

variable "rds_instance_arn" {
  type = string
}

variable "redis_arn" {
  type = string
}

variable "secrets_arn" {
  type = string
}

variable "tags" {
  type = map(string)
}

# Create IAM users
resource "aws_iam_user" "users" {
  for_each = var.users
  
  name = each.value.name
  
  tags = merge(var.tags, {
    Name        = each.value.name
    PolicyType  = each.value.policy_type
  })
}

resource "aws_iam_access_key" "users" {
  for_each = aws_iam_user.users
  
  user = each.value.name
}

# Policy attachments based on user type
locals {
  # Determine which policy to attach to each user
  user_policies = {
    for k, v in var.users : k => v.policy_type == "admin" ? aws_iam_policy.admin.arn : (
      v.policy_type == "readonly" ? aws_iam_policy.readonly.arn : (
        v.policy_type == "infrastructure" ? aws_iam_policy.infrastructure.arn : (
          v.policy_type == "secrets" ? aws_iam_policy.secrets.arn : ""
        )
      )
    )
  }
}

resource "aws_iam_user_policy_attachment" "users" {
  for_each = aws_iam_user.users
  
  user       = each.value.name
  policy_arn = local.user_policies[each.key]
}

# 1. Admin Policy - Full access (overly permissive)
resource "aws_iam_policy" "admin" {
  name        = "${var.project_name}-admin-policy"
  description = "Administrator access to all resources"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "*"  
        Resource = "*"
      }
    ]
  })
  
  tags = var.tags
}

# 2. Read-Only Policy - Read access to all resources
resource "aws_iam_policy" "readonly" {
  name        = "${var.project_name}-readonly-policy"
  description = "Read-only access to all project resources"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket",
          "s3:GetBucketLocation",
          "s3:GetBucketVersioning"
        ]
        Resource = [
          var.s3_bucket_arn,
          "${var.s3_bucket_arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "rds:Describe*",
          "rds:ListTagsForResource"
        ]
        Resource = var.rds_instance_arn
      },
      {
        Effect = "Allow"
        Action = [
          "elasticache:Describe*",
          "elasticache:ListTagsForResource"
        ]
        Resource = var.redis_arn
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:Describe*",
          "ec2:GetConsole*"
        ]
        Resource = "*"  
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:DescribeSecret",
          "secretsmanager:ListSecrets"
        ]
        Resource = var.secrets_arn
      }
    ]
  })
  
  tags = var.tags
}

# 3. Infrastructure Policy - Modify S3, EC2, RDS, Redis
resource "aws_iam_policy" "infrastructure" {
  name        = "${var.project_name}-infrastructure-policy"
  description = "Modify access to infrastructure resources"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:*"  
        ]
        Resource = [
          var.s3_bucket_arn,
          "${var.s3_bucket_arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:*"  
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "rds:ModifyDBInstance",
          "rds:RebootDBInstance",
          "rds:StartDBInstance",
          "rds:StopDBInstance",
          "rds:Describe*",
          "rds:CreateDBSnapshot",
          "rds:DeleteDBSnapshot",
          "rds:RestoreDBInstanceFromDBSnapshot"
        ]
        Resource = var.rds_instance_arn
      },
      {
        Effect = "Allow"
        Action = [
          "elasticache:ModifyCacheCluster",
          "elasticache:RebootCacheCluster",
          "elasticache:Describe*",
          "elasticache:CreateSnapshot",
          "elasticache:DeleteSnapshot"
        ]
        Resource = var.redis_arn
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",  # Can read secrets but not modify
          "secretsmanager:DescribeSecret"
        ]
        Resource = var.secrets_arn
      }
    ]
  })
  
  tags = var.tags
}

# 4. Secrets Manager Policy - Modify only Secrets Manager
resource "aws_iam_policy" "secrets" {
  name        = "${var.project_name}-secrets-policy"
  description = "Full access to Secrets Manager"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:*"  
        ]
        Resource = var.secrets_arn
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:ListSecrets"
        ]
        Resource = "*"  # List operation requires wildcard
      },
      # Should have KMS permissions for encrypted secrets
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = "*" 
      },
      # Read-only access to other resources to understand context
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "rds:Describe*",
          "elasticache:Describe*",
          "ec2:Describe*"
        ]
        Resource = "*"
      }
    ]
  })
  
  tags = var.tags
}

output "user_names" {
  value = [for user in aws_iam_user.users : user.name]
}

output "user_arns" {
  value = { for k, user in aws_iam_user.users : k => user.arn }
}

output "access_keys" {
  value = {
    for k, key in aws_iam_access_key.users : k => {
      id     = key.id
      secret = key.secret
    }
  }
  sensitive = true
}
