# DataFusionX Enterprise 运维与升级指南

当前发布版本：`0.1.0-deploy-smoke`

本文面向负责 DataFusionX Enterprise 日常运维、升级、备份和回滚的管理员。

## 日常健康检查

```bash
docker compose -f deploy/docker-compose.yml --env-file .env ps
curl -fsS http://localhost:18000/api/v1/health
```

需要重点关注：

- backend 是否健康。
- celery-worker 是否运行。
- cdc-guard-worker 是否运行。
- celery-beat 是否只在单一调度节点运行。
- PostgreSQL 和 Redis 是否可用。
- License 状态是否有效。

## 查看日志

```bash
docker compose -f deploy/docker-compose.yml --env-file .env logs --tail=200 backend
docker compose -f deploy/docker-compose.yml --env-file .env logs --tail=200 celery-worker
docker compose -f deploy/docker-compose.yml --env-file .env logs --tail=200 cdc-guard-worker
```

共享日志前请先脱敏，不要包含 `.env`、License 文件、激活码、Token、私钥、部署指纹、数据库连接串或客户现场拓扑。

## 升级前检查

```bash
DEFAULT_ADMIN_PASSWORD='<管理员密码>' ./preflight-upgrade.sh
```

脚本会检查：

- 固定版本镜像。
- Compose 配置。
- release manifest 签名。
- 后端健康状态。
- License 状态。
- PostgreSQL 元数据库备份。
- License volume 备份。
- 运行中任务状态。

`backups/preflight-<时间戳>/env.full.local`、`env.rollback.local`、`metadata.dump` 和 `licenses.tgz` 是敏感材料，不得上传到公开仓库、公开工单或聊天群。

## 执行升级

升级时复用上一版本 `.env`，只更新版本和镜像引用：

```text
DATAFUSIONX_VERSION=0.1.0-deploy-smoke
DATAFUSIONX_BACKEND_IMAGE=ghcr.io/lynn-lee/datafusionx-backend:0.1.0-deploy-smoke
DATAFUSIONX_FRONTEND_IMAGE=ghcr.io/lynn-lee/datafusionx-frontend:0.1.0-deploy-smoke
```

执行：

```bash
DEFAULT_ADMIN_PASSWORD='<管理员密码>' ./upgrade.sh
DEFAULT_ADMIN_PASSWORD='<管理员密码>' ./verify-license.sh
```

升级后验证：

```bash
curl -fsS http://localhost:18000/api/v1/health
docker compose -f deploy/docker-compose.yml --env-file .env ps
```

## 回滚

使用升级前检查生成的备份目录：

```bash
BACKUP_DIR='./backups/preflight-<时间戳>' CONFIRM_ROLLBACK=1 ./rollback.sh
DEFAULT_ADMIN_PASSWORD='<管理员密码>' ./verify-license.sh
```

回滚后确认：

- 控制台可访问。
- 后端健康检查通过。
- License 状态有效。
- 运行中心无异常卡死任务。

## 多节点调度注意事项

DataFusionX Enterprise 的周期任务由 Celery Beat 负责调度。多 app 节点或 HA 部署中只能保留一个调度节点运行 `celery-beat`；非主节点必须保持 `celery-beat` stopped / disabled。Redis 锁只是防重复派发的兜底保护，不能作为允许多个 Beat 常驻运行的理由。

## 对外排查材料

可以共享：

- `env.redacted`
- `compose.rendered.yml`
- `health.json`
- `license-status.json`
- `preflight-summary.txt`

不得共享：

- `.env`
- `env.full.local`
- `env.rollback.local`
- License 文件
- 激活码
- Token
- 私钥
- 数据库连接串
- 客户部署指纹
- 现场拓扑
