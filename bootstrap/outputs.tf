output "state_bucket_name" {
  value       = aws_s3_bucket.tf_state.bucket
  description = "S3 bucket for Terraform state"
}

output "lock_table_name" {
  value       = aws_dynamodb_table.tf_locks.name
  description = "DynamoDB table for Terraform state locking"
}

