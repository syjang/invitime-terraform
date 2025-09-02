variable "region" {
  type    = string
  default = "ap-northeast-2"
}

variable "aws_access_key" {
  type      = string
  default   = null
  sensitive = true
}

variable "aws_secret_key" {
  type      = string
  default   = null
  sensitive = true
}

variable "github_oauth_token" {
  type      = string
  sensitive = true
  default   = ""
}

variable "fcm_service_account_json" {
  description = "FCM 서비스 계정 JSON 전체 문자열"
  type        = string
  default     = null
  sensitive   = true
}

