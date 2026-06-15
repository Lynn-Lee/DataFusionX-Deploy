# DataFusionX Enterprise 安装部署指南

当前发布版本：`0.1.0-deploy-smoke`

本文面向首次部署 DataFusionX Enterprise 的系统管理员和运维人员，覆盖环境准备、部署包获取、配置、Docker Compose 部署、Helm 部署、首次登录和基础验证。

## 1. 部署架构

DataFusionX Enterprise 控制台由以下组件组成：

- `frontend`：Web 控制台。
- `backend`：FastAPI 后端和业务 API。
- `celery-worker`：异步任务 Worker。
- `cdc-guard-worker`：CDC / DDL 卫士相关后台任务。
- `celery-beat`：周期任务调度器，HA 场景只能保留一个调度节点。
- `postgres`：元数据数据库。
- `redis`：任务队列和锁。

外部数据面资源由客户环境提供，包括源端数据库、目标端数据库、Kafka、Debezium、TiCDC、Flink 集群和 Flink SQL Gateway。

## 2. 部署前准备

Docker Compose 部署需要：

- Linux 服务器或等价容器运行环境。
- Docker Engine 和 Docker Compose v2。
- 可访问固定版本镜像：`ghcr.io/lynn-lee/datafusionx-backend:0.1.0-deploy-smoke`、`ghcr.io/lynn-lee/datafusionx-frontend:0.1.0-deploy-smoke`。
- 可用端口：默认前端 `8080`，后端 `18000`，PostgreSQL `15432`，Redis `16379`。
- PostgreSQL 和 Redis 数据卷可持久化。
- 有效 License 公钥、客户 ID、稳定部署 ID，以及在线激活码或离线 License。

Kubernetes 部署需要：

- 可用 Kubernetes 集群。
- Helm 3。
- 可拉取固定版本镜像的镜像仓库访问能力。
- 持久化存储能力，用于 PostgreSQL、Redis 和 License 文件。
- Ingress、TLS 和域名按企业规范准备。

生产部署前请准备：

- 管理员初始密码。
- 至少 32 位 `JWT_SECRET_KEY`。
- 至少 32 位 `ENCRYPTION_SECRET_KEY`。
- PostgreSQL 强密码。
- License 相关配置。
- 告警通知渠道和运维联系人。

## 3. 获取部署包

推荐直接使用公开部署仓库：

```bash
git clone https://github.com/Lynn-Lee/DataFusionX-Deploy.git
cd DataFusionX-Deploy
```

也可以使用固定版本压缩包：

```bash
curl -LO https://github.com/Lynn-Lee/DataFusionX-Deploy/raw/main/releases/v0.1.0-deploy-smoke/DataFusionX-Enterprise-v0.1.0-deploy-smoke.tar.gz
curl -LO https://github.com/Lynn-Lee/DataFusionX-Deploy/raw/main/releases/v0.1.0-deploy-smoke/DataFusionX-Enterprise-v0.1.0-deploy-smoke.tar.gz.sha256
shasum -a 256 -c DataFusionX-Enterprise-v0.1.0-deploy-smoke.tar.gz.sha256
tar -xzf DataFusionX-Enterprise-v0.1.0-deploy-smoke.tar.gz
cd DataFusionX-Enterprise-v0.1.0-deploy-smoke
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

## 4. 配置环境变量

复制模板：

```bash
cp .env.example .env
```

至少修改以下配置：

```text
POSTGRES_PASSWORD
JWT_SECRET_KEY
ENCRYPTION_SECRET_KEY
DEFAULT_ADMIN_PASSWORD
LICENSE_PUBLIC_KEY
LICENSE_CUSTOMER_ID
LICENSE_DEPLOYMENT_ID
COMMERCIAL_INTEGRITY_PUBLIC_KEY
```

`LICENSE_DEPLOYMENT_ID` 是部署指纹计算的一部分，生成后应长期保持稳定。随意变更会导致 License 需要重新签发或迁移。

端口默认值：

```text
FRONTEND_PORT=8080
BACKEND_PORT=18000
POSTGRES_PORT=15432
REDIS_PORT=16379
```

生产环境不要使用弱密码、默认密钥或 `change-me` 值。

## 5. Docker Compose 部署

渲染并检查配置：

```bash
docker compose -f deploy/docker-compose.yml --env-file .env config --quiet
```

拉取镜像：

```bash
docker compose -f deploy/docker-compose.yml --env-file .env pull
```

启动服务：

```bash
docker compose -f deploy/docker-compose.yml --env-file .env up -d
```

查看状态：

```bash
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

如果部署在反向代理后，请把外部访问域名、TLS、超时和上传限制按企业网关规范配置。

## 6. Helm 部署

示例命令：

```bash
helm upgrade --install datafusionx ./helm/datafusionx-commercial \
  --set global.version=0.1.0-deploy-smoke \
  --set image.backend=ghcr.io/lynn-lee/datafusionx-backend:0.1.0-deploy-smoke \
  --set image.frontend=ghcr.io/lynn-lee/datafusionx-frontend:0.1.0-deploy-smoke \
  --set global.publicUrl=https://datafusionx.example.com \
  --set secrets.postgresPassword='<数据库密码>' \
  --set secrets.jwtSecretKey='<至少 32 位 JWT 密钥>' \
  --set secrets.encryptionSecretKey='<至少 32 位加密密钥>' \
  --set secrets.licensePublicKey='<License 公钥>' \
  --set secrets.licenseDeploymentId='<稳定部署 ID>'
```

生产环境建议使用 values 文件或 Kubernetes Secret 管理敏感配置，不要把密码、Token、License 或私钥写入命令历史、公开仓库或工单。

部署后检查：

```bash
kubectl get pods
kubectl get svc
kubectl logs deploy/datafusionx-backend --tail=100
```

## 7. 首次登录

默认管理员账号来自 `.env`：

```text
DEFAULT_ADMIN_USERNAME
DEFAULT_ADMIN_PASSWORD
```

首次登录后请立即完成：

1. 修改管理员密码。
2. 确认系统健康状态。
3. 确认 License 状态。
4. 创建业务项目。
5. 添加项目成员并分配角色。

本地开发或测试可使用初始化账号；生产环境必须使用强随机密码，并妥善保存管理员账号。

## 8. License 激活

在线激活：

1. 使用系统管理员登录。
2. 进入系统健康或授权管理入口。
3. 填写客户 ID 和在线激活码。
4. 提交激活并确认 License 状态为有效。

离线激活：

1. 在授权页面生成离线申请。
2. 将离线申请 JSON 交给授权运营侧。
3. 获取 signed License JSON。
4. 在授权页面导入 signed License。

离线申请不包含数据库密码、私钥或连接凭据。

## 9. 部署后基础验证

完成部署后建议按顺序检查：

```bash
docker compose -f deploy/docker-compose.yml --env-file .env ps
curl -fsS http://localhost:18000/api/v1/health
DEFAULT_ADMIN_PASSWORD='<管理员密码>' ./verify-license.sh
```

控制台内检查：

- 系统健康页面无异常组件。
- License 状态有效。
- 创建测试项目成功。
- 添加源端和目标端连接成功。
- 连接连通性检查可执行。
- 运行中心、诊断中心、审计日志页面可打开。

## 10. 常见启动问题

- 镜像拉取失败：确认服务器可访问镜像仓库，且镜像标签为固定版本 `0.1.0-deploy-smoke`。
- 后端启动失败：检查 `JWT_SECRET_KEY`、`ENCRYPTION_SECRET_KEY`、`POSTGRES_PASSWORD` 和 `COMMERCIAL_INTEGRITY_PUBLIC_KEY`。
- 登录后功能受限：检查 License 是否已导入、是否过期、是否包含所需功能和额度。
- 前端无法访问后端：检查反向代理、`BACKEND_PORT`、容器网络和浏览器控制台错误。
- 数据同步作业无法部署：确认外部 Flink SQL Gateway、Kafka、源端和目标端连接均可访问。
- 调度重复触发：确认多节点部署中只有一个 `celery-beat` 常驻运行。

## 11. 下一步

部署完成后继续阅读：

- [产品使用手册](USER_GUIDE.md)：完成项目、连接、任务、审批、调度和投产检查。
- [运维与升级指南](OPERATIONS_UPGRADE.md)：配置日常巡检、备份、升级和回滚流程。
- [私有化部署方案](COMMERCIAL_DEPLOYMENT.md)：查看部署形态、交付内容和投产检查清单。
- [使用授权](LEGAL-NOTICE.md)：了解试用授权和继续使用授权方式。
