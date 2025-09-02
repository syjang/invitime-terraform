#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
ACCOUNT_JSON_PATH="$ROOT_DIR/invitime-account.json"
ENV_FILE="$ROOT_DIR/.env.aws"

usage() {
  echo "Usage: $0 [dev|prod] [additional terraform plan args...]" >&2
  echo "Example: $0 dev -target=module.pipeline_webapp" >&2
  exit 1
}

# .env.aws가 있으면 우선 로드
if [[ -f "$ENV_FILE" ]]; then
  echo "[INFO] loading $ENV_FILE"
  set -o allexport
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +o allexport
fi

if [[ $# -lt 1 ]]; then
  usage
fi

ENV_NAME="$1"; shift || true
case "$ENV_NAME" in
  dev|prod) ;;
  *) echo "[ERR] first arg must be dev or prod" >&2; usage;;
esac

if [[ ! -f "$ACCOUNT_JSON_PATH" ]]; then
  echo "[ERR] $ACCOUNT_JSON_PATH 파일이 없습니다." >&2
  exit 1
fi

# 기본 리전
export AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION:-ap-northeast-2}

# AWS 자격증명 확인 (.env.aws 로드 후 확인)
if [[ -z "${AWS_ACCESS_KEY_ID:-}" || -z "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
  echo "[ERR] AWS 자격증명(AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY)을 환경변수로 설정하세요." >&2
  echo "      루트 경로의 .env.aws 파일에 정의해도 됩니다. (예: AWS_ACCESS_KEY_ID=..., AWS_SECRET_ACCESS_KEY=...)" >&2
  exit 1
fi

# FCM 서비스 계정 JSON을 단일 라인으로 변환
if command -v python3 >/dev/null 2>&1; then
  FCM_JSON=$(python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1]))))' "$ACCOUNT_JSON_PATH")
elif command -v jq >/dev/null 2>&1; then
  FCM_JSON=$(jq -c . "$ACCOUNT_JSON_PATH")
else
  echo "[ERR] python3 또는 jq가 필요합니다." >&2
  exit 1
fi

TF_WORKDIR="/workspace/envs/$ENV_NAME"

echo "[INFO] terraform init -migrate-state (Docker, latest) in $ENV_NAME"
docker run --rm \
  -v "$ROOT_DIR":/workspace \
  -w "$TF_WORKDIR" \
  -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_DEFAULT_REGION \
  -e TF_VAR_fcm_service_account_json="$FCM_JSON" \
  hashicorp/terraform:latest init -migrate-state

echo "[INFO] terraform plan (Docker, latest) in $ENV_NAME"
docker run --rm \
  -v "$ROOT_DIR":/workspace \
  -w "$TF_WORKDIR" \
  -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_DEFAULT_REGION \
  -e TF_VAR_fcm_service_account_json="$FCM_JSON" \
  hashicorp/terraform:latest plan -input=false "$@"

echo "[OK] plan 완료 ($ENV_NAME)"


