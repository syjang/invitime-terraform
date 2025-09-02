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
}
variable "source_type" {
  description = "Source provider type: GITHUB or S3"
  type        = string
  default     = "GITHUB"
}
variable "s3_source_bucket" {
  description = "S3 bucket name for Source stage when source_type=S3"
  type        = string
  default     = ""
}
variable "s3_source_object_key" {
  description = "S3 object key (zip) for Source stage when source_type=S3"
  type        = string
  default     = ""
}
variable "s3_poll_for_changes" {
  description = "Whether to poll S3 for changes in Source stage"
  type        = bool
  default     = true
}
variable "buildspec" { type = string }
variable "ecr_repo_name" { type = string }
variable "ecs_cluster_name" { type = string }
variable "ecs_service_name" { type = string }

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
locals {
  effective_source_bucket = var.s3_source_bucket != "" ? var.s3_source_bucket : aws_s3_bucket.artifacts.bucket
}

resource "aws_iam_role" "codepipeline" {
  name = "${var.name}-codepipeline-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Service = "codepipeline.amazonaws.com" },
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "codepipeline" {
  name = "${var.name}-codepipeline-policy"
  role = aws_iam_role.codepipeline.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      { Effect = "Allow", Action = [
          "s3:*", "codebuild:BatchGetBuilds", "codebuild:StartBuild",
          "iam:PassRole", "ecs:DescribeServices", "ecs:DescribeTaskDefinition",
          "ecs:RegisterTaskDefinition", "ecs:UpdateService", "ecr:DescribeImages"
        ], Resource = "*" }
    ]
  })
}

resource "aws_s3_bucket" "artifacts" {
  bucket        = "${var.name}-artifacts-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.name}"
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

## Externalized build: CodePipeline은 S3 Source → ECS Deploy만 수행

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
        name             = "Source"
        category         = "Source"
        owner            = "ThirdParty"
        provider         = "GitHub"
        version          = "1"
        output_artifacts = ["source_output"]
        configuration = {
          Owner      = var.github_owner
          Repo       = var.github_repo
          Branch     = var.github_branch
          OAuthToken = var.github_oauth_token
        }
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

  # 외부 CodeBuild가 S3에 올린 zip(source_output)을 그대로 ECS Deploy에 전달

  stage {
    name = "Deploy"
    action {
      name            = "DeployToECS"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "ECS"
      input_artifacts = ["source_output"]
      version         = "1"
      configuration = {
        ClusterName = var.ecs_cluster_name
        ServiceName = var.ecs_service_name
        FileName    = "imagedefinitions.json"
      }
    }
  }
}

output "pipeline_name" { value = aws_codepipeline.this.name }

output "artifacts_bucket_name" {
  value = aws_s3_bucket.artifacts.bucket
}

