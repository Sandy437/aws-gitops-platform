# Remote-state backend: an S3 bucket (versioned, encrypted, private) for the
# Terraform state file, plus a DynamoDB table for state locking.
#
# NOTE ON THE BOOTSTRAP CHICKEN-AND-EGG: the bucket/table that HOLD remote state
# cannot themselves be stored in that remote state on the first apply. This module
# is applied once with a LOCAL backend, then state is migrated. See ADR-0001.

resource "aws_s3_bucket" "state" {
  bucket        = var.bucket_name
  force_destroy = var.force_destroy
  tags          = var.tags
}

# Versioning: keeps every prior state file so a bad apply can be recovered.
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Encryption at rest (SSE). AES256 keeps it free and simple; a KMS key would be
# the next step for prod (documented as a non-goal here — see ADR-0001).
resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block ALL public access — state files can contain sensitive values.
resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# DynamoDB lock table. PAY_PER_REQUEST = no idle cost; the hash key MUST be
# named "LockID" — that is the contract Terraform's S3 backend expects.
resource "aws_dynamodb_table" "locks" {
  name         = var.lock_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"
  tags         = var.tags

  attribute {
    name = "LockID"
    type = "S"
  }
}
