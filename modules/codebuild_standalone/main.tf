variable "name" { type = string }
variable "github_owner" { type = string }
variable "github_repo" { type = string }
variable "github_branch" {
  type    = string
  default = "main"
}
variable "github_oauth_token" {
  type      = string
  sensitive = true
  default   = ""
}
variable "codeconnections_arn" {
  description = "CodeConnections connection ARN used by CodeBuild for GitHub access"
  type        = string
  default     = ""
}
variable "ecr_repo_name" { type = string }
variable "buildspec" { type = string }
variable "artifacts_bucket_name" {
  type    = string
  default = ""
}
variable "artifacts_object_name" {
  type    = string
  default = "api-source.zip"
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "aws_s3_bucket" "artifacts" {
  count         = var.artifacts_bucket_name == "" ? 1 : 0
  bucket        = "${var.name}-artifacts-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.name}"
  force_destroy = true
}

locals {
  effective_bucket = var.artifacts_bucket_name != "" ? var.artifacts_bucket_name : aws_s3_bucket.artifacts[0].bucket
}

resource "aws_iam_role" "codebuild" {
  name = "${var.name}-ext-codebuild-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Service = "codebuild.amazonaws.com" },
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "codebuild" {
  name = "${var.name}-ext-codebuild-policy"
  role = aws_iam_role.codebuild.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      { Effect = "Allow", Action = [
          "ecr:GetAuthorizationToken", "ecr:BatchCheckLayerAvailability",
          "ecr:CompleteLayerUpload", "ecr:UploadLayerPart",
          "ecr:InitiateLayerUpload", "ecr:PutImage",
          "logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents",
          "s3:*", "sts:GetCallerIdentity"
        ], Resource = "*" },
      {
        Effect   = "Allow",
        Action   = [
          "codestar-connections:UseConnection",
          "codestar-connections:GetConnection",
          "codestar-connections:GetConnectionToken",
          "codeconnections:UseConnection",
          "codeconnections:GetConnection",
          "codeconnections:GetConnectionToken"
        ],
        Resource = var.codeconnections_arn != "" ? var.codeconnections_arn : "*"
      }
    ]
  })
}

# GitHub PAT를 사용하는 경우(선택)
resource "aws_codebuild_source_credential" "github_pat" {
  count       = length(var.github_oauth_token) > 0 ? 1 : 0
  auth_type   = "PERSONAL_ACCESS_TOKEN"
  server_type = "GITHUB"
  token       = var.github_oauth_token
}

resource "aws_codebuild_project" "this" {
  name         = "${var.name}-ext-codebuild"
  service_role = aws_iam_role.codebuild.arn

  artifacts {
    type      = "S3"
    location  = local.effective_bucket
    packaging = "ZIP"
    name      = var.artifacts_object_name
  }

  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/standard:7.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = true
    environment_variable {
      name  = "AWS_DEFAULT_REGION"
      value = data.aws_region.current.name
    }
    environment_variable {
      name  = "IMAGE_REPO_NAME"
      value = var.ecr_repo_name
    }
    environment_variable {
      name  = "IMAGE_TAG"
      value = "latest"
    }
  }

  source {
    type            = "GITHUB"
    location        = "https://github.com/${var.github_owner}/${var.github_repo}.git"
    git_clone_depth = 1
    buildspec       = var.buildspec
    report_build_status = true
    dynamic "auth" {
      for_each = var.codeconnections_arn != "" ? [1] : []
      content {
        type     = "CODECONNECTIONS"
        resource = var.codeconnections_arn
      }
    }
  }
}

output "artifacts_bucket_name" { value = local.effective_bucket }
output "artifacts_object_key" { value = var.artifacts_object_name }

