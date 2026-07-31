output "bucket_name" {
  description = "Name of the S3 bucket holding remote state — use in backend config."
  value       = aws_s3_bucket.state.id
}

output "bucket_arn" {
  description = "ARN of the state bucket (for IAM policy scoping)."
  value       = aws_s3_bucket.state.arn
}

output "lock_table_name" {
  description = "Name of the DynamoDB lock table — use as dynamodb_table in backend config."
  value       = aws_dynamodb_table.locks.name
}
