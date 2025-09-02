variable "region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-2"
}

variable "aws_access_key" {
  description = "AWS Access Key ID"
  type        = string
  default     = null
  sensitive   = true
}

variable "aws_secret_key" {
  description = "AWS Secret Access Key"
  type        = string
  default     = null
  sensitive   = true
}

variable "bucket_name" {
  description = "Terraform state S3 bucket name"
  type        = string
}

variable "dynamodb_table_name" {
  description = "Terraform state lock DynamoDB table name"
  type        = string
}

variable "force_destroy" {
  description = "Allow force destroy for the state bucket"
  type        = bool
  default     = false
}

