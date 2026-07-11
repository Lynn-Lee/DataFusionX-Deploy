#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${COMPOSE_FILE:-${ROOT_DIR}/deploy/docker-compose.yml}"
ENV_FILE="${ENV_FILE:-${ROOT_DIR}/.env}"
BACKUP_DIR="${BACKUP_DIR:-${ROOT_DIR}/backups/preflight-$(date +%Y%m%d%H%M%S)}"
API_BASE_URL="${API_BASE_URL:-http://localhost:${BACKEND_PORT:-18000}/api/v1}"
ADMIN_USERNAME="${DEFAULT_ADMIN_USERNAME:-admin}"
ADMIN_PASSWORD="${DEFAULT_ADMIN_PASSWORD:-}"
ALLOW_RUNNING_TASKS="${ALLOW_RUNNING_TASKS:-0}"
SKIP_DB_BACKUP="${SKIP_DB_BACKUP:-0}"
SKIP_LICENSE_BACKUP="${SKIP_LICENSE_BACKUP:-0}"
SKIP_API_CHECK="${SKIP_API_CHECK:-0}"
SKIP_ACTIVE_RUN_CHECK="${SKIP_ACTIVE_RUN_CHECK:-0}"
SKIP_ALEMBIC_CHECK="${SKIP_ALEMBIC_CHECK:-0}"

log() {
  printf '[preflight-upgrade] %s\n' "$*"
}

fail() {
  printf '[preflight-upgrade] %s\n' "$*" >&2
  exit 1
}

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    fail "缺少命令：$1"
  fi
}

compose() {
  docker compose -f "${COMPOSE_FILE}" --env-file "${ENV_FILE}" "$@"
}

env_value() {
  local key="$1"
  if [[ ! -f "${ENV_FILE}" ]]; then
    return 0
  fi
  grep -E "^${key}=" "${ENV_FILE}" | tail -n1 | cut -d= -f2- | sed -E 's/^["'\'']?//; s/["'\'']?$//' || true
}

require_env_value() {
  local key="$1"
  local value
  value="$(env_value "${key}")"
  if [[ -z "${value}" || "${value}" == "change-me"* || "${value}" == *"change-me"* ]]; then
    fail "${key} 未配置或仍为 change-me。"
  fi
}

redact_env() {
  sed -E 's/(PASSWORD|SECRET|TOKEN|KEY|LICENSE|FINGERPRINT|ACTIVATION)([^=]*=).*/\1\2REDACTED/g' "$1"
}

running_service_image() {
  local service="$1"
  local container_id
  container_id="$(compose ps -q "${service}" 2>/dev/null || true)"
  if [[ -z "${container_id}" ]]; then
    return 0
  fi
  docker inspect --format '{{.Config.Image}}' "${container_id}" 2>/dev/null || true
}

image_tag() {
  local image="$1"
  local name_part
  name_part="${image##*/}"
  if [[ "${name_part}" == *:* ]]; then
    printf '%s' "${name_part##*:}"
  fi
}

replace_env_value() {
  local file="$1"
  local key="$2"
  local value="$3"
  local tmp_file
  tmp_file="$(mktemp)"
  awk -v key="${key}" -v value="${value}" '
    BEGIN { done = 0 }
    $0 ~ "^" key "=" { print key "=" value; done = 1; next }
    { print }
    END { if (done == 0) print key "=" value }
  ' "${file}" > "${tmp_file}"
  mv "${tmp_file}" "${file}"
}

write_rollback_env() {
  local rollback_env="${BACKUP_DIR}/env.rollback.local"
  local backend_image frontend_image backend_tag
  backend_image="$(running_service_image backend)"
  frontend_image="$(running_service_image frontend)"
  cp "${ENV_FILE}" "${rollback_env}"
  chmod 600 "${rollback_env}"
  if [[ -n "${backend_image}" ]]; then
    replace_env_value "${rollback_env}" DATAFUSIONX_BACKEND_IMAGE "${backend_image}"
    backend_tag="$(image_tag "${backend_image}")"
    if [[ -n "${backend_tag}" ]]; then
      replace_env_value "${rollback_env}" DATAFUSIONX_VERSION "${backend_tag}"
    fi
  fi
  if [[ -n "${frontend_image}" ]]; then
    replace_env_value "${rollback_env}" DATAFUSIONX_FRONTEND_IMAGE "${frontend_image}"
  fi
  {
    printf 'running_backend_image=%s\n' "${backend_image:-unknown}"
    printf 'running_frontend_image=%s\n' "${frontend_image:-unknown}"
    printf 'rollback_env=%s\n' "${rollback_env}"
  } > "${BACKUP_DIR}/rollback-images.txt"
  if [[ -z "${backend_image}" || -z "${frontend_image}" ]]; then
    log "未能读取当前运行镜像，env.rollback.local 将保留当前 .env 镜像值；如需降级镜像，请手工校正后再回滚。"
  fi
}

http_json() {
  local method="$1"
  local url="$2"
  local body="${3:-}"
  local token="${4:-}"
  local tmp_body tmp_code

  tmp_body="$(mktemp)"
  if [[ -n "${body}" && -n "${token}" ]]; then
    tmp_code="$(curl -sS -o "${tmp_body}" -w '%{http_code}' \
      -X "${method}" "${url}" \
      -H 'Content-Type: application/json' \
      -H "Authorization: Bearer ${token}" \
      --data "${body}")"
  elif [[ -n "${body}" ]]; then
    tmp_code="$(curl -sS -o "${tmp_body}" -w '%{http_code}' \
      -X "${method}" "${url}" \
      -H 'Content-Type: application/json' \
      --data "${body}")"
  elif [[ -n "${token}" ]]; then
    tmp_code="$(curl -sS -o "${tmp_body}" -w '%{http_code}' \
      -X "${method}" "${url}" \
      -H "Authorization: Bearer ${token}")"
  else
    tmp_code="$(curl -sS -o "${tmp_body}" -w '%{http_code}' -X "${method}" "${url}")"
  fi

  cat "${tmp_body}"
  rm -f "${tmp_body}"
  printf '\n%s' "${tmp_code}"
}

json_get() {
  local expr="$1"
  python3 -c "import json,sys; data=json.load(sys.stdin); print(${expr})"
}

check_fixed_image() {
  local key="$1"
  local value
  local forbidden_tag="latest"
  value="$(env_value "${key}")"
  if [[ -z "${value}" ]]; then
    fail "${key} 不能为空，用户部署升级必须显式固定镜像。"
  fi
  if [[ "${value}" == *":${forbidden_tag}" || "${value}" != *":"* ]]; then
    fail "${key} 必须使用固定版本标签，不能使用 latest 或无标签镜像：${value}"
  fi
}

backup_metadata_database() {
  if [[ "${SKIP_DB_BACKUP}" == "1" ]]; then
    log "已跳过 PostgreSQL 元数据库备份。"
    return
  fi

  log "备份 PostgreSQL 元数据库到 ${BACKUP_DIR}/metadata.dump。"
  if ! compose ps postgres --status running -q >/dev/null 2>&1 || [[ -z "$(compose ps postgres --status running -q)" ]]; then
    fail "postgres 服务未运行，无法执行升级前元数据库备份。"
  fi
  compose exec -T postgres pg_dump -U datafusionx -d datafusionx -Fc > "${BACKUP_DIR}/metadata.dump"
  if [[ ! -s "${BACKUP_DIR}/metadata.dump" ]]; then
    fail "元数据库备份文件为空：${BACKUP_DIR}/metadata.dump"
  fi
  compose exec -T postgres pg_restore -l < "${BACKUP_DIR}/metadata.dump" > "${BACKUP_DIR}/metadata.dump.list"
}

backup_license_volume() {
  if [[ "${SKIP_LICENSE_BACKUP}" == "1" ]]; then
    log "已跳过 License volume 备份。"
    return
  fi

  log "备份 License volume 到 ${BACKUP_DIR}/licenses.tgz。"
  if ! compose run --rm --no-deps --entrypoint sh backend -c \
    'if command -v tar >/dev/null 2>&1 && [ -d /app/licenses ]; then tar -czf - -C /app/licenses .; else exit 20; fi' \
    > "${BACKUP_DIR}/licenses.tgz"; then
    fail "License volume 备份失败，请确认后端镜像可用且包含 tar。"
  fi
}

check_active_runs() {
  if [[ "${SKIP_ACTIVE_RUN_CHECK}" == "1" ]]; then
    log "已跳过运行中任务检查。"
    printf 'skipped\n' > "${BACKUP_DIR}/active-runs.count"
    return
  fi

  log "检查运行中任务。"
  local active_count
  active_count="$(compose exec -T postgres psql -U datafusionx -d datafusionx -Atc \
    "select count(*) from job_runs where status in ('PENDING','RUNNING');" 2>/dev/null || printf '0')"
  active_count="$(printf '%s' "${active_count}" | tr -dc '0-9')"
  active_count="${active_count:-0}"
  printf '%s\n' "${active_count}" > "${BACKUP_DIR}/active-runs.count"
  if [[ "${active_count}" != "0" && "${ALLOW_RUNNING_TASKS}" != "1" ]]; then
    fail "当前存在 ${active_count} 个 PENDING/RUNNING 运行记录。请停任务或设置 ALLOW_RUNNING_TASKS=1 明确接受维护窗口风险。"
  fi
}

check_api() {
  if [[ "${SKIP_API_CHECK}" == "1" ]]; then
    log "已跳过 API 健康和 License 检查。"
    return
  fi

  need_cmd curl
  log "检查后端健康：${API_BASE_URL}/health"
  local health_response health_body health_code
  health_response="$(http_json GET "${API_BASE_URL}/health")"
  health_body="$(printf '%s' "${health_response}" | sed '$d')"
  health_code="$(printf '%s' "${health_response}" | tail -n1)"
  printf '%s\n' "${health_body}" > "${BACKUP_DIR}/health.json"
  if [[ "${health_code}" != "200" ]]; then
    fail "/health 期望 HTTP 200，实际 HTTP ${health_code}"
  fi

  if [[ -z "${ADMIN_PASSWORD}" ]]; then
    log "未提供 DEFAULT_ADMIN_PASSWORD，跳过登录态 License 检查。"
    return
  fi

  log "登录管理员并检查 License 状态。"
  local login_payload login_response login_body login_code access_token license_response license_code license_body valid
  login_payload="$(ADMIN_USERNAME="${ADMIN_USERNAME}" ADMIN_PASSWORD="${ADMIN_PASSWORD}" python3 - <<'PY'
import json
import os
print(json.dumps({"username": os.environ["ADMIN_USERNAME"], "password": os.environ["ADMIN_PASSWORD"]}))
PY
)"
  login_response="$(http_json POST "${API_BASE_URL}/auth/login" "${login_payload}")"
  login_body="$(printf '%s' "${login_response}" | sed '$d')"
  login_code="$(printf '%s' "${login_response}" | tail -n1)"
  if [[ "${login_code}" != "200" ]]; then
    printf '%s\n' "${login_body}" > "${BACKUP_DIR}/login-error.json"
    fail "管理员登录失败，HTTP ${login_code}。"
  fi
  access_token="$(printf '%s' "${login_body}" | json_get "(data.get('data') if isinstance(data, dict) and isinstance(data.get('data'), dict) else data).get('accessToken', '')")"
  if [[ -z "${access_token}" || "${access_token}" == "None" ]]; then
    fail "管理员登录未返回 accessToken。"
  fi

  license_response="$(http_json GET "${API_BASE_URL}/license/status" "" "${access_token}")"
  license_body="$(printf '%s' "${license_response}" | sed '$d')"
  license_code="$(printf '%s' "${license_response}" | tail -n1)"
  printf '%s\n' "${license_body}" > "${BACKUP_DIR}/license-status.json"
  if [[ "${license_code}" != "200" ]]; then
    fail "License 状态检查失败，HTTP ${license_code}。"
  fi
  valid="$(printf '%s' "${license_body}" | json_get "(data.get('data') if isinstance(data, dict) and isinstance(data.get('data'), dict) else data).get('valid', False)")"
  if [[ "${valid}" != "True" && "${valid}" != "true" ]]; then
    fail "当前 License 不可用，升级前必须先处理授权状态。"
  fi
}

need_cmd docker
need_cmd python3

if [[ ! -f "${COMPOSE_FILE}" ]]; then
  fail "找不到 Compose 文件：${COMPOSE_FILE}"
fi
if [[ ! -f "${ENV_FILE}" ]]; then
  fail "找不到环境变量文件：${ENV_FILE}"
fi

mkdir -p "${BACKUP_DIR}"
chmod 700 "${BACKUP_DIR}"

log "检查用户部署关键环境变量。"
require_env_value DATAFUSIONX_VERSION
require_env_value POSTGRES_PASSWORD
if ! grep -Eq '^JWT_SECRET_KEY_CURRENT=.+$' "${ENV_FILE}"; then
  require_env_value JWT_SECRET_KEY
fi
require_env_value ENCRYPTION_SECRET_KEY
require_env_value DEFAULT_ADMIN_PASSWORD
require_env_value LICENSE_PUBLIC_KEY
require_env_value LICENSE_DEPLOYMENT_ID
require_env_value COMMERCIAL_INTEGRITY_PUBLIC_KEY
check_fixed_image DATAFUSIONX_BACKEND_IMAGE
check_fixed_image DATAFUSIONX_FRONTEND_IMAGE

log "保存本机回滚配置备份。请勿把 env.full.local 发给任何第三方。"
cp "${COMPOSE_FILE}" "${BACKUP_DIR}/docker-compose.yml"
cp "${ENV_FILE}" "${BACKUP_DIR}/env.full.local"
chmod 600 "${BACKUP_DIR}/env.full.local"
write_rollback_env
redact_env "${ENV_FILE}" > "${BACKUP_DIR}/env.redacted"
{
  printf 'DATAFUSIONX_VERSION=%s\n' "$(env_value DATAFUSIONX_VERSION)"
  printf 'DATAFUSIONX_BACKEND_IMAGE=%s\n' "$(env_value DATAFUSIONX_BACKEND_IMAGE)"
  printf 'DATAFUSIONX_FRONTEND_IMAGE=%s\n' "$(env_value DATAFUSIONX_FRONTEND_IMAGE)"
} > "${BACKUP_DIR}/version.env"

log "校验 Docker Compose 配置。"
compose config --quiet
compose config > "${BACKUP_DIR}/compose.rendered.yml"
compose ps > "${BACKUP_DIR}/compose.ps.before.txt" 2> "${BACKUP_DIR}/compose.ps.before.err" || true

if [[ -f "${ROOT_DIR}/release-manifest.json" && -f "${ROOT_DIR}/release-manifest.sig" ]]; then
  log "校验用户部署 release manifest。"
  python3 "${ROOT_DIR}/tools/commercial-manifest.py" verify-release \
    --package-dir "${ROOT_DIR}" \
    --public-key "$(env_value COMMERCIAL_INTEGRITY_PUBLIC_KEY)"
fi

backup_metadata_database
backup_license_volume
check_active_runs
if [[ "${SKIP_ALEMBIC_CHECK}" == "1" ]]; then
  log "已跳过 Alembic 版本检查。"
else
  compose run --rm backend alembic current > "${BACKUP_DIR}/alembic-current.txt"
fi
check_api

cat > "${BACKUP_DIR}/preflight-summary.txt" <<EOF
DataFusionX Enterprise upgrade preflight passed.
backup_dir=${BACKUP_DIR}
compose_file=${COMPOSE_FILE}
env_file=${ENV_FILE}
version=$(env_value DATAFUSIONX_VERSION)
backend_image=$(env_value DATAFUSIONX_BACKEND_IMAGE)
frontend_image=$(env_value DATAFUSIONX_FRONTEND_IMAGE)
active_runs=$(cat "${BACKUP_DIR}/active-runs.count" 2>/dev/null || printf 'unknown')
EOF

log "升级前检查通过。备份目录：${BACKUP_DIR}"
log "可共享给支持侧的是 env.redacted、compose.rendered.yml、health.json、license-status.json 和 preflight-summary.txt（如存在）；不要共享 env.full.local、env.rollback.local、metadata.dump 或 licenses.tgz。"
