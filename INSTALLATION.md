# DataFusionX Enterprise 安装部署指南

当前发布版本：`0.1.0-deploy-smoke`

本文面向首次部署 DataFusionX Enterprise 的客户管理员和运维人员。

## 部署前准备

Docker Compose 部署需要：

- Linux 服务器或等价容器运行环境。
- Docker Engine 和 Docker Compose v2。
- 可访问 `ghcr.io/lynn-lee/datafusionx-backend:0.1.0-deploy-smoke` 和 `ghcr.io/lynn-lee/datafusionx-frontend:0.1.0-deploy-smoke`。
- 可用端口：默认前端 `8080`，后端 `18000`，PostgreSQL `15432`，Redis `16379`。
- 有效 License 公钥、客户 ID、稳定部署 ID，以及在线激活码或离线 License。

Kubernetes 部署需要：

- 可用 Kubernetes 集群。
- Helm 3。
- 可拉取固定版本商业镜像的镜像仓库访问能力。
- 持久化存储能力，用于 PostgreSQL、Redis 和 License 文件。

## 获取部署包

推荐方式：

```bash
git clone https://github.com/Lynn-Lee/DataFusionX-Deploy.git
cd DataFusionX-Deploy
```

固定版本压缩包方式：

```bash
curl -LO https://github.com/Lynn-Lee/DataFusionX-Deploy/raw/main/releases/v0.1.0-deploy-smoke/DataFusionX-Enterprise-v0.1.0-deploy-smoke.tar.gz
curl -LO https://github.com/Lynn-Lee/DataFusionX-Deploy/raw/main/releases/v0.1.0-deploy-smoke/DataFusionX-Enterprise-v0.1.0-deploy-smoke.tar.gz.sha256
shasum -a 256 -c DataFusionX-Enterprise-v0.1.0-deploy-smoke.tar.gz.sha256
tar -xzf DataFusionX-Enterprise-v0.1.0-deploy-smoke.tar.gz
cd DataFusionX-Enterprise-v0.1.0-deploy-smoke
```

## 配置环境变量

```bash
cp .env.example .env
```

必须修改：

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

## Docker Compose 部署

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

## Helm 部署

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

## 首次登录

默认管理员账号来自 `.env`：

```text
DEFAULT_ADMIN_USERNAME
DEFAULT_ADMIN_PASSWORD
```

生产环境必须在首次登录后修改默认密码，并妥善保存系统管理员账号。

## License 激活

在线激活：

1. 使用系统管理员登录。
2. 进入系统健康或授权管理入口。
3. 填写客户 ID 和在线激活码。
4. 提交激活并确认 License 状态为有效。

离线激活：

1. 在授权页面生成离线申请。
2. 将离线申请 JSON 发给授权运营侧。
3. 获取 signed License JSON。
4. 在授权页面导入 signed License。

离线申请不包含数据库密码、私钥或连接凭据。

## 常见启动问题

- 镜像拉取失败：确认服务器可访问镜像仓库，且镜像标签为固定版本 `0.1.0-deploy-smoke`。
- 后端启动失败：检查 `JWT_SECRET_KEY`、`ENCRYPTION_SECRET_KEY`、`POSTGRES_PASSWORD` 和 `COMMERCIAL_INTEGRITY_PUBLIC_KEY`。
- 登录后功能受限：检查 License 是否已导入、是否过期、是否包含所需功能和额度。
- 数据同步作业无法部署：确认外部 Flink SQL Gateway、Kafka、源端和目标端连接均可访问。DataFusionX Enterprise 只做控制面，不创建 Kafka Topic、Flink 集群或生产目标表。
