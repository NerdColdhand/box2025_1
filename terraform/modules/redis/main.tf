variable "project_name" {
  type = string
}

variable "node_type" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "vpc_security_group_ids" {
  type = list(string)
}

variable "snapshot_retention_limit" {
  type = number
}

variable "transit_encryption_enabled" {
  type = bool
}

variable "tags" {
  type = map(string)
}

resource "aws_elasticache_subnet_group" "main" {
  name       = "${var.project_name}-redis-subnet"
  subnet_ids = var.subnet_ids
  
  tags = merge(var.tags, {
    Name = "${var.project_name}-redis-subnet-group"
  })
}

resource "aws_elasticache_cluster" "main" {
  cluster_id           = "${var.project_name}-redis"
  engine               = "redis"
  node_type            = var.node_type
  num_cache_nodes      = 1  
  parameter_group_name = "default.redis7"
  engine_version       = "7.0"
  port                 = 6379
  
  subnet_group_name    = aws_elasticache_subnet_group.main.name
  security_group_ids   = var.vpc_security_group_ids
  
  snapshot_retention_limit = var.snapshot_retention_limit
  
  # at_rest_encryption_enabled = false
  
  transit_encryption_enabled = var.transit_encryption_enabled
  
  auto_minor_version_upgrade = false
  
  maintenance_window = "sun:05:00-sun:06:00"
  
  tags = merge(var.tags, {
    Name = "${var.project_name}-redis"
  })
}

# Better approach would be to use replication group:
# resource "aws_elasticache_replication_group" "main" {
#   replication_group_id       = "${var.project_name}-redis"
#   replication_group_description = "Redis cluster for ${var.project_name}"
#   engine                     = "redis"
#   node_type                  = var.node_type
#   number_cache_clusters      = 2
#   automatic_failover_enabled = true
#   multi_az_enabled          = true
#   at_rest_encryption_enabled = true
#   transit_encryption_enabled = true
# }

output "redis_endpoint" {
  value = aws_elasticache_cluster.main.cache_nodes[0].address
}

output "redis_arn" {
  value = aws_elasticache_cluster.main.arn
}

output "redis_port" {
  value = aws_elasticache_cluster.main.port
}
