# Tests for the remote-state module.
#
# `command = plan` means these assert CONFIGURATION LOGIC only — no API calls, no
# credentials, no cost. They run in CI and in a fork. See ADR-0004.

# Dummy provider config so plan can run without real credentials.
provider "aws" {
  region                      = "eu-central-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}

variables {
  bucket_name = "example-tfstate-test"
}

run "state_bucket_is_hardened_by_default" {
  command = plan

  assert {
    condition     = aws_s3_bucket_versioning.state.versioning_configuration[0].status == "Enabled"
    error_message = "State bucket versioning must be Enabled — it is the recovery path for a bad state write."
  }

  # `rule` is a SET of objects, so it has no addressable index — flatten it with a
  # for expression instead of rule[0]. Deliberately AES256, not aws:kms: ADR-0001
  # records KMS-CMK as a documented non-goal.
  assert {
    condition = anytrue([
      for r in aws_s3_bucket_server_side_encryption_configuration.state.rule :
      anytrue([
        for d in r.apply_server_side_encryption_by_default : d.sse_algorithm == "AES256"
      ])
    ])
    error_message = "State bucket must be encrypted at rest with AES256."
  }

  # All four public-access controls must be on. State files can contain secrets.
  assert {
    condition = alltrue([
      aws_s3_bucket_public_access_block.state.block_public_acls,
      aws_s3_bucket_public_access_block.state.block_public_policy,
      aws_s3_bucket_public_access_block.state.ignore_public_acls,
      aws_s3_bucket_public_access_block.state.restrict_public_buckets,
    ])
    error_message = "All four S3 public-access blocks must be enabled on the state bucket."
  }

  assert {
    condition     = aws_s3_bucket.state.force_destroy == false
    error_message = "force_destroy must default to false — deleting a populated state bucket is catastrophic."
  }
}

run "lock_table_matches_the_backend_contract" {
  command = plan

  # Terraform's S3 backend requires the lock table's hash key to be exactly "LockID".
  assert {
    condition     = aws_dynamodb_table.locks.hash_key == "LockID"
    error_message = "Lock table hash_key must be 'LockID' — that is the contract the S3 backend expects."
  }

  assert {
    condition     = aws_dynamodb_table.locks.billing_mode == "PAY_PER_REQUEST"
    error_message = "Lock table should be PAY_PER_REQUEST so an idle backend costs nothing."
  }
}

run "rejects_an_invalid_bucket_name" {
  command = plan

  # S3 names cannot contain uppercase; the variable validation must catch it.
  variables {
    bucket_name = "Invalid_Bucket_NAME"
  }

  expect_failures = [var.bucket_name]
}
