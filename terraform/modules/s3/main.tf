variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "enable_versioning" {
  type    = bool
  default = false
}

variable "tags" {
  type = map(string)
}

resource "aws_s3_bucket" "main" {
  bucket = "${var.project_name}-${var.environment}-data"  # Bad: No random suffix, might conflict
  
  # Bad: force_destroy allows accidental data deletion
  force_destroy = true
  
  tags = merge(var.tags, {
    Name = "${var.project_name}-data-bucket"
  })
}

# Bad: Versioning disabled by default
resource "aws_s3_bucket_versioning" "main" {
  bucket = aws_s3_bucket.main.id
  
  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Suspended"
  }
}

# Bad: No encryption configuration
# resource "aws_s3_bucket_server_side_encryption_configuration" "main" {
#   bucket = aws_s3_bucket.main.id
#   rule {
#     apply_server_side_encryption_by_default {
#       sse_algorithm = "AES256"
#     }
#   }
# }

# Bad: Public access not blocked
resource "aws_s3_bucket_public_access_block" "main" {
  bucket = aws_s3_bucket.main.id
  
  block_public_acls       = false  # Should be true
  block_public_policy     = false  # Should be true
  ignore_public_acls      = false  # Should be true
  restrict_public_buckets = false  # Should be true
}

output "bucket_name" {
  value = aws_s3_bucket.main.id
}

output "bucket_arn" {
  value = aws_s3_bucket.main.arn
}
