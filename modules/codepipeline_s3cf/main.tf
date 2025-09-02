variable "name" { type = string }
variable "github_owner" { type = string }
variable "github_repo" { type = string }
variable "github_branch" { type = string }
variable "github_oauth_token" {
  type      = string
  sensitive = true
}
variable "source_type" {
  description = "Source provider type: GITHUB or S3"
  type        = string
  default     = "GITHUB"
}
variable "s3_source_bucket" {
  type    = string
  default = ""
}
variable "s3_source_object_key" {
  type    = string
  default = ""
}
variable "s3_poll_for_changes" {
  type    = bool
  default = true
}
variable "buildspec" { type = string }
variable "bucket_name" { type = string }
variable "distribution_id" { type = string }
variable "environment_variables" {
  description = "Additional environment variables for CodeBuild (list of maps with name/value)"
  type        = list(object({ name = string, value = string }))
  default     = []
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
locals {
  effective_source_bucket = var.s3_source_bucket != "" ? var.s3_source_bucket : aws_s3_bucket.artifacts.bucket
}

resource "aws_iam_role" "codepipeline" {
  name = "${var.name}-codepipeline-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{ Effect = "Allow", Principal = { Service = "codepipeline.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

resource "aws_iam_role_policy" "codepipeline" {
  name = "${var.name}-codepipeline-policy"
  role = aws_iam_role.codepipeline.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{ Effect = "Allow", Action = ["s3:*", "codebuild:*", "iam:PassRole"], Resource = "*" }]
  })
}

resource "aws_s3_bucket" "artifacts" {
  bucket        = "${var.name}-artifacts-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.name}"
  force_destroy = true
}

resource "aws_iam_role" "codebuild" {
  name = "${var.name}-codebuild-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{ Effect = "Allow", Principal = { Service = "codebuild.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

resource "aws_iam_role_policy" "codebuild" {
  name = "${var.name}-codebuild-policy"
  role = aws_iam_role.codebuild.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      { Effect = "Allow", Action = [
        "logs:CreateLogGroup","logs:CreateLogStream","logs:PutLogEvents",
        "s3:PutObject","s3:PutObjectAcl","s3:DeleteObject","s3:ListBucket",
        "cloudfront:CreateInvalidation"
      ], Resource = "*" }
    ]
  })
}

resource "aws_codebuild_project" "this" {
  name         = "${var.name}-codebuild"
  service_role = aws_iam_role.codebuild.arn
  artifacts { type = "CODEPIPELINE" }
  environment {
    compute_type = "BUILD_GENERAL1_SMALL"
    image        = "aws/codebuild/standard:7.0"
    type         = "LINUX_CONTAINER"

    environment_variable {
      name  = "TARGET_BUCKET"
      value = var.bucket_name
    }
    environment_variable {
      name  = "DISTRIBUTION_ID"
      value = var.distribution_id
    }
    dynamic "environment_variable" {
      for_each = var.environment_variables
      content {
        name  = environment_variable.value.name
        value = environment_variable.value.value
      }
    }
  }
  source {
    type      = "CODEPIPELINE"
    buildspec = var.buildspec
  }
}

resource "aws_codepipeline" "this" {
  name     = "${var.name}-pipeline"
  role_arn = aws_iam_role.codepipeline.arn

  artifact_store {
    location = aws_s3_bucket.artifacts.bucket
    type     = "S3"
  }

  stage {
    name = "Source"
    dynamic "action" {
      for_each = var.source_type == "GITHUB" ? [1] : []
      content {
        name = "Source"
        category = "Source"
        owner = "ThirdParty"
        provider = "GitHub"
        version = "1"
        output_artifacts = ["source_output"]
        configuration = { Owner = var.github_owner, Repo = var.github_repo, Branch = var.github_branch, OAuthToken = var.github_oauth_token }
      }
    }
    dynamic "action" {
      for_each = var.source_type == "S3" ? [1] : []
      content {
        name             = "Source"
        category         = "Source"
        owner            = "AWS"
        provider         = "S3"
        version          = "1"
        output_artifacts = ["source_output"]
        configuration = {
          S3Bucket             = local.effective_source_bucket
          S3ObjectKey          = var.s3_source_object_key
          PollForSourceChanges = tostring(var.s3_poll_for_changes)
        }
      }
    }
  }

  stage {
    name = "Build"
    action {
      name = "Build"
      category = "Build"
      owner = "AWS"
      provider = "CodeBuild"
      input_artifacts = ["source_output"]
      output_artifacts = ["build_output"]
      version = "1"
      configuration = { ProjectName = aws_codebuild_project.this.name }
    }
  }
}

output "pipeline_name" { value = aws_codepipeline.this.name }

output "artifacts_bucket_name" {
  value = aws_s3_bucket.artifacts.bucket
}

