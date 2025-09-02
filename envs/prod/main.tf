locals {
  project = "invitime"
  env     = "prod"
  cluster_name = "${local.project}-${local.env}"
}

data "aws_ecr_repository" "api" {
  name = "invitime-api"
}

module "ecs_cluster" {
  source       = "../../modules/ecs_cluster"
  cluster_name = local.cluster_name
}

module "network" {
  source               = "../../modules/network"
  name_prefix          = local.cluster_name
  cidr                 = "10.20.0.0/16"
  azs                  = ["ap-northeast-2a", "ap-northeast-2c"]
  public_subnet_cidrs  = ["10.20.1.0/24", "10.20.2.0/24"]
  private_subnet_cidrs = ["10.20.101.0/24", "10.20.102.0/24"]
}




data "aws_acm_certificate" "alb" {
  domain      = "invitime.kr"
  statuses    = ["ISSUED"]
  most_recent = true
}

# CloudFront는 us-east-1 인증서 필요
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
  web_host_headers  = ["app.invitime.kr"]
  api_host_headers  = ["api.invitime.kr"]
}

resource "aws_route53_record" "app_prod" {
  zone_id = "Z08466659BE3IFKFX3JV"
  name    = "app.invitime.kr"
  type    = "A"
  alias {
    name                   = module.site_webapp.distribution_domain_name
    zone_id                = module.site_webapp.distribution_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "alb_alias_api" {
  zone_id = "Z08466659BE3IFKFX3JV"
  name    = "api.invitime.kr"
  type    = "A"
  alias {
    name                   = module.alb.alb_dns_name
    zone_id                = module.alb.alb_zone_id
    evaluate_target_health = false
  }
}

module "site_webapp" {
  source         = "../../modules/s3_cf_site"
  name_prefix    = "${local.project}-${local.env}-webapp"
  domain_names   = ["app.invitime.kr"]
  certificate_arn = data.aws_acm_certificate.cf.arn
  providers = {
    aws            = aws
    aws.us_east_1  = aws.us_east_1
  }
}

module "service_api_with_tg" {
  source              = "../../modules/ecs_service"
  name                = "${local.project}-${local.env}-api"
  cluster_arn         = module.ecs_cluster.cluster_arn
  container_image     = data.aws_ecr_repository.api.repository_url
  container_port      = 8000
  desired_count       = 2
  subnet_ids          = module.network.private_subnet_ids
  security_group_ids  = [module.network.api_sg_id]
  target_group_arn    = module.alb.tg_api_arn
  task_cpu            = 256
  task_memory         = 512
  assign_public_ip    = false
  log_group_name      = "/ecs/${local.project}-${local.env}-api"
  environment = {
    ENV                               = local.env
    APP_NAME                          = "InviTime API"
    APP_VERSION                       = "1.0.0"
    DEBUG                             = "False"
    HOST                              = "0.0.0.0"
    PORT                              = "8000"
    DB_ECHO                           = "False"
    ALGORITHM                         = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES       = "1440"
    CORS_ORIGINS                      = "[\"https://app.invitime.kr\"]"
    AWS_REGION                        = "ap-northeast-2"
    S3_BUCKET_NAME                    = "invitime-uploads"
    S3_ENDPOINT_URL                   = ""
    ENVIRONMENT                       = "prod"
    USE_S3                            = "True"
    UPLOAD_MAX_SIZE_MB                = "10"
    UPLOAD_ALLOWED_EXTENSIONS         = "[\".pdf\", \".jpg\", \".jpeg\", \".png\", \".doc\", \".docx\"]"
    LOCAL_UPLOAD_DIR                  = "uploads"
  }
  secret_json_map = local.api_secret_json_map
}

resource "random_password" "app_secret" {
  length  = 48
  special = true
}

resource "aws_secretsmanager_secret" "app_secret" {
  name = "${local.project}-${local.env}-app-secrets"
}

resource "aws_secretsmanager_secret_version" "app_secret" {
  secret_id     = aws_secretsmanager_secret.app_secret.id
  secret_string = jsonencode({ secret_key = random_password.app_secret.result })
}

# FCM service account secret (optional) - 이미 존재하는 시크릿을 조회하고 버전만 생성
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

  # 웹앱은 S3+CloudFront로 전환되어 오토스케일링 불필요

module "autoscaling_api" {
  source        = "../../modules/ecs_autoscaling"
  cluster_name  = module.ecs_cluster.cluster_name
  service_name  = module.service_api_with_tg.service_name
  min_capacity  = 2
  max_capacity  = 6
  cpu_target_percent    = 60
  memory_target_percent = 70
}

module "rds" {
  source                 = "../../modules/rds_mysql"
  name_prefix            = "${local.project}-${local.env}"
  vpc_id                 = module.network.vpc_id
  subnet_ids             = module.network.private_subnet_ids
  allowed_ingress_sg_ids = [module.network.api_sg_id]
  db_name                = "invitime"
  db_username            = "invitime"
  instance_class         = "db.t3.small"
  allocated_storage      = 50
  multi_az               = true
  deletion_protection    = true
  backup_retention       = 7
  engine_version         = "8.0"
}

module "pipeline_webapp" {
  source            = "../../modules/codepipeline_s3cf"
  name              = "${local.project}-${local.env}-webapp"
  github_owner      = "AHPO-PJT"
  github_repo       = "invitime"
  github_branch     = "main"
  github_oauth_token = var.github_oauth_token
  source_type       = "S3"
  s3_source_object_key = "webapp-source.zip"
  buildspec         = file("${path.module}/webapp-buildspec-s3.yml")
  bucket_name       = module.site_webapp.bucket_name
  distribution_id   = module.site_webapp.distribution_id
  environment_variables = [
    { name = "VITE_API_URL", value = "https://api.invitime.kr" }
  ]
}

module "codebuild_webapp" {
  source                 = "../../modules/codebuild_standalone"
  name                   = "${local.project}-${local.env}-webapp"
  github_owner           = "AHPO-PJT"
  github_repo            = "invitime"
  github_branch          = "main"
  github_oauth_token     = var.github_oauth_token
  codeconnections_arn    = "arn:aws:codeconnections:ap-northeast-2:822330924869:connection/8fe44256-51df-40c3-ad88-a8aa6f986bc2"
  ecr_repo_name          = "n/a"
  buildspec              = file("${path.module}/webapp-buildspec-archive.yml")
  artifacts_bucket_name  = module.pipeline_webapp.artifacts_bucket_name
  artifacts_object_name  = "webapp-source.zip"
}

module "pipeline_api" {
  source            = "../../modules/codepipeline_ecs"
  name              = "${local.project}-${local.env}-api"
  github_owner      = "AHPO-PJT"
  github_repo       = "invitime"
  github_branch     = "main"
  github_oauth_token = var.github_oauth_token
  source_type       = "S3"
  s3_source_object_key = "api-source.zip"
  buildspec         = file("${path.module}/api-buildspec.yml")
  ecr_repo_name     = data.aws_ecr_repository.api.name
  ecs_cluster_name  = module.ecs_cluster.cluster_name
  ecs_service_name  = module.service_api_with_tg.service_name
}

module "codebuild_api" {
  source                 = "../../modules/codebuild_standalone"
  name                   = "${local.project}-${local.env}-api"
  github_owner           = "AHPO-PJT"
  github_repo            = "invitime"
  github_branch          = "main"
  github_oauth_token     = var.github_oauth_token
  codeconnections_arn    = "arn:aws:codeconnections:ap-northeast-2:822330924869:connection/8fe44256-51df-40c3-ad88-a8aa6f986bc2"
  ecr_repo_name          = data.aws_ecr_repository.api.name
  buildspec              = file("${path.module}/api-buildspec.yml")
  artifacts_object_name  = "api-source.zip"
  artifacts_bucket_name  = module.pipeline_api.artifacts_bucket_name
}

