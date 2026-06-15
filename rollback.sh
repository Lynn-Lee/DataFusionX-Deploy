#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${COMPOSE_FILE:-${ROOT_DIR}/deploy/docker-compose.yml}"
ENV_FILE="${ENV_FILE:-${ROOT_DIR}/.env}"
BACKUP_DIR="${BACKUP_DIR:-}"
CONFIRM_ROLLBACK="${CONFIRM_ROLLBACK:-0}"
RESTORE_ENV="${RESTORE_ENV:-1}"
RESTORE_DB="${RESTORE_DB:-1}"
RESTORE_LICENSES="${RESTORE_LICENSES:-1}"

log() {
  printf '[rollback] %s\n' "$*"
}

fail() {
  printf '[rollback] %s\n' "$*" >&2
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

latest_backup_dir() {
  find "${ROOT_DIR}/backups" -maxdepth 1 -type d -name 'preflight-*' 2>/dev/null | sort | tail -n1
}

need_cmd docker

if [[ -z "${BACKUP_DIR}" ]]; then
  BACKUP_DIR="$(latest_backup_dir)"
fi
if [[ -z "${BACKUP_DIR}" || ! -d "${BACKUP_DIR}" ]]; then
  fail "请通过 BACKUP_DIR 指定 preflight 备份目录。"
fi
if [[ ! -f "${COMPOSE_FILE}" ]]; then
  fail "找不到 Compose 文件：${COMPOSE_FILE}"
fi
if [[ ! -f "${ENV_FILE}" ]]; then
  fail "找不到环境变量文件：${ENV_FILE}"
fi
if [[ "${CONFIRM_ROLLBACK}" != "1" ]]; then
  fail "回滚会停止应用、恢复元数据库和 License volume。确认后请设置 CONFIRM_ROLLBACK=1。"
fi

log "使用备份目录：${BACKUP_DIR}"
mkdir -p "${BACKUP_DIR}/rollback-artifacts"
compose ps > "${BACKUP_DIR}/rollback-artifacts/compose.ps.before-rollback.txt" || true
compose logs --no-color --tail=300 > "${BACKUP_DIR}/rollback-artifacts/compose.logs.before-rollback.txt" || true

if [[ "${RESTORE_ENV}" == "1" ]]; then
  rollback_env="${BACKUP_DIR}/env.rollback.local"
  if [[ ! -f "${rollback_env}" ]]; then
    rollback_env="${BACKUP_DIR}/env.full.local"
  fi
  if [[ ! -f "${rollback_env}" ]]; then
    fail "缺少 ${BACKUP_DIR}/env.rollback.local 或 env.full.local，无法自动恢复上一版环境变量。"
  fi
  log "恢复上一版本机 .env。"
  cp "${ENV_FILE}" "${BACKUP_DIR}/rollback-artifacts/env.before-rollback.local"
  chmod 600 "${BACKUP_DIR}/rollback-artifacts/env.before-rollback.local"
  cp "${rollback_env}" "${ENV_FILE}"
  chmod 600 "${ENV_FILE}"
fi

log "停止应用服务，保留 PostgreSQL 和 Redis。"
compose stop backend celery-worker celery-beat cdc-guard-worker frontend >/dev/null 2>&1 || true
compose up -d postgres redis

if [[ "${RESTORE_DB}" == "1" ]]; then
  if [[ ! -s "${BACKUP_DIR}/metadata.dump" ]]; then
    fail "缺少元数据库备份：${BACKUP_DIR}/metadata.dump"
  fi
  log "恢复 PostgreSQL 元数据库。"
  compose exec -T postgres pg_isready -U datafusionx -d datafusionx >/dev/null
  compose exec -T postgres psql -U datafusionx -d postgres -v ON_ERROR_STOP=1 <<'SQL'
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE datname = 'datafusionx' AND pid <> pg_backend_pid();
DROP DATABASE IF EXISTS datafusionx;
CREATE DATABASE datafusionx OWNER datafusionx;
SQL
  compose exec -T postgres pg_restore -U datafusionx -d datafusionx --no-owner < "${BACKUP_DIR}/metadata.dump"
fi

if [[ "${RESTORE_LICENSES}" == "1" ]]; then
  if [[ -s "${BACKUP_DIR}/licenses.tgz" ]]; then
    log "恢复 License volume。"
    compose run --rm --no-deps --entrypoint sh backend -c \
      'rm -rf /app/licenses/* && tar -xzf - -C /app/licenses' < "${BACKUP_DIR}/licenses.tgz"
  else
    log "未找到 licenses.tgz，跳过 License volume 恢复。"
  fi
fi

log "启动回滚后的 DataFusionX Enterprise 服务。"
compose up -d
compose ps > "${BACKUP_DIR}/rollback-artifacts/compose.ps.after-rollback.txt" || true

log "回滚流程完成。请继续执行 ./verify-license.sh，并检查登录、项目列表、任务列表和运行中心。"
