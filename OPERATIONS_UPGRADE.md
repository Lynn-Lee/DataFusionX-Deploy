# DataFusionX Enterprise 运维与升级指南

当前发布版本：`0.1.0-deploy-smoke`

本文面向负责 DataFusionX Enterprise 日常运维、升级、备份、回滚和故障排查的管理员。

## 1. 日常巡检

建议每天至少检查一次服务状态：

```bash
docker compose -f deploy/docker-compose.yml --env-file .env ps
curl -fsS http://localhost:18000/api/v1/health
```

重点关注：

- `frontend` 是否可访问。
- `backend` 健康检查是否通过。
- `celery-worker` 是否运行。
- `cdc-guard-worker` 是否运行。
- `celery-beat` 是否只在单一调度节点运行。
- PostgreSQL 和 Redis 是否可用。
- License 状态是否有效。
- 运行中心是否存在长时间卡住的运行实例。
- 诊断中心是否存在高风险任务、连接或容量风险。
- 告警通知渠道是否可发送测试消息。

## 2. 控制台巡检入口

推荐按以下顺序巡检：

1. 概览看板：查看项目成功率、失败运行、DDL 阻断、未确认告警和 Flink 容量。
2. 运行中心：查看近期待处理运行、失败分类、Flink Job、Kafka lag 和日志。
3. 诊断中心：查看高风险对象、待闭环动作和稳定性趋势。
4. DDL 卫士：确认结构变更阻断是否已处理。
5. 告警列表：确认告警是否已分派、确认或恢复。
6. 审计日志：核对关键变更、审批和调度启停记录。

## 3. 查看日志

Docker Compose：

```bash
docker compose -f deploy/docker-compose.yml --env-file .env logs --tail=200 backend
docker compose -f deploy/docker-compose.yml --env-file .env logs --tail=200 celery-worker
docker compose -f deploy/docker-compose.yml --env-file .env logs --tail=200 cdc-guard-worker
docker compose -f deploy/docker-compose.yml --env-file .env logs --tail=200 celery-beat
```

Kubernetes：

```bash
kubectl logs deploy/datafusionx-backend --tail=200
kubectl logs deploy/datafusionx-celery-worker --tail=200
kubectl logs deploy/datafusionx-cdc-guard-worker --tail=200
kubectl logs deploy/datafusionx-celery-beat --tail=200
```

共享日志前请先脱敏，不要包含 `.env`、License 文件、激活码、Token、私钥、部署指纹、数据库连接串或客户现场拓扑。

## 4. 备份策略

升级、迁移或重大配置变更前必须备份：

- PostgreSQL 元数据库。
- License volume。
- 当前 `.env` 的脱敏快照和回滚所需本地副本。
- 当前部署包、镜像版本和 release manifest。

备份文件应保存到受控目录，并按企业备份策略纳入保留和恢复演练。

## 5. 升级前检查

执行：

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

升级前还应在控制台确认：

- 没有关键任务处于不可中断运行窗口。
- 运行中心无未知状态的任务。
- 告警渠道可用。
- 回滚负责人和业务确认窗口已确定。

## 6. 执行升级

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

控制台内验证：

- 登录成功。
- 系统健康正常。
- License 状态有效。
- 项目列表、连接管理、任务同步、SQL 作业、调度视图、运行中心、诊断中心可打开。
- 最近一条运行记录可查看日志和详情。

## 7. 回滚

使用升级前检查生成的备份目录：

```bash
BACKUP_DIR='./backups/preflight-<时间戳>' CONFIRM_ROLLBACK=1 ./rollback.sh
DEFAULT_ADMIN_PASSWORD='<管理员密码>' ./verify-license.sh
```

回滚后确认：

- 控制台可访问。
- 后端健康检查通过。
- License 状态有效。
- PostgreSQL 元数据恢复到预期版本。
- 运行中心无异常卡死任务。
- 调度状态符合回滚前业务预期。

如果回滚后仍异常，请保留现场日志、备份目录和 release manifest，不要继续多次覆盖部署。

## 8. 多节点调度注意事项

DataFusionX Enterprise 的周期任务由 Celery Beat 负责调度。多 app 节点或 HA 部署中只能保留一个调度节点运行 `celery-beat`；非主节点必须保持 `celery-beat` stopped / disabled。Redis 锁只是防重复派发的兜底保护，不能作为允许多个 Beat 常驻运行的理由。

巡检时请确认：

```bash
docker compose -f deploy/docker-compose.yml --env-file .env ps | grep celery-beat
```

Kubernetes 或 systemd 部署请使用对应平台命令确认只有一个 Beat 实例处于 Running / enabled 状态。

## 9. 故障排查路径

登录失败：

- 检查前端是否可访问。
- 检查后端健康和日志。
- 检查管理员账号、密码和外部身份配置。

功能受限：

- 检查 License 状态、功能项、额度和有效期。
- 检查用户项目角色和资源级授权。

任务无法启动：

- 检查执行计划是否已审批。
- 检查连接连通性和 catalog。
- 检查 Flink SQL Gateway、Kafka、源端和目标端。
- 检查 DDL 卫士是否存在未确认阻断。

运行失败：

- 先看运行中心失败分类和日志。
- 再看诊断中心聚合线索。
- 最后按外部 Flink、Kafka、数据库和网络链路继续排查。

## 10. 对外排查材料

可以共享：

- `env.redacted`
- `compose.rendered.yml`
- `health.json`
- `license-status.json`
- `preflight-summary.txt`
- 已脱敏的后端、Worker 和前端错误日志
- 已脱敏的运行中心截图或诊断中心截图

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
