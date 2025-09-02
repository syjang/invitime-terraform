# init
docker run --rm -v "/Users/leo/project/invitime-terraform":/workspace -w /workspace/envs/dev \
  -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_DEFAULT_REGION=ap-northeast-2 \
  hashicorp/terraform:latest init -upgrade | cat

# Secrets: app_secret
docker run --rm -v "/Users/leo/project/invitime-terraform":/workspace -w /workspace/envs/dev \
  -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_DEFAULT_REGION=ap-northeast-2 \
  hashicorp/terraform:latest state rm 'aws_secretsmanager_secret.app_secret' | cat
docker run --rm -v "/Users/leo/project/invitime-terraform":/workspace -w /workspace/envs/dev \
  -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_DEFAULT_REGION=ap-northeast-2 \
  hashicorp/terraform:latest import 'aws_secretsmanager_secret.app_secret' \
  'arn:aws:secretsmanager:ap-northeast-2:822330924869:secret:invitime-dev-app-secrets-P9bt1d' | cat

# Secrets: fcm (있을 때만)
docker run --rm -v "/Users/leo/project/invitime-terraform":/workspace -w /workspace/envs/dev \
  -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_DEFAULT_REGION=ap-northeast-2 \
  hashicorp/terraform:latest state rm 'aws_secretsmanager_secret.fcm[0]' | cat
docker run --rm -v "/Users/leo/project/invitime-terraform":/workspace -w /workspace/envs/dev \
  -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_DEFAULT_REGION=ap-northeast-2 \
  hashicorp/terraform:latest import 'aws_secretsmanager_secret.fcm[0]' \
  'arn:aws:secretsmanager:ap-northeast-2:822330924869:secret:invitime-dev-fcm-service-account-jyaQLU' | cat

# Secrets: RDS 자격증명
docker run --rm -v "/Users/leo/project/invitime-terraform":/workspace -w /workspace/envs/dev \
  -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_DEFAULT_REGION=ap-northeast-2 \
  hashicorp/terraform:latest state rm 'module.rds.aws_secretsmanager_secret.db' | cat
docker run --rm -v "/Users/leo/project/invitime-terraform":/workspace -w /workspace/envs/dev \
  -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_DEFAULT_REGION=ap-northeast-2 \
  hashicorp/terraform:latest import 'module.rds.aws_secretsmanager_secret.db' \
  'arn:aws:secretsmanager:ap-northeast-2:822330924869:secret:invitime-dev-db-credentials-gyXVQp' | cat

# IAM inline policy들 (형식: role_name:policy_name)
docker run --rm -v "/Users/leo/project/invitime-terraform":/workspace -w /workspace/envs/dev \
  -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_DEFAULT_REGION=ap-northeast-2 \
  hashicorp/terraform:latest state rm 'module.pipeline_api.aws_iam_role_policy.codepipeline' | cat
docker run --rm -v "/Users/leo/project/invitime-terraform":/workspace -w /workspace/envs/dev \
  -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_DEFAULT_REGION=ap-northeast-2 \
  hashicorp/terraform:latest import 'module.pipeline_api.aws_iam_role_policy.codepipeline' \
  'invitime-dev-api-codepipeline-role:invitime-dev-api-codepipeline-policy' | cat

docker run --rm -v "/Users/leo/project/invitime-terraform":/workspace -w /workspace/envs/dev \
  -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_DEFAULT_REGION=ap-northeast-2 \
  hashicorp/terraform:latest state rm 'module.pipeline_api.aws_iam_role_policy.codebuild' | cat
docker run --rm -v "/Users/leo/project/invitime-terraform":/workspace -w /workspace/envs/dev \
  -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_DEFAULT_REGION=ap-northeast-2 \
  hashicorp/terraform:latest import 'module.pipeline_api.aws_iam_role_policy.codebuild' \
  'invitime-dev-api-codebuild-role:invitime-dev-api-codebuild-policy' | cat

docker run --rm -v "/Users/leo/project/invitime-terraform":/workspace -w /workspace/envs/dev \
  -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_DEFAULT_REGION=ap-northeast-2 \
  hashicorp/terraform:latest state rm 'module.pipeline_webapp.aws_iam_role_policy.codepipeline' | cat
docker run --rm -v "/Users/leo/project/invitime-terraform":/workspace -w /workspace/envs/dev \
  -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_DEFAULT_REGION=ap-northeast-2 \
  hashicorp/terraform:latest import 'module.pipeline_webapp.aws_iam_role_policy.codepipeline' \
  'invitime-dev-webapp-codepipeline-role:invitime-dev-webapp-codepipeline-policy' | cat

docker run --rm -v "/Users/leo/project/invitime-terraform":/workspace -w /workspace/envs/dev \
  -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_DEFAULT_REGION=ap-northeast-2 \
  hashicorp/terraform:latest state rm 'module.pipeline_webapp.aws_iam_role_policy.codebuild' | cat
docker run --rm -v "/Users/leo/project/invitime-terraform":/workspace -w /workspace/envs/dev \
  -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_DEFAULT_REGION=ap-northeast-2 \
  hashicorp/terraform:latest import 'module.pipeline_webapp.aws_iam_role_policy.codebuild' \
  'invitime-dev-webapp-codebuild-role:invitime-dev-webapp-codebuild-policy' | cat

# 최종 확인
docker run --rm -v "/Users/leo/project/invitime-terraform":/workspace -w /workspace/envs/dev \
  -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_DEFAULT_REGION=ap-northeast-2 \
  hashicorp/terraform:latest plan | cat