# DataFusionX Enterprise 商业交付检查清单

## 版本信息

- 版本：`0.1.0-deploy-smoke`
- 公开发布仓库：`https://github.com/Lynn-Lee/DataFusionX-Deploy`
- 公开发布水印：`public-release`
- 交付批次：`0.1.0-deploy-smoke`
- 分发模式：`public-release`
- 后端镜像：`ghcr.io/lynn-lee/datafusionx-backend:0.1.0-deploy-smoke`
- 前端镜像：`ghcr.io/lynn-lee/datafusionx-frontend:0.1.0-deploy-smoke`

## 部署前

- 已阅读 `INSTALLATION.md`。
- 已准备 Docker Compose 或 Kubernetes / Helm 环境。
- 已确认服务器可以拉取固定版本镜像。
- 已复制 `.env.example` 为 `.env` 并替换所有 `change-me` 值。
- 已准备有效 License 公钥、客户 ID、稳定部署 ID，以及在线激活码或离线 License。
- 已确认 `.env`、License 文件、激活码、Token、私钥、部署指纹和数据库连接串不会提交到公开仓库或工单。

## 发布包校验

- 已校验版本压缩包 sha256。
- 已执行 `tools/commercial-manifest.py verify-release` 校验 signed release manifest。
- 已确认 Docker Compose 和 Helm values 均使用固定版本镜像标签。

## 部署后

- 控制台首页可访问。
- `/api/v1/health` 健康检查通过。
- backend、celery-worker、cdc-guard-worker 运行正常。
- 单节点部署中 celery-beat 运行正常；多节点部署中只有主调度节点运行 celery-beat。
- 系统管理员可以登录。
- License 状态有效。
- 已修改默认管理员密码。

## 升级和回滚

- 升级前已执行 `preflight-upgrade.sh`。
- 已保存升级前备份目录位置。
- 已确认敏感备份材料不会外发。
- 已阅读 `OPERATIONS_UPGRADE.md` 中的回滚步骤。

## 产品使用

- 已创建项目。
- 已添加项目成员并分配角色。
- 已配置源端连接和目标端连接。
- 已确认外部 Kafka、Flink SQL Gateway、目标表和数据库授权由客户侧准备。
- 已阅读 `USER_GUIDE.md` 中的 CDC、Batch、SQL 作业和运行中心说明。
