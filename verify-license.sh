#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
API_BASE_URL="${API_BASE_URL:-http://localhost:${BACKEND_PORT:-18000}/api/v1}"
ADMIN_USERNAME="${DEFAULT_ADMIN_USERNAME:-admin}"
ADMIN_PASSWORD="${DEFAULT_ADMIN_PASSWORD:-}"

log() {
  printf '[license] %s\n' "$*"
}

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf '[license] 缺少命令：%s\n' "$1" >&2
    exit 1
  fi
}

json_get() {
  local expr="$1"
  python3 -c "import json,sys; data=json.load(sys.stdin); print(${expr})"
}

need_cmd curl
need_cmd python3

if [[ -f "${ROOT_DIR}/release-manifest.json" && -f "${ROOT_DIR}/release-manifest.sig" ]]; then
  public_key="${COMMERCIAL_MANIFEST_PUBLIC_KEY:-${COMMERCIAL_INTEGRITY_PUBLIC_KEY:-}}"
  if [[ -z "${public_key}" && -f "${ROOT_DIR}/.env" ]]; then
    public_key="$(grep '^COMMERCIAL_INTEGRITY_PUBLIC_KEY=' "${ROOT_DIR}/.env" | cut -d= -f2- || true)"
  fi
  if [[ -n "${public_key}" ]]; then
    log "校验商业 release manifest。"
    python3 "${ROOT_DIR}/tools/commercial-manifest.py" verify-release \
      --package-dir "${ROOT_DIR}" \
      --public-key "${public_key}"
  else
    log "未提供商业发布验签公钥，跳过 release manifest 校验。"
  fi
fi

log "检查后端健康：${API_BASE_URL}/health"
curl -fsS "${API_BASE_URL}/health" >/dev/null

if [[ -z "${ADMIN_PASSWORD}" ]]; then
  printf '[license] 请通过 DEFAULT_ADMIN_PASSWORD 或环境变量提供管理员密码，用于读取授权状态。\n' >&2
  exit 1
fi

login_payload="$(ADMIN_USERNAME="${ADMIN_USERNAME}" ADMIN_PASSWORD="${ADMIN_PASSWORD}" python3 - <<'PY'
import json
import os
print(json.dumps({"username": os.environ["ADMIN_USERNAME"], "password": os.environ["ADMIN_PASSWORD"]}))
PY
)"
login_response="$(curl -fsS -X POST "${API_BASE_URL}/auth/login" -H 'Content-Type: application/json' --data "${login_payload}")"
access_token="$(printf '%s' "${login_response}" | json_get "data.get('accessToken')")"
if [[ "${access_token}" == "None" || -z "${access_token}" ]]; then
  printf '[license] 登录未返回正式 access token，请确认管理员密码、默认密码强制改密或 2FA 状态。\n' >&2
  exit 1
fi

status_response="$(curl -fsS -H "Authorization: Bearer ${access_token}" "${API_BASE_URL}/license/status")"
valid="$(printf '%s' "${status_response}" | json_get "data.get('valid')")"
status="$(printf '%s' "${status_response}" | json_get "data.get('status')")"
customer="$(printf '%s' "${status_response}" | json_get "data.get('customerId')")"
expires="$(printf '%s' "${status_response}" | json_get "data.get('expiresAt')")"

log "授权状态：${status}，客户：${customer}，到期：${expires}"
if [[ "${valid}" != "True" ]]; then
  printf '%s\n' "${status_response}" >&2
  printf '[license] 当前 License 不可用。\n' >&2
  exit 1
fi

log "License 校验通过。"
