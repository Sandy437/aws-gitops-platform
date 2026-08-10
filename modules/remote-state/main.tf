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

# Encryption at rest (SSE-S3 / AES256).
#
# Trivy AWS-0132 (HIGH) wants a customer-managed KMS key (SSE-KMS) here. That is
# accepted-but-deferred, not overlooked: ADR-0001 records KMS-CMK as an explicit
# non-goal for a portfolio backend, where AES256 + bucket versioning already gives
# encryption at rest and a recovery path for a bad state write. SSE-KMS earns its
# keep when you need key rotation policy, per-key access control, and CloudTrail
# auditability of key use — i.e. a real multi-team production backend.
#
# The suppression carries an expiry so it cannot rot silently: after that date CI
# fails again and forces a re-decision. Tracked for implementation as an optional
# `kms_key_arn` input (see repo issues).
#trivy:ignore:AWS-0132 exp:2027-02-01
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
