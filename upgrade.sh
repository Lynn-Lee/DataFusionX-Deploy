#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${COMPOSE_FILE:-${ROOT_DIR}/deploy/docker-compose.yml}"
ENV_FILE="${ENV_FILE:-${ROOT_DIR}/.env}"
BACKUP_DIR="${BACKUP_DIR:-${ROOT_DIR}/backups/preflight-$(date +%Y%m%d%H%M%S)}"
SKIP_BACKUP="${SKIP_BACKUP:-0}"
SKIP_PULL="${SKIP_PULL:-0}"
SKIP_PREFLIGHT="${SKIP_PREFLIGHT:-0}"

log() {
  printf '[upgrade] %s\n' "$*"
}

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf '[upgrade] 缺少命令：%s\n' "$1" >&2
    exit 1
  fi
}

need_cmd docker
need_cmd python3

if [[ ! -f "${COMPOSE_FILE}" ]]; then
  printf '[upgrade] 找不到 Compose 文件：%s\n' "${COMPOSE_FILE}" >&2
  exit 1
fi

if [[ ! -f "${ENV_FILE}" ]]; then
  printf '[upgrade] 找不到环境变量文件：%s\n' "${ENV_FILE}" >&2
  exit 1
fi

if [[ -f "${ROOT_DIR}/release-manifest.json" && -f "${ROOT_DIR}/release-manifest.sig" ]]; then
  manifest_public_key="$(grep '^COMMERCIAL_INTEGRITY_PUBLIC_KEY=' "${ENV_FILE}" | cut -d= -f2- || true)"
  if [[ -n "${manifest_public_key}" ]]; then
    log "校验用户部署 release manifest。"
    python3 "${ROOT_DIR}/tools/commercial-manifest.py" verify-release \
      --package-dir "${ROOT_DIR}" \
      --public-key "${manifest_public_key}"
  else
    log "未找到 COMMERCIAL_INTEGRITY_PUBLIC_KEY，跳过 release manifest 校验。"
  fi
fi

if [[ "${SKIP_PREFLIGHT}" != "1" && "${SKIP_BACKUP}" != "1" ]]; then
  log "执行升级前检查和本机备份。"
  BACKUP_DIR="${BACKUP_DIR}" COMPOSE_FILE="${COMPOSE_FILE}" ENV_FILE="${ENV_FILE}" "${ROOT_DIR}/preflight-upgrade.sh"
elif [[ "${SKIP_BACKUP}" != "1" ]]; then
  log "跳过升级前检查，仅备份当前 Compose 配置和环境模板到 ${BACKUP_DIR}。"
  mkdir -p "${BACKUP_DIR}"
  chmod 700 "${BACKUP_DIR}"
  cp "${COMPOSE_FILE}" "${BACKUP_DIR}/docker-compose.yml"
  cp "${ENV_FILE}" "${BACKUP_DIR}/env.full.local"
  chmod 600 "${BACKUP_DIR}/env.full.local"
  sed -E 's/(PASSWORD|SECRET|TOKEN|KEY|LICENSE|FINGERPRINT|ACTIVATION)([^=]*=).*/\1\2REDACTED/g' "${ENV_FILE}" > "${BACKUP_DIR}/env.redacted"
fi

if [[ "${SKIP_PULL}" != "1" ]]; then
  log "拉取固定版本用户部署镜像。"
  docker compose -f "${COMPOSE_FILE}" --env-file "${ENV_FILE}" pull
fi

log "执行数据库迁移。"
docker compose -f "${COMPOSE_FILE}" --env-file "${ENV_FILE}" run --rm backend alembic upgrade head

log "滚动重启 DataFusionX Enterprise 服务。"
docker compose -f "${COMPOSE_FILE}" --env-file "${ENV_FILE}" up -d

log "查看服务状态。"
docker compose -f "${COMPOSE_FILE}" --env-file "${ENV_FILE}" ps

log "升级流程完成。备份目录：${BACKUP_DIR}"
log "请继续执行 ./verify-license.sh 和业务健康检查；如需回滚，使用 BACKUP_DIR='${BACKUP_DIR}' CONFIRM_ROLLBACK=1 ./rollback.sh。"
