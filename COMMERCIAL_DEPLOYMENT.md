# DataFusionX Enterprise 私有化部署方案

> 文档状态：L1 商业私有化部署方案。本文面向客户、实施和运维团队，说明 DataFusionX Enterprise 在企业内网、测试环境、预生产和生产环境中的推荐部署方式、交付内容、上线检查和运维边界。

DataFusionX Enterprise 是面向企业 IT、DBA、数据开发和运维团队的数据同步控制台。私有化部署包只包含固定版本商业镜像引用、Docker Compose 编排、Helm Chart、环境变量模板、校验工具、升级回滚脚本、用户文档和截图材料，不交付后端源码、前端源码、构建私钥、授权中心源码或客户专属授权。

## 1. 部署目标

私有化部署的目标是让客户在自己的服务器、虚拟机或 Kubernetes 集群中运行 DataFusionX Enterprise 控制面，并对接客户已有的数据面资源：

- 源端数据库：MySQL、TiDB、PostgreSQL、Oracle、SQL Server。
- 目标端：StarRocks、MySQL、TiDB、PostgreSQL、Oracle、SQL Server。
- 外部运行时：Kafka、Flink 集群、Flink SQL Gateway、Debezium、Canal 或 TiCDC。
- 企业治理：LDAP、OIDC、CAS、钉钉、飞书、企业微信、Slack、邮件、Webhook、Alertmanager。

DataFusionX Enterprise 不创建 Kafka Topic、Debezium Connector、TiCDC Changefeed、Flink 集群、生产目标表或数据库授权 SQL；这些资源仍由客户现有平台、DBA 或运维团队准备和维护。

## 2. 交付内容

公开部署仓库 `Lynn-Lee/DataFusionX-Deploy` 是用户下载和部署入口。根目录保存最新稳定部署入口，`releases/v<version>/` 保存历史版本压缩包和 sha256 文件。

交付包通常包含：

```text
DataFusionX-Enterprise-v<version>/
  .env.example
  README.md
  INSTALLATION.md
  USER_GUIDE.md
  OPERATIONS_UPGRADE.md
  COMMERCIAL_DEPLOYMENT.md
  LEGAL-NOTICE.md
  deploy/docker-compose.yml
  helm/datafusionx-commercial/
  nginx/datafusionx-commercial.conf
  tools/commercial-manifest.py
  preflight-upgrade.sh
  upgrade.sh
  rollback.sh
  verify-license.sh
  screenshots/
  checksums.txt
  release-manifest.json
  release-manifest.sig
  releases/v<version>/DataFusionX-Enterprise-v<version>.tar.gz
  releases/v<version>/DataFusionX-Enterprise-v<version>.tar.gz.sha256
```

离线交付时可额外提供镜像 tar 包：

```text
images/
  datafusionx-backend-commercial-<version>.tar
  datafusionx-frontend-commercial-<version>.tar
```

## 3. 推荐部署形态

| 部署形态 | 适用场景 | 说明 |
| --- | --- | --- |
| Docker Compose 单节点 | 试用、PoC、小规模生产、客户内网快速落地 | 包含 Frontend、Backend、Worker、Beat、CDC Guard、PostgreSQL、Redis。 |
| Docker Compose + 外部 PostgreSQL / Redis | 中小规模生产 | 控制面服务仍由 Compose 管理，元数据库和缓存接入客户已有基础设施。 |
| Kubernetes + Helm | 标准生产、统一容器平台、多环境交付 | 使用随包 Helm Chart 部署，便于接入 Ingress、Secret、PVC、监控和企业镜像仓库。 |
| 离线镜像部署 | 无法访问公网或 GHCR 的环境 | 由交付方提供镜像 tar，客户先 `docker load` 或导入私有镜像仓库。 |

无论使用哪种形态，多 app 节点或 HA 部署中只能保留一个调度节点运行 `celery-beat`；非主节点必须保持 `celery-beat` stopped / disabled。Redis 锁只是防重复派发的兜底保护，不能作为允许多个 Beat 常驻运行的理由。

## 4. 部署前准备

服务器或集群需要提前准备：

- Docker Engine + Docker Compose v2，或 Kubernetes + Helm 3。
- 可访问固定版本镜像，或已导入离线镜像 tar。
- 可用端口：默认前端 `8080`，后端 `18000`，PostgreSQL `15432`，Redis `16379`。
- 稳定访问域名或内网地址，并将 `DATAFUSIONX_PUBLIC_URL` 配置为用户浏览器实际访问地址。
- 生产随机密钥：`POSTGRES_PASSWORD`、`JWT_SECRET_KEY`、`ENCRYPTION_SECRET_KEY`、管理员初始密码。
- 使用授权公钥、客户 ID、稳定部署 ID，以及在线激活码或离线授权。
- 外部 Kafka、Flink SQL Gateway、源端、目标端、目标表和数据库授权。
- 外部 Flink 集群已安装 Kafka / JDBC / StarRocks Connector、JDBC Driver、S3/MinIO 插件，并完成 checkpoint、savepoint 和 HA storage 验证。
- 备份目录和回滚窗口。

不得把 `.env`、授权文件、激活码、Token、私钥、客户部署指纹、真实连接串或现场拓扑写入公开仓库、公开工单或聊天群。

## 5. Docker Compose 部署流程

获取公开部署仓库：

```bash
git clone https://github.com/Lynn-Lee/DataFusionX-Deploy.git
cd DataFusionX-Deploy
cp .env.example .env
```

编辑 `.env`，至少检查并填妥：

```text
DATAFUSIONX_PUBLIC_URL
POSTGRES_PASSWORD
JWT_SECRET_KEY
ENCRYPTION_SECRET_KEY
DEFAULT_ADMIN_PASSWORD
LICENSE_PUBLIC_KEY
LICENSE_CUSTOMER_ID
LICENSE_DEPLOYMENT_ID
COMMERCIAL_INTEGRITY_PUBLIC_KEY
```

启动前确认没有遗留占位值：

```bash
grep -nE 'change-me|^LICENSE_PUBLIC_KEY=$|^LICENSE_CUSTOMER_ID=$|^COMMERCIAL_INTEGRITY_PUBLIC_KEY=$' .env
```

预期结果是没有输出。只要还有输出，就继续编辑 `.env`。

渲染并启动：

```bash
docker compose -f deploy/docker-compose.yml --env-file .env config --quiet
docker compose -f deploy/docker-compose.yml --env-file .env pull
docker compose -f deploy/docker-compose.yml --env-file .env up -d
docker compose -f deploy/docker-compose.yml --env-file .env ps
```

健康检查：

```bash
curl -fsS http://localhost:18000/api/v1/health
```

浏览器访问：

```text
http://localhost:8080
```

## 6. Helm 部署流程

Kubernetes 环境可使用随包 Helm Chart。生产环境建议先复制 values 文件，再通过文件部署，避免把密码、Token 或授权配置写进命令历史：

```bash
cp helm/datafusionx-commercial/values.yaml values-prod.yaml
```

至少修改 `values-prod.yaml` 中的版本、访问地址、镜像和 `secrets`：

```yaml
global:
  version: "<version>"
  publicUrl: "https://datafusionx.example.com"
image:
  backend: "<backend-image>"
  frontend: "<frontend-image>"
secrets:
  postgresPassword: "<数据库密码>"
  jwtSecretKey: "<至少 32 字节 JWT 密钥>"
  encryptionSecretKey: "<至少 32 字节加密密钥>"
  licensePublicKey: "<使用授权公钥>"
  licenseCustomerId: "<客户 ID>"
  licenseDeploymentId: "<稳定部署 ID>"
  commercialIntegrityPublicKey: "<商业发布包验签公钥>"
auth:
  ssoRedirectUrl: "https://datafusionx.example.com/oauth/callback"
```

部署前先渲染检查：

```bash
helm template datafusionx ./helm/datafusionx-commercial -f values-prod.yaml >/tmp/datafusionx-rendered.yaml
helm upgrade --install datafusionx ./helm/datafusionx-commercial -f values-prod.yaml
```

生产环境建议接入客户已有 Secret、Ingress、存储、镜像仓库、日志采集和监控系统。Chart 默认提供 PostgreSQL、Redis、Backend、Frontend、Celery Worker、Celery Beat 和授权文件 PVC；如使用托管 PostgreSQL / Redis，可基于 values 调整。

## 7. 发布包校验

固定版本压缩包下载后先校验 sha256：

```bash
shasum -a 256 -c DataFusionX-Enterprise-v<version>.tar.gz.sha256
```

部署目录内校验 signed release manifest：

```bash
python tools/commercial-manifest.py verify-release \
  --package-dir . \
  --public-key <商业发布验签公钥>
```

正式发布记录中建议留存：

- 版本号和发布批次。
- 压缩包 sha256。
- `release-manifest.json` 与签名校验结果。
- 后端和前端镜像 digest。
- 部署环境、变更窗口、回滚点和验收负责人。

## 8. 使用授权

部署完成后，DataFusionX Enterprise 支持试用授权，试用期内可以完整体验产品能力。如果试用期结束后仍希望继续使用，或希望扩大到更多用户、更多实例、长期生产环境、离线环境或正式商业场景，请联系作者 Lynn-Lee 获取继续使用授权。

授权详情见 `LEGAL-NOTICE.md`。

## 9. 部署后初始化

部署完成后，按以下顺序初始化：

1. 使用初始化管理员账号登录控制台。
2. 修改默认管理员密码。
3. 进入系统健康页确认后端、Worker、Beat、PostgreSQL、Redis、授权和商业完整性状态。
4. 如需统一身份，配置 LDAP、OIDC、CAS 或企业 IM 登录。
5. 创建项目，添加项目成员并分配 `viewer`、`operator`、`admin`。
6. 配置源端连接和目标端连接，并完成连通性检查和 catalog 校验。
7. 创建 CDC、Batch 或 SQL 作业。
8. 发布执行计划并完成项目管理员审批。
9. 配置手动运行或调度。
10. 在运行中心、DDL 卫士、诊断中心、告警列表和审计日志中确认投产风险。

详细操作见 `USER_GUIDE.md`。

## 10. 投产检查清单

### 10.1 部署前

- 已阅读 `INSTALLATION.md` 和本私有化部署方案。
- 已准备 Docker Compose 或 Kubernetes / Helm 环境。
- 已确认服务器可以拉取固定版本镜像，或已导入离线镜像。
- 已复制 `.env.example` 为 `.env` 并替换所有 `change-me` 值。
- 已确认 `DATAFUSIONX_PUBLIC_URL` 与用户浏览器实际访问地址一致。
- 已准备使用授权公钥、客户 ID、稳定部署 ID，以及在线激活码或离线授权。
- 已确认 `.env`、授权文件、激活码、Token、私钥、部署指纹和数据库连接串不会进入公开材料。

### 10.2 发布包和镜像

- 已校验版本压缩包 sha256。
- 已执行 `tools/commercial-manifest.py verify-release` 校验 signed release manifest。
- 已确认 Docker Compose 和 Helm values 均使用固定版本镜像标签。
- 已记录后端和前端镜像 digest。

### 10.3 部署后

- 控制台首页可访问。
- `/api/v1/health` 健康检查通过。
- backend、celery-worker、cdc-guard-worker 运行正常。
- 单节点部署中 celery-beat 运行正常；多节点部署中只有主调度节点运行 celery-beat。
- 系统管理员可以登录。
- 授权状态有效或仍处于试用期内。
- 默认管理员密码已修改。

### 10.4 产品使用

- 已创建项目。
- 已添加项目成员并分配角色。
- 已配置源端连接和目标端连接。
- 已确认外部 Kafka、Flink SQL Gateway、目标表和数据库授权由客户侧准备。
- 已确认 Flink Connector、JDBC Driver、MinIO/S3 checkpoint 和外部 CDC 引擎由客户数据平台侧维护，DataFusionX Enterprise 不创建或托管这些资源。
- 已创建并审批至少一个 CDC、Batch 或 SQL 作业。
- 已完成一次手动验证运行。
- DDL 卫士、告警通知、诊断中心和审计日志已完成投产前检查。

### 10.5 运维和回滚

- 已阅读 `OPERATIONS_UPGRADE.md`。
- 已执行升级前备份或确认初次部署备份策略。
- 已确认回滚脚本、备份目录和回滚窗口。
- 已明确日常巡检负责人、告警接收人和支持联系人。

## 11. 升级和回滚

升级前执行：

```bash
DEFAULT_ADMIN_PASSWORD='<管理员密码>' ./preflight-upgrade.sh
```

脚本会检查固定版本镜像、关键环境变量、Compose 配置、商业 release manifest、PostgreSQL 元数据库备份、授权数据卷备份、运行中任务、Alembic 当前版本、健康检查和授权状态。检查通过后会输出 `backups/preflight-<时间戳>/` 备份目录。

升级：

```bash
DEFAULT_ADMIN_PASSWORD='<管理员密码>' ./upgrade.sh
DEFAULT_ADMIN_PASSWORD='<管理员密码>' ./verify-license.sh
```

回滚：

```bash
BACKUP_DIR='./backups/preflight-<时间戳>' CONFIRM_ROLLBACK=1 ./rollback.sh
DEFAULT_ADMIN_PASSWORD='<管理员密码>' ./verify-license.sh
```

`backups/preflight-<时间戳>/env.full.local`、`env.rollback.local`、`metadata.dump` 和 `licenses.tgz` 是敏感回滚材料，不得进入工单、公开聊天、公开仓库或交付包。对外排查只共享 `env.redacted`、`compose.rendered.yml`、`health.json`、`license-status.json` 和 `preflight-summary.txt`。

如果管理员首次登录后已改密，所有脚本中的 `<管理员密码>` 都应使用当前有效密码；如果管理员账号不是默认 `admin`，同时传入 `DEFAULT_ADMIN_USERNAME='<管理员账号>'`。

## 12. 安全边界

- 不提交 `.env`、真实数据库连接串、Token、私钥、云服务凭据、SSH Host、凭据路径、现场 runbook、客户部署指纹或真实拓扑。
- 不在客户侧部署授权中心私钥。
- 不使用 `latest` 镜像标签进入生产。
- 不绕过执行计划审批、DDL 卫士、授权拦截、审计和商业完整性校验。
- 共享日志、截图、诊断包和验收材料前必须脱敏。

## 13. 公开发布源头

DataFusionX Enterprise 私有源码仓库是唯一研发、构建、签名和发布源头。正式 tag 或显式手动发布时，商业发布流程会生成部署包并同步到 `Lynn-Lee/DataFusionX-Deploy`。公开部署仓库只保存用户部署入口、用户文档、校验工具、固定版本镜像引用和历史版本压缩包，不保存源码、私钥、真实授权文件、激活码、客户部署指纹、授权中心 token、现场 runbook、真实拓扑或 sourcemap。
