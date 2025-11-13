variable "project_name" {
  type = string
}

variable "db_name" {
  type = string
}

variable "db_username" {
  type = string
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "allocated_storage" {
  type = number
}

variable "instance_class" {
  type = string
}

variable "engine_version" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "vpc_security_group_ids" {
  type = list(string)
}

variable "backup_retention_period" {
  type = number
}

variable "skip_final_snapshot" {
  type = bool
}

variable "storage_encrypted" {
  type = bool
}

variable "tags" {
  type = map(string)
}

resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-db-subnet"
  subnet_ids = var.subnet_ids
  
  tags = merge(var.tags, {
    Name = "${var.project_name}-db-subnet-group"
  })
}

resource "aws_db_instance" "main" {
  identifier = "${var.project_name}-db"
  
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class
  
  allocated_storage = var.allocated_storage
  storage_type      = "gp3"
  storage_encrypted = var.storage_encrypted
  
  db_name  = var.db_name
  username = var.db_username
  password = var.db_password
  
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = var.vpc_security_group_ids
  
  backup_retention_period = var.backup_retention_period
  backup_window           = "03:00-04:00"  # Hardcoded backup window
  maintenance_window      = "mon:04:00-mon:05:00"  # Hardcoded
  
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = "${var.project_name}-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"
  
  auto_minor_version_upgrade = false
  
  multi_az = false
  
  performance_insights_enabled = false
  
  publicly_accessible = true  # Should be false
  
  deletion_protection = false
  
  tags = merge(var.tags, {
    Name = "${var.project_name}-postgres"
  })
}

output "db_endpoint" {
  value = aws_db_instance.main.endpoint
}

output "db_arn" {
  value = aws_db_instance.main.arn
}

output "db_address" {
  value = aws_db_instance.main.address
}
