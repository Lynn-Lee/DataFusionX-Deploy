# DataFusionX Enterprise

DataFusionX Enterprise 是面向企业 IT、DBA、数据开发和运维团队的商业私有化数据同步控制台。本仓库是 DataFusionX Enterprise 的公开部署仓库，只包含用户部署所需的编排文件、文档、校验工具和固定版本商业镜像引用，不包含私有源码。

当前发布版本：`0.1.0-deploy-smoke`

## 这个仓库适合谁

- 想快速了解 DataFusionX Enterprise 能力和部署形态的客户或合作伙伴。
- 需要在测试、预生产或生产环境安装 DataFusionX Enterprise 的运维人员。
- 需要查看升级、回滚、License 激活和日常巡检步骤的系统管理员。

## 你可以在这里做什么

- 直接 clone 本仓库并使用 Docker Compose 或 Helm 部署。
- 下载 `releases/v0.1.0-deploy-smoke/DataFusionX-Enterprise-v0.1.0-deploy-smoke.tar.gz` 固定版本包。
- 校验发布包 sha256 和 signed release manifest。
- 查看安装部署、运维升级和产品使用手册。

## 快速开始

```bash
git clone https://github.com/Lynn-Lee/DataFusionX-Deploy.git
cd DataFusionX-Deploy
cp .env.example .env
```

编辑 `.env`，至少替换所有 `change-me` 值，并填写 License 相关配置。然后启动：

```bash
docker compose -f deploy/docker-compose.yml --env-file .env pull
docker compose -f deploy/docker-compose.yml --env-file .env up -d
docker compose -f deploy/docker-compose.yml --env-file .env ps
```

默认访问地址：

- 控制台：`http://localhost:8080`
- 后端健康检查：`http://localhost:18000/api/v1/health`

## 文档

- [安装部署指南](INSTALLATION.md)
- [运维与升级指南](OPERATIONS_UPGRADE.md)
- [产品使用手册](USER_GUIDE.md)
- [商业交付检查清单](CUSTOMER_DELIVERY_CHECKLIST.md)
- [商业私有化部署方案](COMMERCIAL_DEPLOYMENT.md)
- [法律和授权说明](LEGAL-NOTICE.md)

## 发布包校验

```bash
shasum -a 256 -c releases/v0.1.0-deploy-smoke/DataFusionX-Enterprise-v0.1.0-deploy-smoke.tar.gz.sha256
python tools/commercial-manifest.py verify-release \
  --package-dir . \
  --public-key '7sE7Bn3CJGIAd-CCDpeX-05wjTFsaS4kbM3vKU0tWNM'
```

## 镜像

- 后端 / Worker / Beat：`ghcr.io/lynn-lee/datafusionx-backend:0.1.0-deploy-smoke`
- 前端：`ghcr.io/lynn-lee/datafusionx-frontend:0.1.0-deploy-smoke`

生产环境不要使用 `latest`，请保留 `.env.example`、Docker Compose 和 Helm values 中的明确版本标签。

## 授权边界

本仓库可公开 clone 或下载，但商业使用仍需要有效 License。License、激活码、客户部署指纹和授权额度由授权中心单独签发和管理，不包含在本公开仓库中。

不要把 `.env`、License 文件、激活码、Token、私钥、部署指纹、数据库连接串或现场拓扑提交到公开仓库、公开工单或聊天群。
