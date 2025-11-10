terraform {
  required_version = ">= 1.5"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }  
}

provider "aws" {
  region = "us-east-1"
}

locals {
  project_name = "expenses-api"
  environment  = "production"  

  common_tags = {
    Project     = local.project_name
    Environment = local.environment
    ManagedBy   = "Terraform"
    CostCenter  = "Engineering"  
  }
  
  vpc_cidr            = "10.0.0.0/16"
  public_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]
  
  availability_zones = ["us-east-1a", "us-east-1b"]  
  
  # Database configuration - some
  db_name     = "expensedb"
  db_username = "admin"  
  db_port     = 5432
  
  # Redis configuration
  redis_port = 6379
  redis_node_type = "cache.t3.micro"  
  
  allowed_ssh_cidr = "0.0.0.0/0"  
}

# VPC Module - Good use of module
module "vpc" {
  source = "./modules/vpc"
  
  project_name         = local.project_name
  vpc_cidr             = local.vpc_cidr
  public_subnet_cidrs  = local.public_subnet_cidrs
  private_subnet_cidrs = local.private_subnet_cidrs
  availability_zones   = local.availability_zones
  
  tags = local.common_tags
}

# S3 Bucket for application data
module "s3" {
  source = "./modules/s3"
  
  project_name = local.project_name
  environment  = local.environment
  
  enable_versioning = false
  
  tags = local.common_tags
}

# Secrets Manager for sensitive data
resource "random_password" "db_password" {
  length  = 16
  special = true
}

module "secrets" {
  source = "./modules/secrets"
  
  project_name = local.project_name
  
  secrets = {
    database = {
      username = local.db_username
      password = random_password.db_password.result
      host     = module.rds.db_endpoint
      port     = local.db_port
      dbname   = local.db_name
    }
    redis = {
      host = module.redis.redis_endpoint
      port = local.redis_port
    }
    api_keys = {
      external_service = "api-key-12345" 
    }
  }
  
  tags = local.common_tags
}

# RDS PostgreSQL Database
module "rds" {
  source = "./modules/rds"
  
  project_name           = local.project_name
  db_name                = local.db_name
  db_username            = local.db_username
  db_password            = random_password.db_password.result
  
  allocated_storage      = 20
  instance_class         = "db.t3.micro"
  engine_version         = "15.4"
  
  vpc_id                 = module.vpc.vpc_id
  subnet_ids             = module.vpc.private_subnet_ids
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  
  backup_retention_period = 0
  skip_final_snapshot    = true
  
  storage_encrypted = false
  
  tags = local.common_tags
}

# ElastiCache Redis
module "redis" {
  source = "./modules/redis"
  
  project_name = local.project_name
  node_type    = local.redis_node_type
  
  subnet_ids             = module.vpc.private_subnet_ids
  vpc_security_group_ids = [aws_security_group.redis_sg.id]
  
  snapshot_retention_limit = 0
  
  transit_encryption_enabled = false
  
  tags = local.common_tags
}

# Security Groups - Too permissive
resource "aws_security_group" "app_sg" {
  name_prefix = "${local.project_name}-app-"
  description = "Security group for application servers"
  vpc_id      = module.vpc.vpc_id
  
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [local.allowed_ssh_cidr]
    description = "SSH access"
  }
  
  # Application ports - should be behind load balancer
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Java app"
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.project_name}-app-sg"
  })
}

resource "aws_security_group" "rds_sg" {
  name_prefix = "${local.project_name}-rds-"
  description = "Security group for RDS"
  vpc_id      = module.vpc.vpc_id
  
  ingress {
    from_port       = local.db_port
    to_port         = local.db_port
    protocol        = "tcp"
    security_groups = [aws_security_group.app_sg.id]
    description     = "PostgreSQL from app"
  }
  
  ingress {
    from_port   = local.db_port
    to_port     = local.db_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "PostgreSQL from anywhere"
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.project_name}-rds-sg"
  })
}

resource "aws_security_group" "redis_sg" {
  name_prefix = "${local.project_name}-redis-"
  description = "Security group for Redis"
  vpc_id      = module.vpc.vpc_id
  
  ingress {
    from_port       = local.redis_port
    to_port         = local.redis_port
    protocol        = "tcp"
    security_groups = [aws_security_group.app_sg.id]
    description     = "Redis from app"
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.project_name}-redis-sg"
  })
}

# EC2 Instance with IAM role
resource "aws_iam_role" "ec2_role" {
  name = "${local.project_name}-ec2-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
  
  tags = local.common_tags
}

resource "aws_iam_role_policy" "ec2_policy" {
  name = "${local.project_name}-ec2-policy"
  role = aws_iam_role.ec2_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:*",  
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = "*"  
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${local.project_name}-ec2-profile"
  role = aws_iam_role.ec2_role.name
}

resource "aws_instance" "app_server" {
  ami           = "ami-0c55b159cbfafe1f0"  
  instance_type = "t3.micro"
  
  subnet_id                   = module.vpc.public_subnet_ids[0]
  vpc_security_group_ids      = [aws_security_group.app_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2_profile.name
  associate_public_ip_address = true
  
  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y docker postgresql15
              service docker start
              
              aws secretsmanager get-secret-value --secret-id ${module.secrets.secret_id} --region us-east-1
              EOF
  
  monitoring = false
  
  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    encrypted             = false 
    delete_on_termination = true
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.project_name}-app-server"
  })
}

# IAM Users with different permission levels
module "iam_users" {
  source = "./modules/iam"
  
  project_name = local.project_name
  
  users = {
    admin = {
      name        = "${local.project_name}-admin"
      policy_type = "admin"
    }
    readonly = {
      name        = "${local.project_name}-readonly"
      policy_type = "readonly"
    }
    infrastructure = {
      name        = "${local.project_name}-infrastructure"
      policy_type = "infrastructure"  # S3, EC2, RDS, Redis
    }
    secrets = {
      name        = "${local.project_name}-secrets"
      policy_type = "secrets"  # Secrets Manager only
    }
  }
  
  # Resources to grant access to
  s3_bucket_arn    = module.s3.bucket_arn
  rds_instance_arn = module.rds.db_arn
  redis_arn        = module.redis.redis_arn
  secrets_arn      = module.secrets.secret_arn
  
  tags = local.common_tags
}

# Outputs - Some expose sensitive data
output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "s3_bucket_name" {
  description = "S3 bucket name"
  value       = module.s3.bucket_name
}

output "rds_endpoint" {
  description = "RDS endpoint"
  value       = module.rds.db_endpoint
  sensitive   = true  # Good: Marked as sensitive
}

output "redis_endpoint" {
  description = "Redis endpoint"
  value       = module.redis.redis_endpoint
}

output "instance_public_ip" {
  description = "EC2 instance public IP"
  value       = aws_instance.app_server.public_ip
}

output "secret_arn" {
  description = "Secrets Manager ARN"
  value       = module.secrets.secret_arn
}

output "db_password" {
  description = "Database password"
  value       = random_password.db_password.result
  sensitive   = true
}

# IAM user outputs
output "iam_users" {
  description = "Created IAM users"
  value       = module.iam_users.user_names
}

output "iam_access_keys" {
  description = "IAM user access keys"
  value       = module.iam_users.access_keys
  sensitive   = true
}
