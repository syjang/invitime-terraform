locals {
  project = "invitime"
  env     = "dev"
  cluster_name = "${local.project}-${local.env}"
}

module "ecr_api" {
  source          = "../../modules/ecr"
  repository_name = "${local.project}-api"
  image_mutability = "MUTABLE"
  scan_on_push     = true
}

module "ecs_cluster" {
  source       = "../../modules/ecs_cluster"
  cluster_name = local.cluster_name
}

module "network" {
  source               = "../../modules/network"
  name_prefix          = local.cluster_name
  cidr                 = "10.10.0.0/16"
  azs                  = ["ap-northeast-2a", "ap-northeast-2c"]
  public_subnet_cidrs  = ["10.10.1.0/24", "10.10.2.0/24"]
  private_subnet_cidrs = ["10.10.101.0/24", "10.10.102.0/24"]
}



data "aws_acm_certificate" "alb" {
  domain      = "invitime.kr"
  statuses    = ["ISSUED"]
  most_recent = true
}

# CloudFront용 us-east-1 인증서
data "aws_acm_certificate" "cf" {
  provider    = aws.us_east_1
  domain      = "invitime.kr"
  statuses    = ["ISSUED"]
  most_recent = true
}

module "alb" {
  source            = "../../modules/alb"
  name_prefix       = local.cluster_name
  vpc_id            = module.network.vpc_id
  public_subnet_ids = module.network.public_subnet_ids
  alb_sg_id         = module.network.alb_sg_id
  certificate_arn   = data.aws_acm_certificate.alb.arn
  web_port          = 3000
  api_port          = 8000
  web_host_headers  = ["app-dev.invitime.kr"]
  api_host_headers  = ["api-dev.invitime.kr"]
}

resource "aws_route53_record" "app_dev" {
  zone_id = "Z08466659BE3IFKFX3JV"
  name    = "app-dev.invitime.kr"
  type    = "A"
  alias {
    name                   = module.site_webapp.distribution_domain_name
    zone_id                = module.site_webapp.distribution_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "api_dev" {
  zone_id = "Z08466659BE3IFKFX3JV"
  name    = "api-dev.invitime.kr"
  type    = "A"
  alias {
    name                   = module.alb.alb_dns_name
    zone_id                = module.alb.alb_zone_id
    evaluate_target_health = false
  }
}

# Attach services to ALB target groups
module "site_webapp" {
  source         = "../../modules/s3_cf_site"
  name_prefix    = "${local.project}-${local.env}-webapp"
  domain_names   = ["app-dev.invitime.kr"]
  certificate_arn = data.aws_acm_certificate.cf.arn
  providers = {
    aws            = aws
    aws.us_east_1  = aws.us_east_1
  }
}

module "service_api_with_tg" {
  source              = "../../modules/ecs_service"
  name                = "${local.project}-api"
  cluster_arn         = module.ecs_cluster.cluster_arn
  container_image     = "${module.ecr_api.repository_url}:dev-latest"
  container_port      = 8000
  desired_count       = 1
  subnet_ids          = module.network.private_subnet_ids
  security_group_ids  = [module.network.api_sg_id]
  target_group_arn    = module.alb.tg_api_arn
  task_cpu            = 512
  task_memory         = 1024
  assign_public_ip    = false
  log_group_name      = "/ecs/${local.project}-${local.env}-api"
  environment = {
    ENV                               = local.env
    APP_NAME                          = "InviTime API"
    APP_VERSION                       = "1.0.0"
    HOST                              = "0.0.0.0"
    PORT                              = "8000"
    DB_ECHO                           = "False"
    ALGORITHM                         = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES       = "1440"
    CORS_ORIGINS                      = "[\"https://app-dev.invitime.kr\"]"
    AWS_REGION                        = "ap-northeast-2"
    S3_BUCKET_NAME                    = "invitime-uploads"
    S3_ENDPOINT_URL                   = ""
    ENVIRONMENT                       = "dev"
    USE_S3                            = "True"
    UPLOAD_MAX_SIZE_MB                = "10"
    UPLOAD_ALLOWED_EXTENSIONS         = "[\".pdf\", \".jpg\", \".jpeg\", \".png\", \".doc\", \".docx\"]"
    LOCAL_UPLOAD_DIR                  = "uploads"
    RUN_MIGRATIONS                    = "true"
  }
  secret_json_map = merge(local.api_secret_json_map, {
    DB_USER     = { secret_arn = module.rds.secret_arn, key = "username" }
    DB_PASSWORD = { secret_arn = module.rds.secret_arn, key = "password" }
    DB_HOST     = { secret_arn = module.rds.secret_arn, key = "host" }
    DB_PORT     = { secret_arn = module.rds.secret_arn, key = "port" }
    DB_NAME     = { secret_arn = module.rds.secret_arn, key = "dbname" }
    SMTP_PASSWORD = { secret_arn = data.aws_secretsmanager_secret.smtp.arn, key = "password" }
    SMTP_USERNAME = { secret_arn = data.aws_secretsmanager_secret.smtp.arn, key = "username" }
  })
  task_policy_json = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:PutObject","s3:GetObject","s3:DeleteObject","s3:ListBucket"
        ],
        Resource = [
          "arn:aws:s3:::invitime-uploads",
          "arn:aws:s3:::invitime-uploads/*"
        ]
      },
      {
        Effect = "Allow",
        Action = ["ses:SendEmail","ses:SendRawEmail"],
        Resource = "*"
      }
    ]
  })
}

resource "random_password" "app_secret" {
  length  = 32
  special = true
}

resource "aws_secretsmanager_secret" "app_secret" {
  name = "${local.project}-${local.env}-app-secrets"
}

resource "aws_secretsmanager_secret_version" "app_secret" {
  secret_id     = aws_secretsmanager_secret.app_secret.id
  secret_string = jsonencode({ secret_key = random_password.app_secret.result })
}

# SMTP secret (existing resource)
data "aws_secretsmanager_secret" "smtp" {
  name = "invitime-smtp"
}

# FCM service account secret (optional)
data "aws_secretsmanager_secret" "fcm" {
  count = var.fcm_service_account_json == null ? 0 : 1
  name  = "${local.project}-${local.env}-fcm-service-account"
}

resource "aws_secretsmanager_secret_version" "fcm" {
  count         = var.fcm_service_account_json == null ? 0 : 1
  secret_id     = data.aws_secretsmanager_secret.fcm[0].id
  secret_string = jsonencode({ json = var.fcm_service_account_json })
}

locals {
  api_secret_json_map_base = {
    DB_USERNAME = { secret_arn = module.rds.secret_arn, key = "username" }
    DB_PASSWORD = { secret_arn = module.rds.secret_arn, key = "password" }
    DB_HOST     = { secret_arn = module.rds.secret_arn, key = "host" }
    DB_PORT     = { secret_arn = module.rds.secret_arn, key = "port" }
    DB_NAME     = { secret_arn = module.rds.secret_arn, key = "dbname" }
    SECRET_KEY  = { secret_arn = aws_secretsmanager_secret.app_secret.arn, key = "secret_key" }
  }

  api_secret_json_map = var.fcm_service_account_json == null ? local.api_secret_json_map_base : merge(
    local.api_secret_json_map_base,
    {
      FCM_SERVICE_ACCOUNT_KEY = { secret_arn = data.aws_secretsmanager_secret.fcm[0].arn, key = "json" }
    }
  )
}

module "rds" {
  source                 = "../../modules/rds_mysql"
  name_prefix            = "${local.project}-${local.env}"
  vpc_id                 = module.network.vpc_id
  subnet_ids             = ["subnet-0449e94951e76e7fd", "subnet-0b48e484f6b16652b"]
  allowed_ingress_sg_ids = [module.network.api_sg_id]
  db_name                = "invitime"
  db_username            = "invitime"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  multi_az               = false
  engine_version         = "8.4.6"
  deletion_protection    = false
  backup_retention       = 1
  publicly_accessible    = false
}

  # 웹앱은 S3+CloudFront로 전환되어 오토스케일링 불필요

module "autoscaling_api" {
  source        = "../../modules/ecs_autoscaling"
  cluster_name  = module.ecs_cluster.cluster_name
  service_name  = module.service_api_with_tg.service_name
  min_capacity  = 1
  max_capacity  = 3
  cpu_target_percent    = 60
  memory_target_percent = 70
}

# Webapp pipeline
// 웹앱 파이프라인 제거 (ext CodeBuild만 사용)

# Git → CodeBuild(웹앱 빌드 아카이브를 S3에 업로드)
module "codebuild_webapp" {
  source                 = "../../modules/codebuild_standalone"
  name                   = "${local.project}-${local.env}-webapp"
  github_owner           = "AHPO-PJT"
  github_repo            = "invitime"
  github_branch          = "dev"
  github_oauth_token     = var.github_oauth_token
  codeconnections_arn    = "arn:aws:codeconnections:ap-northeast-2:822330924869:connection/8fe44256-51df-40c3-ad88-a8aa6f986bc2"
  ecr_repo_name          = "n/a"
  buildspec              = file("${path.module}/webapp-buildspec-s3.yml")
  artifacts_bucket_name  = ""
  artifacts_object_name  = ""
  path_filter            = "^dashboard/.*"
  extra_environment_variables = [
    { name = "TARGET_BUCKET", value = module.site_webapp.bucket_name },
    { name = "DISTRIBUTION_ID", value = module.site_webapp.distribution_id },
    { name = "VITE_API_URL", value = "https://api-dev.invitime.kr" }
  ]
}

# API pipeline
module "pipeline_api" {
  source            = "../../modules/codepipeline_ecs"
  name              = "${local.project}-${local.env}-api"
  github_owner      = "AHPO-PJT"
  github_repo       = "invitime"
  github_branch     = "dev"
  github_oauth_token = var.github_oauth_token
  source_type       = "S3"
  s3_source_object_key = "api-source.zip"
  buildspec         = file("${path.module}/api-buildspec.yml")
  ecr_repo_name     = module.ecr_api.repository_name
  ecs_cluster_name  = module.ecs_cluster.cluster_name
  ecs_service_name  = module.service_api_with_tg.service_name
}

# Git → CodeBuild(빌드/푸시 + imagedefinitions.zip S3 업로드)
module "codebuild_api" {
  source                 = "../../modules/codebuild_standalone"
  name                   = "${local.project}-${local.env}-api"
  github_owner           = "AHPO-PJT"
  github_repo            = "invitime"
  github_branch          = "dev"
  github_oauth_token     = var.github_oauth_token
  codeconnections_arn    = "arn:aws:codeconnections:ap-northeast-2:822330924869:connection/8fe44256-51df-40c3-ad88-a8aa6f986bc2"
  ecr_repo_name          = module.ecr_api.repository_name
  buildspec              = file("${path.module}/api-buildspec.yml")
  artifacts_object_name  = "api-source.zip"
  artifacts_bucket_name  = module.pipeline_api.artifacts_bucket_name
  path_filter            = "^api-server/.*"
}

