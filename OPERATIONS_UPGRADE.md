# DataFusionX Enterprise 运维与升级指南

当前发布版本：`2.0`

本文面向负责 DataFusionX Enterprise 日常运维、升级、备份、回滚和故障排查的管理员。所有命令默认在部署目录执行，也就是包含 `.env`、`deploy/docker-compose.yml`、`preflight-upgrade.sh`、`upgrade.sh` 和 `rollback.sh` 的目录。

## 1. 日常巡检

建议每天至少巡检一次服务和控制台状态。

### 1.1 命令行巡检

```bash
docker compose -f deploy/docker-compose.yml --env-file .env ps
curl -fsS http://localhost:18000/api/v1/health
```

预期结果：

- `frontend`、`backend`、`celery-worker`、`cdc-guard-worker`、`celery-beat`、`postgres`、`redis` 均处于 `running` 或 `Up` 状态。
- `/api/v1/health` 返回健康 JSON。
- 单节点部署中 `celery-beat` 正常运行；多 app 节点或 HA 部署中只有一个 `celery-beat` 常驻运行。

如果使用外部 PostgreSQL / Redis 或 Kubernetes，请按实际平台替换状态检查命令，但巡检对象保持一致：前端、后端、Worker、Beat、元数据库、Redis、授权和商业完整性。

### 1.2 控制台巡检

推荐按以下顺序巡检：

1. 概览看板：查看项目成功率、失败运行、DDL 阻断、未确认告警和 Flink 容量。
2. 运行中心：查看近期待处理运行、失败分类、Flink Job、Kafka lag 和日志。
3. 诊断中心：查看高风险对象、待闭环动作和稳定性趋势。
4. DDL 卫士：确认结构变更阻断是否已处理。
5. 告警列表：确认告警是否已分派、确认或恢复。
6. 审计日志：核对关键变更、审批和调度启停记录。
7. 系统健康：确认授权、商业完整性、Worker、Beat、PostgreSQL、Redis 和通知渠道。

## 2. 查看日志

Docker Compose：

```bash
docker compose -f deploy/docker-compose.yml --env-file .env logs --tail=200 backend
docker compose -f deploy/docker-compose.yml --env-file .env logs --tail=200 celery-worker
docker compose -f deploy/docker-compose.yml --env-file .env logs --tail=200 cdc-guard-worker
docker compose -f deploy/docker-compose.yml --env-file .env logs --tail=200 celery-beat
docker compose -f deploy/docker-compose.yml --env-file .env logs --tail=200 frontend
```

持续跟踪日志：

```bash
docker compose -f deploy/docker-compose.yml --env-file .env logs -f --tail=100 backend
```

Kubernetes：

```bash
kubectl logs deploy/datafusionx-backend --tail=200
kubectl logs deploy/datafusionx-celery-worker --tail=200
kubectl logs deploy/datafusionx-cdc-guard-worker --tail=200
kubectl logs deploy/datafusionx-celery-beat --tail=200
```

共享日志前请先脱敏，不要包含 `.env`、授权文件、激活码、Token、私钥、部署指纹、数据库连接串或客户现场拓扑。

## 3. 备份策略

升级、迁移或重大配置变更前必须备份：

- PostgreSQL 元数据库。
- License volume。
- 当前 `.env` 的本地完整副本和脱敏副本。
- 当前部署包、镜像版本、release manifest 和镜像 digest。
- 反向代理、Ingress、企业 Secret、监控告警等外部配置。

`preflight-upgrade.sh` 会自动生成一次升级前备份，默认目录为：

```text
backups/preflight-<时间戳>/
```

关键文件说明：

| 文件 | 用途 | 是否可共享 |
| --- | --- | --- |
| `preflight-summary.txt` | 升级前检查摘要 | 可共享 |
| `env.redacted` | 脱敏后的环境变量 | 可共享 |
| `compose.rendered.yml` | 渲染后的 Compose 配置，仍需复核是否含敏感值 | 谨慎共享 |
| `health.json` | 后端健康检查结果 | 可共享 |
| `license-status.json` | 授权状态结果，需确认无敏感字段 | 谨慎共享 |
| `env.full.local` | 完整 `.env` 备份 | 不可共享 |
| `env.rollback.local` | 回滚用 `.env` | 不可共享 |
| `metadata.dump` | PostgreSQL 元数据库备份 | 不可共享 |
| `licenses.tgz` | License volume 备份 | 不可共享 |

备份目录应保存到受控位置，并纳入企业备份保留和恢复演练。

## 4. 升级前检查

升级前先确认维护窗口：

- 没有关键任务处于不可中断运行窗口。
- 运行中心没有未知状态或长期卡住的运行实例。
- 告警通知渠道可用。
- 回滚负责人、业务确认人和变更窗口已确定。
- 新版本镜像已经可拉取，或离线镜像已导入。

执行升级前检查：

```bash
DEFAULT_ADMIN_PASSWORD='<管理员密码>' ./preflight-upgrade.sh
```

如果管理员账号不是默认 `admin`，同时传入账号：

```bash
DEFAULT_ADMIN_USERNAME='<管理员账号>' DEFAULT_ADMIN_PASSWORD='<管理员密码>' ./preflight-upgrade.sh
```

脚本会检查和执行：

- 用户部署关键环境变量是否仍为 `change-me`。
- 后端和前端镜像是否使用固定版本标签。
- Docker Compose 配置是否可渲染。
- 用户部署 release manifest 签名是否可校验。
- PostgreSQL 元数据库备份。
- License volume 备份。
- 当前运行中任务数量。
- Alembic 当前版本。
- 后端健康状态。
- 管理员登录和授权状态。

预期结果：终端出现 `升级前检查通过`，并输出备份目录。

如果存在运行中任务，脚本会阻断升级。请优先停任务或等待运行结束；如果业务已经确认维护窗口风险，可显式设置：

```bash
ALLOW_RUNNING_TASKS=1 DEFAULT_ADMIN_PASSWORD='<管理员密码>' ./preflight-upgrade.sh
```

只有在已确认业务影响时才使用 `ALLOW_RUNNING_TASKS=1`。

## 5. 执行升级

升级前编辑 `.env`，把版本和镜像引用改成目标版本：

```text
DATAFUSIONX_VERSION=2.0
DATAFUSIONX_BACKEND_IMAGE=ghcr.io/lynn-lee/datafusionx-backend:2.0
DATAFUSIONX_FRONTEND_IMAGE=ghcr.io/lynn-lee/datafusionx-frontend:2.0
```

生产环境必须使用固定版本标签，不要使用 `latest` 或无标签镜像。

执行升级：

```bash
DEFAULT_ADMIN_PASSWORD='<管理员密码>' ./upgrade.sh
```

脚本会按顺序执行：

1. 校验用户部署 release manifest。
2. 调用 `preflight-upgrade.sh` 做升级前检查和备份。
3. 拉取固定版本镜像。
4. 执行 `backend alembic upgrade head`。
5. `docker compose up -d` 滚动重启服务。
6. 输出服务状态和备份目录。

如果已经单独执行过 preflight，并希望复用同一个备份目录：

```bash
BACKUP_DIR='./backups/preflight-<时间戳>' DEFAULT_ADMIN_PASSWORD='<管理员密码>' ./upgrade.sh
```

如果公网受限且镜像已提前导入，可跳过拉取：

```bash
SKIP_PULL=1 DEFAULT_ADMIN_PASSWORD='<管理员密码>' ./upgrade.sh
```

不建议跳过 preflight。只有在应急场景且已经手工完成备份和检查时，才使用：

```bash
SKIP_PREFLIGHT=1 DEFAULT_ADMIN_PASSWORD='<管理员密码>' ./upgrade.sh
```

## 6. 升级后验证

升级完成后立即执行：

```bash
docker compose -f deploy/docker-compose.yml --env-file .env ps
curl -fsS http://localhost:18000/api/v1/health
DEFAULT_ADMIN_PASSWORD='<管理员密码>' ./verify-license.sh
```

如果首次登录后已改密：

```bash
DEFAULT_ADMIN_USERNAME='<管理员账号>' DEFAULT_ADMIN_PASSWORD='<新管理员密码>' ./verify-license.sh
```

控制台内验证：

- 登录成功。
- 系统健康正常。
- 授权状态有效或仍处于 180 天试用期内。
- 项目列表、连接管理、任务同步、SQL 作业、调度视图、运行中心、诊断中心可打开。
- 最近一条运行记录可查看日志和详情。
- 告警通知测试可发送。
- 审计日志能看到本次升级前后的关键操作记录。

升级验收通过后，记录：

- 升级版本。
- 后端和前端镜像标签或 digest。
- 备份目录。
- 健康检查结果。
- 验收人和验收时间。

## 7. 回滚

回滚会恢复上一版 `.env`、PostgreSQL 元数据库和 License volume。回滚前先保留现场：

```bash
docker compose -f deploy/docker-compose.yml --env-file .env ps
docker compose -f deploy/docker-compose.yml --env-file .env logs --no-color --tail=300 > rollback-before.log
```

使用指定备份目录回滚：

```bash
BACKUP_DIR='./backups/preflight-<时间戳>' CONFIRM_ROLLBACK=1 ./rollback.sh
```

如果不指定 `BACKUP_DIR`，脚本会尝试使用 `backups/` 下最新的 `preflight-*` 目录。生产环境建议显式指定，避免误用备份目录。

回滚后验证：

```bash
docker compose -f deploy/docker-compose.yml --env-file .env ps
curl -fsS http://localhost:18000/api/v1/health
DEFAULT_ADMIN_PASSWORD='<管理员密码>' ./verify-license.sh
```

控制台内确认：

- 控制台可访问。
- 后端健康检查通过。
- 授权状态有效。
- PostgreSQL 元数据恢复到预期版本。
- 项目列表、任务列表、运行中心和审计日志符合回滚预期。
- 调度状态符合回滚前业务确认结果。

如果回滚后仍异常，请保留现场日志、备份目录和 release manifest，不要继续多次覆盖部署。

## 8. 多节点调度注意事项

DataFusionX Enterprise 的周期任务由 Celery Beat 负责调度。多 app 节点或 HA 部署中只能保留一个调度节点运行 `celery-beat`；非主节点必须保持 `celery-beat` stopped / disabled。Redis 锁只是防重复派发的兜底保护，不能作为允许多个 Beat 常驻运行的理由。

Docker Compose 巡检：

```bash
docker compose -f deploy/docker-compose.yml --env-file .env ps | grep celery-beat
```

Kubernetes 巡检：

```bash
kubectl get deploy | grep celery-beat
kubectl get pods | grep celery-beat
```

预期结果：生产调度域内只有一个 Beat 实例处于 Running / enabled 状态。

发布脚本在重建服务前会先优雅停止 `celery-worker`、`cdc-guard-worker` 和 `celery-beat`。如果日志时间点正好落在发布窗口，少量 `SIGTERM`、`WorkerLostError` 或 worker warm shutdown 记录通常表示容器被部署流程停止，不应单独视为运行故障。发布后请用下面的口径复核：

```bash
docker compose -f deploy/docker-compose.yml --env-file .env logs --since=10m celery-worker cdc-guard-worker celery-beat | grep -E 'ERROR|WorkerLostError|Traceback' || true
```

预期结果：重启后无新增 ERROR；如仍持续出现非发布窗口内的 `WorkerLostError`、`Traceback` 或任务失败日志，再按运行失败路径排查。

## 9. 故障排查路径

### 9.1 登录失败

先检查：

```bash
curl -fsS http://localhost:18000/api/v1/health
docker compose -f deploy/docker-compose.yml --env-file .env logs --tail=200 backend
```

再确认：

- 管理员账号和密码是否正确。
- 首次登录是否已触发强制改密。
- 2FA 或外部身份配置是否影响登录。
- 反向代理是否正确转发 API 请求。

### 9.2 功能受限

先执行：

```bash
DEFAULT_ADMIN_PASSWORD='<管理员密码>' ./verify-license.sh
```

再确认：

- 授权是否有效、过期、吊销或额度不足。
- 当前用户是否有项目角色。
- 是否配置了资源级授权导致按钮不可用。

### 9.3 任务无法启动

按顺序检查：

1. 执行计划是否已发布并由项目 `admin` 审批。
2. 连接连通性和 catalog 校验是否通过。
3. Flink SQL Gateway、Kafka、源端、目标端和目标表是否可访问。
4. 关系型目标端 CDC 是否具备兼容主键或唯一约束。
5. DDL 卫士是否存在未确认阻断。

### 9.4 运行失败

按顺序处理：

1. 在运行中心查看失败分类、运行日志、步骤日志、最终 SQL 和 Flink Job 状态。
2. 在诊断中心查看聚合线索、容量风险和待闭环动作。
3. 检查外部 Flink、Kafka、数据库和网络链路。
4. 将处理结论、证据和下一步写回运行诊断或运维记录。

## 10. 对外排查材料

可以共享：

- `env.redacted`
- `compose.rendered.yml`，共享前再次确认无敏感信息
- `health.json`
- `license-status.json`，共享前再次确认无敏感信息
- `preflight-summary.txt`
- 已脱敏的后端、Worker 和前端错误日志
- 已脱敏的运行中心截图或诊断中心截图

不得共享：

- `.env`
- `env.full.local`
- `env.rollback.local`
- `metadata.dump`
- `licenses.tgz`
- 授权文件
- 激活码
- Token
- 私钥
- 数据库连接串
- 客户部署指纹
- 现场拓扑
