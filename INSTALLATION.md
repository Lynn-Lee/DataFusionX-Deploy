# DataFusionX Enterprise 安装部署指南

当前发布版本：`3.0`

本文面向首次部署 DataFusionX Enterprise 的系统管理员和运维人员。按本文顺序执行，可以完成部署包获取、配置、Docker Compose 或 Helm 部署、首次登录、授权激活和基础验收。

## 1. 先确认部署方式

如果只是试用、PoC 或小规模生产，优先使用 Docker Compose 单节点部署；如果企业已有 Kubernetes 平台，使用 Helm 部署。

| 场景 | 推荐方式 | 说明 |
| --- | --- | --- |
| 试用 / PoC / 单台服务器 | Docker Compose | 最少依赖，随包启动 PostgreSQL 和 Redis。 |
| 小规模生产 | Docker Compose | 可先使用随包 PostgreSQL / Redis，也可按企业规范改成外部托管服务。 |
| 标准生产 / 多环境 | Helm | 适合接入 Ingress、Secret、PVC、日志采集、监控和企业镜像仓库。 |
| 无公网环境 | 离线镜像部署 | 先导入镜像 tar 或同步到企业私有镜像仓库，再按 Compose 或 Helm 部署。 |

DataFusionX Enterprise 只部署控制面。源端数据库、目标端数据库、Kafka、Debezium、TiCDC、Flink 集群、Flink SQL Gateway、目标表和数据库授权 SQL 需要由客户现有平台、DBA 或运维团队提前准备。

## 2. 部署架构

随包部署包含以下组件：

- `frontend`：Web 控制台。
- `backend`：FastAPI 后端和业务 API。
- `celery-worker`：异步任务 Worker。
- `cdc-guard-worker`：CDC / DDL 卫士相关后台任务。
- `celery-beat`：周期任务调度器。多节点或 HA 场景只能保留一个调度节点。
- `postgres`：控制台元数据数据库。
- `redis`：任务队列、缓存和锁。

默认端口：

| 组件 | 默认端口 | 用途 |
| --- | ---: | --- |
| frontend | `8080` | 用户访问控制台。 |
| backend | `18000` | 健康检查和 API。 |
| postgres | `15432` | 元数据库，仅建议内网访问。 |
| redis | `16379` | 任务队列，仅建议内网访问。 |

如果服务器已占用这些端口，在 `.env` 中修改 `FRONTEND_PORT`、`BACKEND_PORT`、`POSTGRES_PORT`、`REDIS_PORT`。

## 3. 环境准备

Docker Compose 部署需要：

- Linux 服务器或等价容器运行环境。
- Docker Engine 和 Docker Compose v2。
- `curl`、`tar`、`shasum` 或 `sha256sum`。
- 可拉取固定版本镜像，或已经导入离线镜像。
- 持久化磁盘用于 PostgreSQL 数据卷和授权文件卷。
- 可访问控制台的域名、内网地址或反向代理地址。
- 有效的使用授权公钥、客户 ID、稳定部署 ID，以及在线激活码或离线授权文件。

Kubernetes 部署需要：

- 可用 Kubernetes 集群。
- Helm 3。
- 可拉取固定版本镜像的仓库访问能力，或企业私有镜像仓库。
- StorageClass / PVC，用于 PostgreSQL、Redis 和授权文件。
- Ingress、TLS、域名、日志采集和监控按企业规范准备。

生产部署前请提前准备：

- 管理员初始密码。
- 至少 32 字节的 `JWT_SECRET_KEY`。
- 至少 32 字节的 `ENCRYPTION_SECRET_KEY`。
- PostgreSQL 强密码。
- `LICENSE_PUBLIC_KEY`、`LICENSE_CUSTOMER_ID`、`LICENSE_DEPLOYMENT_ID`。
- 告警通知渠道和运维联系人。

可用下面命令生成随机密钥：

```bash
openssl rand -base64 48
```

## 4. 获取部署包

推荐直接使用公开部署仓库：

```bash
git clone https://github.com/Lynn-Lee/DataFusionX-Deploy.git
cd DataFusionX-Deploy
```

也可以下载固定版本压缩包：

```bash
curl -LO https://github.com/Lynn-Lee/DataFusionX-Deploy/raw/main/releases/v3.0/DataFusionX-Enterprise-v3.0.tar.gz
curl -LO https://github.com/Lynn-Lee/DataFusionX-Deploy/raw/main/releases/v3.0/DataFusionX-Enterprise-v3.0.tar.gz.sha256
shasum -a 256 -c DataFusionX-Enterprise-v3.0.tar.gz.sha256
tar -xzf DataFusionX-Enterprise-v3.0.tar.gz
cd DataFusionX-Enterprise-v3.0
```

如果系统没有 `shasum`，可使用：

```bash
sha256sum -c DataFusionX-Enterprise-v3.0.tar.gz.sha256
```

发布包内主要文件：

- `README.md`：项目说明和快速开始。
- `INSTALLATION.md`：安装部署指南。
- `OPERATIONS_UPGRADE.md`：运维与升级指南。
- `USER_GUIDE.md`：产品使用手册。
- `deploy/docker-compose.yml`：Docker Compose 编排。
- `helm/datafusionx-commercial/`：Helm Chart。
- `.env.example`：环境变量模板。
- `preflight-upgrade.sh`、`upgrade.sh`、`rollback.sh`、`verify-license.sh`：升级、回滚和校验脚本。

## 5. 配置 `.env`

复制模板：

```bash
cp .env.example .env
chmod 600 .env
```

至少检查并填妥以下配置：

| 配置项 | 必填 | 说明 |
| --- | --- | --- |
| `DATAFUSIONX_VERSION` | 是 | 当前部署版本，默认 `3.0`。 |
| `DATAFUSIONX_BACKEND_IMAGE` | 是 | 后端 / Worker / Beat 固定版本镜像。 |
| `DATAFUSIONX_FRONTEND_IMAGE` | 是 | 前端固定版本镜像。 |
| `DATAFUSIONX_PUBLIC_URL` | 是 | 用户浏览器访问控制台的最终地址，例如 `https://datafusionx.example.com`。 |
| `POSTGRES_PASSWORD` | 是 | 元数据库密码。 |
| `JWT_SECRET_KEY` | 是 | 登录 token 签名密钥，至少 32 字节；配置 `JWT_SECRET_KEY_CURRENT` 时作为兼容回退。 |
| `JWT_SECRET_KEY_CURRENT` | 否 | JWT 轮换期间用于签发新 token，至少 32 字节。 |
| `JWT_SECRET_KEY_PREVIOUS` | 否 | JWT 轮换期间用于验证旧 token，旧 token 过期后清空。 |
| `ENCRYPTION_SECRET_KEY` | 是 | 连接凭据加密密钥，至少 32 字节。 |
| `DEFAULT_ADMIN_USERNAME` | 是 | 初始管理员账号，默认 `admin`。 |
| `DEFAULT_ADMIN_PASSWORD` | 是 | 初始管理员密码，生产必须替换。 |
| `LICENSE_PUBLIC_KEY` | 是 | 使用授权验签公钥。 |
| `LICENSE_CUSTOMER_ID` | 是 | 客户 ID。 |
| `LICENSE_DEPLOYMENT_ID` | 是 | 稳定部署 ID，生成后长期保持不变。 |
| `LICENSE_TRIAL_DAYS` | 是 | 初次部署自动生成的试用授权期限，默认 `180` 天。 |
| `COMMERCIAL_INTEGRITY_PUBLIC_KEY` | 是 | 用户部署包完整性验签公钥。 |

`LICENSE_DEPLOYMENT_ID` 是部署指纹计算的一部分，随意变更会导致授权需要重新签发或迁移。建议用企业内唯一且稳定的值，例如 `customer-prod-datafusionx-001`，不要写真实机密或服务器地址。

### 5.1 外部运行时接入配置

Compose 部署时，复制 `.env.example` 为 `.env` 后，需要填写客户已有 Flink 入口：

```text
FLINK_SQL_GATEWAY_URL=http://flink-sql-gateway.example.com:8083
FLINK_REST_URL=http://flink-rest.example.com:8081
```

如果希望“系统健康”页面做平台级 Kafka 连通性检查，可填写：

```text
KAFKA_BOOTSTRAP_SERVERS=kafka01:9092,kafka02:9092,kafka03:9092
```

`KAFKA_BOOTSTRAP_SERVERS` 只用于平台级依赖健康检查。CDC 任务真正消费的 Kafka bootstrap servers 和 Topic，需要在控制台创建 CDC 任务时逐任务填写。

| 配置对象 | 配置位置 | 说明 |
| --- | --- | --- |
| Flink SQL Gateway | `.env` 的 `FLINK_SQL_GATEWAY_URL` | DataFusionX Enterprise 提交 CDC、Batch 和 SQL 作业的入口。 |
| Flink REST | `.env` 的 `FLINK_REST_URL` | 运行中心刷新 Flink Job 状态、异常、指标和 checkpoint 的入口。 |
| 平台级 Kafka 健康检查 | `.env` 的 `KAFKA_BOOTSTRAP_SERVERS` | 只用于依赖健康检查，可留空。 |
| 私网端点探测开关 | `.env` 的 `ALLOW_PRIVATE_NETWORK_ENDPOINTS` | 生产环境必须保持 `false`，避免连接探测被用作内网端口扫描；仅本地单机演示或隔离测试可临时开启。 |
| CDC 任务 Kafka 消费 | 控制台 CDC 任务表单 | 每个 CDC 任务填写 Kafka Bootstrap Servers、Topic、消息格式和消费起点。 |
| Flink Connector / JDBC Driver | 客户 Flink 集群插件目录或集群镜像 | Kafka、JDBC、StarRocks 等 connector jar 由 Flink 管理员安装。 |
| MinIO / S3 checkpoint | 客户 Flink 集群配置 | S3/MinIO 插件、checkpoint、savepoint 和 HA storage 由客户 Flink 集群维护。 |
| Debezium / Canal / TiCDC | 客户外部 CDC 平台 | DataFusionX Enterprise 不创建 Connector 或 Changefeed，只消费已产生的 Kafka Topic。 |

后端、Celery Worker、Celery Beat 和 CDC Guard Worker 都读取同一份 `.env`。修改 Flink、Kafka 或 DDL Guard 相关环境变量后，需要重启这些服务，避免 API、后台提交、调度刷新和 DDL 卫士使用不同配置。

如果启用企业统一登录，请确认 `.env` 中有：

```text
SSO_REDIRECT_URL=https://datafusionx.example.com/oauth/callback
```

保存后检查占位值：

```bash
grep -nE 'change-me|^LICENSE_PUBLIC_KEY=$|^LICENSE_CUSTOMER_ID=$|^COMMERCIAL_INTEGRITY_PUBLIC_KEY=$' .env
```

预期结果：没有输出。只要还有输出，就先继续编辑 `.env`，不要启动生产服务。

## 6. Docker Compose 部署

### 6.1 渲染配置

```bash
docker compose -f deploy/docker-compose.yml --env-file .env config --quiet
```

预期结果：命令无输出且退出码为 `0`。如果提示某个变量 `is required`，回到第 5 节补齐 `.env`。

### 6.2 拉取镜像

```bash
docker compose -f deploy/docker-compose.yml --env-file .env pull
```

预期结果：`postgres`、`redis`、`backend`、`frontend` 等镜像拉取成功。公网受限环境请先按第 8 节导入离线镜像。

### 6.3 启动服务

```bash
docker compose -f deploy/docker-compose.yml --env-file .env up -d
```

查看状态：

```bash
docker compose -f deploy/docker-compose.yml --env-file .env ps
```

预期结果：`postgres`、`redis`、`backend`、`celery-worker`、`cdc-guard-worker`、`celery-beat`、`frontend` 均处于 `running` 或 `Up` 状态。

如果某个服务没有启动，先看日志：

```bash
docker compose -f deploy/docker-compose.yml --env-file .env logs --tail=200 backend
docker compose -f deploy/docker-compose.yml --env-file .env logs --tail=200 celery-worker
docker compose -f deploy/docker-compose.yml --env-file .env logs --tail=200 frontend
```

常见原因是 `.env` 仍有空值、镜像拉取失败、端口冲突、PostgreSQL 密码错误或授权公钥缺失。

### 6.4 健康检查

```bash
curl -fsS http://localhost:18000/api/v1/health
```

预期结果：返回健康检查 JSON，且命令退出码为 `0`。

如果部署在远程服务器，可在服务器本机执行：

```bash
curl -fsS http://127.0.0.1:18000/api/v1/health
```

浏览器访问：

```text
http://<服务器地址或域名>:8080
```

如果使用反向代理，外部访问地址应与 `.env` 中 `DATAFUSIONX_PUBLIC_URL` 一致。

## 7. 首次登录和授权激活

默认管理员账号来自 `.env`：

```text
DEFAULT_ADMIN_USERNAME
DEFAULT_ADMIN_PASSWORD
```

首次登录后请立即完成：

1. 修改管理员密码。
2. 进入系统健康页面，确认后端、Worker、Beat、PostgreSQL、Redis、授权和商业完整性状态。
3. 进入授权管理入口，完成在线激活或离线授权导入。
4. 创建业务项目。
5. 添加项目成员并分配角色。

在线激活：

1. 使用系统管理员登录。
2. 进入系统健康或授权管理入口。
3. 填写客户 ID 和在线激活码。
4. 提交激活并确认授权状态为有效。

离线激活：

1. 在授权页面生成离线申请。
2. 将离线申请 JSON 交给授权运营侧。
3. 获取签名授权 JSON。
4. 在授权页面导入签名授权。

离线申请不包含数据库密码、私钥或连接凭据。

## 8. 离线镜像部署

如果服务器无法访问 GHCR，请先在可联网机器下载或由交付方提供镜像 tar，然后传到目标服务器：

```bash
docker load -i datafusionx-backend-commercial-3.0.tar
docker load -i datafusionx-frontend-commercial-3.0.tar
docker images | grep datafusionx
```

确认 `.env` 中镜像名与 `docker images` 输出一致：

```text
DATAFUSIONX_BACKEND_IMAGE=<已导入的后端镜像:固定版本>
DATAFUSIONX_FRONTEND_IMAGE=<已导入的前端镜像:固定版本>
```

随后从第 6.1 节继续执行。生产环境不要使用 `latest` 或无标签镜像。

## 9. Helm 部署

建议先复制 values 文件：

```bash
cp helm/datafusionx-commercial/values.yaml values-prod.yaml
```

编辑 `values-prod.yaml`，至少修改：

```yaml
global:
  version: "3.0"
  publicUrl: "https://datafusionx.example.com"
image:
  backend: "ghcr.io/lynn-lee/datafusionx-backend:3.0"
  frontend: "ghcr.io/lynn-lee/datafusionx-frontend:3.0"
secrets:
  postgresPassword: "<数据库密码>"
  jwtSecretKey: "<至少 32 字节 JWT 密钥>"
  jwtSecretKeyCurrent: "<可选，JWT 轮换期间的新密钥>"
  jwtSecretKeyPrevious: "<可选，JWT 轮换期间的上一把密钥>"
  encryptionSecretKey: "<至少 32 字节加密密钥>"
  licensePublicKey: "<使用授权公钥>"
  licenseCustomerId: "<客户 ID>"
  licenseDeploymentId: "<稳定部署 ID>"
  commercialIntegrityPublicKey: "<用户部署包验签公钥>"
auth:
  ssoRedirectUrl: "https://datafusionx.example.com/oauth/callback"
```

默认 Chart 会部署单实例内置 PostgreSQL。生产 HA 场景可改用客户已有 PostgreSQL 集群：先在目标 namespace 创建只包含元数据库密码的 Secret，再启用 `externalPostgres`。启用后，Chart 不再创建内置 PostgreSQL Deployment、Service 和 PVC。

```bash
kubectl create secret generic datafusionx-external-postgres \
  --from-literal=POSTGRES_PASSWORD='<数据库密码>'
```

```yaml
externalPostgres:
  enabled: true
  host: "postgres-ha.example.internal"
  port: 5432
  database: "datafusionx"
  username: "datafusionx"
  passwordSecret: "datafusionx-external-postgres"
  passwordSecretKey: "POSTGRES_PASSWORD"
```

渲染检查：

```bash
helm template datafusionx ./helm/datafusionx-commercial -f values-prod.yaml >/tmp/datafusionx-rendered.yaml
```

部署：

```bash
helm upgrade --install datafusionx ./helm/datafusionx-commercial -f values-prod.yaml
```

检查：

```bash
kubectl get pods
kubectl get svc
kubectl logs deploy/datafusionx-backend --tail=100
```

生产环境建议使用 Kubernetes Secret、外部 Secret 管理器或企业配置平台管理敏感配置，不要把密码、Token、授权文件或私钥写入命令历史、公开仓库或工单。

## 10. 反向代理和域名

如果通过 Nginx、Ingress 或企业网关暴露控制台，请确认：

- 外部域名已经指向前端服务。
- `DATAFUSIONX_PUBLIC_URL` 使用最终浏览器访问地址。
- `SSO_REDIRECT_URL` 使用同一域名下的 `/oauth/callback`。
- 网关保留 `Host`、`X-Forwarded-Proto`、`X-Forwarded-For`。
- API 请求、登录回调、文件导入导出和长时间运行请求没有被过短超时截断。
- TLS 证书由企业统一管理。

随包提供的 `nginx/datafusionx-commercial.conf` 可作为反向代理配置参考，正式接入前请按企业网关规范调整域名、证书和日志策略。

## 11. 部署后基础验证

完成部署后，按顺序检查：

```bash
docker compose -f deploy/docker-compose.yml --env-file .env ps
curl -fsS http://localhost:18000/api/v1/health
DEFAULT_ADMIN_PASSWORD='<管理员密码>' ./verify-license.sh
```

如果管理员首次登录后已经被要求改密，请使用新密码执行 `verify-license.sh`：

```bash
DEFAULT_ADMIN_USERNAME='<管理员账号>' DEFAULT_ADMIN_PASSWORD='<新管理员密码>' ./verify-license.sh
```

控制台内检查：

- 系统健康页面无异常组件。
- 授权状态有效或仍处于 180 天试用期内。
- 创建测试项目成功。
- 添加源端和目标端连接成功。
- 连接连通性检查可执行。
- 运行中心、诊断中心、审计日志页面可打开。

## 12. 常见启动问题

| 现象 | 先检查什么 | 常用命令 |
| --- | --- | --- |
| `docker compose config` 报变量缺失 | `.env` 是否未填或仍为 `change-me` | `grep -nE 'change-me|^LICENSE_PUBLIC_KEY=$' .env` |
| 镜像拉取失败 | 服务器是否能访问镜像仓库，镜像标签是否固定版本 | `docker compose -f deploy/docker-compose.yml --env-file .env pull` |
| 后端启动失败 | JWT、加密密钥、PostgreSQL 密码、授权公钥、完整性公钥 | `docker compose -f deploy/docker-compose.yml --env-file .env logs --tail=200 backend` |
| 前端可打开但登录失败 | 后端健康、`DATAFUSIONX_PUBLIC_URL`、反向代理、浏览器控制台 | `curl -fsS http://localhost:18000/api/v1/health` |
| 登录后功能受限 | 授权是否已导入、是否过期、功能和额度是否满足 | `DEFAULT_ADMIN_PASSWORD='<密码>' ./verify-license.sh` |
| 数据同步作业无法部署 | `.env` 中 Flink SQL Gateway / REST 是否可达，CDC 任务级 Kafka 配置、源端、目标端、目标表是否准备完成 | 在控制台连接测试、catalog 校验和系统健康页面复核 |
| Flink 作业启动后缺少 connector 或 checkpoint 失败 | 客户 Flink 集群是否已安装 Kafka / JDBC / StarRocks / S3 等 connector、driver 和 MinIO/S3 checkpoint 配置 | 在外部 Flink Web UI、TaskManager 日志和 Flink 集群配置中排查 |
| 调度重复触发 | 是否只有一个 `celery-beat` 常驻运行 | `docker compose -f deploy/docker-compose.yml --env-file .env ps | grep celery-beat` |

## 13. 下一步

部署完成后继续阅读：

- [产品使用手册](USER_GUIDE.md)：完成项目、连接、任务、审批、调度和投产检查。
- [运维与升级指南](OPERATIONS_UPGRADE.md)：配置日常巡检、备份、升级和回滚流程。
- [部署方案与边界](COMMERCIAL_DEPLOYMENT.md)：查看部署形态选择、交付内容、控制面/数据面边界和投产检查清单。
- [使用授权](LEGAL-NOTICE.md)：了解试用授权和继续使用授权方式。
