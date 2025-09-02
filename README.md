## Invitime Terraform 인프라

이 저장소는 AWS 상에 invitime 프로젝트(프론트 `dashboard`, 백엔드 `api-server`)를 ECR/ECS/CodeBuild/CodePipeline으로 배포하기 위한 Terraform 구성을 담습니다. 환경은 `dev`와 `prod` 두 가지이며, 테라폼 상태는 S3 + DynamoDB를 사용합니다.

### 구성 개요
- **클러스터**: `invitime-dev`, `invitime-prod`
- **서비스**: `invitime-webapp`(React dashboard), `invitime-api`(Python api-server)
- **레지스트리**: ECR 1개 (API), 웹앱은 S3로 정적 배포
- **배포 파이프라인**: GitHub → CodeBuild → ECR/S3 → CodePipeline → ECS/CloudFront
- **상태 저장소**: S3 버킷(`invitime-terraform`) + DynamoDB 테이블(`invitime-tf-locks`)
 - **네트워크**: 전용 VPC, 퍼블릭/프라이빗 서브넷, NAT, SG
 - **로드밸런서**: ALB(HTTP→HTTPS 리다이렉트), HTTPS(ACM 인증서)
 - **오토스케일링**: ECS 서비스 CPU/메모리 타겟 추적

### 사전 준비
- AWS 자격 증명: Access Key ID / Secret Key
- GitHub 저장소: `https://github.com/AHPO-PJT/invitime` (모노레포: `dashboard`, `api-server`)
- 리전 기본값: `ap-northeast-2` (필요시 변경)

### 1) 상태 저장소 (S3 backend)
- dev/prod의 backend 버킷은 `invitime-terraform`으로 설정되어 있습니다.
- 기존 다른 버킷을 쓰고 있었다면 각 환경에서 `terraform init -migrate-state`로 마이그레이션하세요.

### 2) 환경별 초기화 (dev/prod)
`envs/dev/providers.tf`, `envs/prod/providers.tf`의 S3/DynamoDB backend 설정을 확인하세요.

AWS 자격 증명은 다음 중 하나로 제공합니다.
- 환경 변수: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`
- 혹은 Terraform 변수로 전달: `-var "aws_access_key=..." -var "aws_secret_key=..."`

예시:
```
cd envs/dev
terraform init
terraform plan \
  -var "aws_access_key=$AWS_ACCESS_KEY_ID" \
  -var "aws_secret_key=$AWS_SECRET_ACCESS_KEY" \
  -var "region=ap-northeast-2"
```

### 현재 상태 (초안)
- `bootstrap`: S3/DDB 상태 저장소 생성 코드 포함
- `modules`: ECR, ECS 클러스터/서비스, CodeBuild, CodePipeline 모듈 스캐폴딩 포함
- `modules/network`, `modules/alb`, `modules/acm`, `modules/ecs_autoscaling` 추가
- `envs/dev`, `envs/prod`: 네트워크/ALB/ACM/오토스케일링과 ECS 서비스 연동 예시 포함

### Docker로 Terraform 실행
로컬에 Terraform 설치 없이 Docker로 실행합니다.

```
docker run --rm \
  -v $(pwd):/workspace \
  -w /workspace/envs/dev \
  -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_DEFAULT_REGION=ap-northeast-2 \
  hashicorp/terraform:latest init

docker run --rm \
  -v $(pwd):/workspace \
  -w /workspace/envs/dev \
  -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_DEFAULT_REGION=ap-northeast-2 \
  hashicorp/terraform:latest apply -auto-approve
```

prod도 동일하게 `-w /workspace/envs/prod`로 바꿔 실행합니다.

### 구성 상세
- 웹앱: S3+CloudFront (dev: `app-dev.invitime.kr`, prod: `app.invitime.kr`)
- API: ECS Fargate(+ALB) (dev: `api-dev.invitime.kr`, prod: `api.invitime.kr`)
- 인증서: ACM + Route53 DNS 검증
- 오토스케일링: ECS Target Tracking(CPU/Memory)
- RDS(MySQL): 프라이빗 서브넷, 접속정보는 Secrets Manager 보관
- 시크릿 주입: `secret_json_map`으로 Secrets Manager JSON 키를 컨테이너 env로 주입

### 실행 스크립트
- dev: `scripts/dev-apply.sh` (로컬 `invitime-account.json`을 읽어 FCM JSON 전달)
- prod: `scripts/prod-apply.sh`

### FCM 서비스 계정 주입
- 전체 JSON을 그대로 전달 (파일: `invitime-account.json`)
- 컨테이너에는 `FCM_SERVICE_ACCOUNT_KEY` 환경변수로 주입됩니다.


