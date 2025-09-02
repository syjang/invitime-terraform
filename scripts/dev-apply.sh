#!/usr/bin/env bash
set -euo pipefail


ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
ACCOUNT_JSON_PATH="$ROOT_DIR/invitime-account.json"
ENV_FILE="$ROOT_DIR/.env.aws"

# .env.aws가 있으면 우선 로드
if [[ -f "$ENV_FILE" ]]; then
  echo "[INFO] loading $ENV_FILE"
  set -o allexport
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +o allexport
fi

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

TF_DIR="$ROOT_DIR/envs/dev"

echo "[INFO] terraform init -migrate-state (Docker, latest)"
docker run --rm \
  -v "$ROOT_DIR":/workspace \
  -w /workspace/envs/dev \
  -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_DEFAULT_REGION \
  -e TF_VAR_fcm_service_account_json="$FCM_JSON" \
  hashicorp/terraform:latest init -migrate-state



# 선택적 타겟(-target) 인자 처리: 공백/콤마 구분 모두 허용
TARGET_ARGS=()
if [[ $# -gt 0 ]]; then
  for raw in "$@"; do
    IFS=',' read -r -a arr <<< "$raw"
    for t in "${arr[@]}"; do
      t_trimmed="${t//[[:space:]]/}"
      if [[ -n "$t_trimmed" ]]; then TARGET_ARGS+=( -target="$t_trimmed" ); fi
    done
  done
  echo "[INFO] terraform apply targets: ${TARGET_ARGS[*]}"
fi

echo "[INFO] terraform apply (Docker, latest)"
docker run --rm \
  -v "$ROOT_DIR":/workspace \
  -w /workspace/envs/dev \
  -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_DEFAULT_REGION \
  -e TF_VAR_fcm_service_account_json="$FCM_JSON" \
  hashicorp/terraform:latest apply -auto-approve ${TARGET_ARGS[@]:-}

echo "[OK] dev 배포 완료"


