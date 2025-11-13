variable "project_name" {
  type = string
}

variable "secrets" {
  type = any
}

variable "tags" {
  type = map(string)
}

resource "aws_secretsmanager_secret" "main" {
  name = "${var.project_name}-secrets"  
  
  recovery_window_in_days = 0  # Immediate deletion - dangerous
  
  tags = merge(var.tags, {
    Name = "${var.project_name}-secrets"
  })
}

resource "aws_secretsmanager_secret_version" "main" {
  secret_id     = aws_secretsmanager_secret.main.id
  secret_string = jsonencode(var.secrets)
}

output "secret_id" {
  value = aws_secretsmanager_secret.main.id
}

output "secret_arn" {
  value = aws_secretsmanager_secret.main.arn
}
