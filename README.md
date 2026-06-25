# DataFusionX Enterprise

DataFusionX Enterprise 是面向企业 IT、DBA、数据开发和运维团队的私有化数据同步控制台。本仓库是用户下载、部署和升级 DataFusionX Enterprise 的公开入口，包含固定版本部署编排、Helm Chart、校验工具、运维脚本、产品文档和功能截图。

当前发布版本：`1.1.2`

## 项目定位

DataFusionX Enterprise 聚焦企业数据同步“控制面”：把连接管理、CDC / Batch 任务配置、SQL 作业治理、执行计划审批、调度、运行观测、诊断、DDL 变更处理、审计和授权管理统一到一个可交付、可审计、可运维的平台中。

平台不托管生产数据面资源，不自动创建 Kafka Topic、Debezium Connector、TiCDC Changefeed、Flink 集群、生产目标表或数据库授权 SQL。源端、目标端、Kafka、Flink SQL Gateway 和目标表仍由企业现有数据平台、DBA 或运维团队按内部规范准备；DataFusionX Enterprise 负责读取配置、生成执行计划、提交外部 Flink SQL 作业并持续观测运行状态。

部署时需要在 `.env` 中配置外部 Flink SQL Gateway 和 Flink REST 地址；CDC 任务的 Kafka Bootstrap Servers 和 Topic 在任务表单中逐任务填写。Flink Connector jar、JDBC Driver、MinIO/S3 checkpoint、savepoint、HA storage 以及 Debezium / Canal / TiCDC 等外部 CDC 引擎由客户数据平台维护，DataFusionX Enterprise 不上传 jar、不托管 MinIO，也不创建外部运行时资源。

## 核心能力

- 项目治理：项目隔离、成员角色、资源级授权、配置导入导出和审计留痕。
- 连接管理：统一维护 MySQL、TiDB、PostgreSQL、Oracle、SQL Server、StarRocks 等源端和目标端连接，支持连通性检查和 catalog 校验。
- 任务同步：支持 CDC 与 Batch，同步任务保持一表一任务、一表一执行计划、一表一运行观测。
- SQL 作业：支持单 SQL 和多步骤串行跑批，提供参数冻结、输入输出资产声明、发布审批、调度和结果预览。
- 审批与调度：执行计划审批通过后才允许启动、部署或启用调度；支持 Once、指定时间、Cron 和补跑。
- 运行观测：运行中心统一展示 CDC、Batch 和 SQL 作业运行记录、Flink Job 状态、日志、指标、告警和一致性校验。
- DDL 卫士：对 CDC DDL 事件和 Batch catalog drift 做阻断、确认和审计，避免未确认结构变更进入生产链路。
- 诊断中心：聚合失败分类、稳定性趋势、容量风险和待闭环动作，辅助运维排障和投产复核。
- 平台治理：系统健康、系统配置、兼容矩阵、告警通知、商业授权和升级回滚工具链。

## 最短部署路径

适合 Docker Compose 单节点试用、PoC 或小规模生产。正式生产部署前请完整阅读 [安装部署指南](INSTALLATION.md)。

```bash
git clone https://github.com/Lynn-Lee/DataFusionX-Deploy.git
cd DataFusionX-Deploy
cp .env.example .env
```

编辑 `.env`，至少检查并填妥以下字段：

```text
POSTGRES_PASSWORD
JWT_SECRET_KEY
ENCRYPTION_SECRET_KEY
DEFAULT_ADMIN_PASSWORD
LICENSE_PUBLIC_KEY
LICENSE_CUSTOMER_ID
LICENSE_DEPLOYMENT_ID
COMMERCIAL_INTEGRITY_PUBLIC_KEY
DATAFUSIONX_PUBLIC_URL
```

可用下面命令快速生成密钥值：

```bash
openssl rand -base64 32
```

启动前确认没有遗留占位值：

```bash
grep -nE 'change-me|^LICENSE_PUBLIC_KEY=$|^LICENSE_CUSTOMER_ID=$|^COMMERCIAL_INTEGRITY_PUBLIC_KEY=$' .env
```

上面命令没有输出，才继续启动：

```bash
docker compose -f deploy/docker-compose.yml --env-file .env config --quiet
docker compose -f deploy/docker-compose.yml --env-file .env pull
docker compose -f deploy/docker-compose.yml --env-file .env up -d
docker compose -f deploy/docker-compose.yml --env-file .env ps
curl -fsS http://localhost:18000/api/v1/health
```

默认访问地址：

- 控制台：`http://localhost:8080`
- 后端健康检查：`http://localhost:18000/api/v1/health`

如果部署在服务器上，请把 `localhost` 替换成服务器内网地址、域名或反向代理地址，并确保 `.env` 中的 `DATAFUSIONX_PUBLIC_URL` 与用户浏览器实际访问地址一致。

## 文档入口

- [安装部署指南](INSTALLATION.md)：从环境准备、`.env` 配置、Docker Compose / Helm 部署到首次登录验证。
- [产品使用手册](USER_GUIDE.md)：从系统初始化到项目、连接、任务、审批、调度、运行中心和投产检查。
- [运维升级指南](OPERATIONS_UPGRADE.md)：日常巡检、日志、备份、升级、回滚和故障排查。
- [私有化部署方案](COMMERCIAL_DEPLOYMENT.md)：部署形态、交付内容、上线检查和安全边界。
- [使用授权](LEGAL-NOTICE.md)：试用和继续使用授权说明。

## 核心功能截图

### 概览看板

![概览看板](screenshots/dashboard-overview.png)

### 连接管理

![连接管理](screenshots/connections.png)

### 任务同步

![任务同步](screenshots/sync-jobs.png)

### SQL 作业

![SQL 作业](screenshots/sql-jobs.png)

### DDL 卫士

![DDL 卫士](screenshots/ddl-guard.png)

### 运行中心

![运行中心](screenshots/run-center.png)

### 诊断中心

![诊断中心](screenshots/diagnostics-overview.png)

### 调度视图

![调度视图](screenshots/schedule-view.png)

## 发布包校验

如果下载 `releases/v1.1.2/DataFusionX-Enterprise-v1.1.2.tar.gz` 固定版本包，请先校验 sha256：

```bash
shasum -a 256 -c releases/v1.1.2/DataFusionX-Enterprise-v1.1.2.tar.gz.sha256
```

正式发布包内会随版本生成 `release-manifest.json` 和 `release-manifest.sig`，用于发布流程和交付归档校验。文档或截图单独更新时不应手工伪造重签发布 manifest。

## 镜像

- 后端 / Worker / Beat：`ghcr.io/lynn-lee/datafusionx-backend:1.1.2`
- 前端：`ghcr.io/lynn-lee/datafusionx-frontend:1.1.2`

生产环境不要使用 `latest`，请保留 `.env.example`、Docker Compose 和 Helm values 中的明确版本标签。
