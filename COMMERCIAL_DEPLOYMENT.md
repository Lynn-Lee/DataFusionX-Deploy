# DataFusionX Enterprise 商业私有化部署方案

> 文档状态：L1 商业交付权威。商业部署包、镜像形态、验签和交付边界以本文为准。

本文用于 DataFusionX Enterprise 商业私有化部署。商业部署包只包含固定版本商业镜像引用、部署编排文件、Helm Chart、环境变量模板和校验清单，不向客户交付后端源码、前端源码、构建脚本私钥或 `License-Server-Center` 源码。离线客户仍可由发布方额外提供镜像 tar 包。

## 交付形态

- 后端使用 `backend/Dockerfile.commercial` 构建商业镜像，`backend/app/core`、`backend/app/models`、`backend/app/services`、`backend/app/worker`、`backend/app/api/deps.py` 和 `backend/app/api/v1/routes` 会在构建阶段通过 Nuitka 编译为平台相关扩展模块，并删除这些目录内的业务源码文件。`backend/app/api/v1/router.py`、Pydantic schema 和必要包初始化文件保留源码，以保证框架路由聚合、反射和 OpenAPI 生成稳定。
- 前端使用 Vite 生产构建产物，禁用 sourcemap，并使用 Terser 压缩、移除注释、删除 `console` / `debugger`、启用顶层变量混淆；最终只交付 Nginx 静态资源镜像。
- 客户部署可以使用 `deploy/docker-compose.commercial.yml` 或 `deploy/helm/datafusionx-commercial`，二者只引用已构建镜像，不包含源码 build context。
- 商业编排中的 CDC Guard Worker 使用 `python -c "from app.worker.cdc_guard_worker import main; main()"` 入口启动，以兼容 Nuitka 编译后的 worker 扩展模块；现场不要改回 `python -m app.worker.cdc_guard_worker`。
- `scripts/build-commercial-release.sh` 可生成两种交付形态：默认本地离线包会包含镜像 tar；CI 公开商业包会推送固定版本 GHCR 镜像，并只打包 Docker Compose、Helm Chart、用户文档、`CUSTOMER_DELIVERY_CHECKLIST.md`、`checksums.txt`、`release-manifest.json` 和 `release-manifest.sig`。
- 商业后端镜像构建阶段会生成客户/交付批次水印和核心文件完整性 manifest，并用公司 Ed25519 发布私钥签名；Web、Celery Worker、Celery Beat 和 CDC Guard Worker 启动时会使用 `COMMERCIAL_INTEGRITY_PUBLIC_KEY` 校验 manifest 签名和关键文件 hash。商业构建标记会强制启用完整性校验，不能通过把 `COMMERCIAL_INTEGRITY_REQUIRED=false` 作为普通环境变量来关闭。

## 构建商业交付包

在研发或发布环境执行：

```bash
python scripts/commercial-manifest.py generate-keypair
export COMMERCIAL_MANIFEST_PRIVATE_KEY=<公司发布签名私钥>
export DATAFUSIONX_COMMERCIAL_CUSTOMER_ID=<公开发布水印，默认 public-release>
export DATAFUSIONX_COMMERCIAL_DELIVERY_ID=<交付批次，默认使用版本号>
export DATAFUSIONX_COMMERCIAL_DISTRIBUTION_MODE=<public-release>
scripts/build-commercial-release.sh 1.0.0
```

`COMMERCIAL_MANIFEST_PRIVATE_KEY` 必须保存在发布机或 CI/CD secret 中，不得写入仓库、镜像、`.env` 或商业部署包。商业 Dockerfile 通过 BuildKit secret 读取私钥，避免私钥进入镜像层历史。
`COMMERCIAL_MANIFEST_PUBLIC_KEY` 已固定为 `7sE7Bn3CJGIAd-CCDpeX-05wjTFsaS4kbM3vKU0tWNM`，脚本会自动写入商业部署包 `.env.example` 和 Helm values 的 `COMMERCIAL_INTEGRITY_PUBLIC_KEY` / `commercialIntegrityPublicKey`。

在离线、半离线或访问默认 Debian / PyPI 源较慢的私有化环境，可以在构建时临时指定镜像源：

```bash
DATAFUSIONX_APT_MIRROR=http://mirrors.cloud.aliyuncs.com/debian \
PIP_INDEX_URL=https://mirrors.aliyun.com/pypi/simple \
DATAFUSIONX_NPM_REGISTRY=https://registry.npmmirror.com \
COMMERCIAL_MANIFEST_PRIVATE_KEY=<公司发布签名私钥> \
scripts/build-commercial-release.sh 1.0.0
```

上述变量只影响商业镜像构建阶段的依赖下载源，不会写入运行期 `.env`、客户 License 或业务配置。

生成目录：

```text
dist-commercial/datafusionx-enterprise-1.0.0/
  images/
    datafusionx-backend-commercial-1.0.0.tar
    datafusionx-frontend-commercial-1.0.0.tar
  deploy/
    docker-compose.yml
  helm/
    datafusionx-commercial/
  tools/
    commercial-manifest.py
  .env.example
  README.md
  INSTALLATION.md
  OPERATIONS_UPGRADE.md
  USER_GUIDE.md
  CUSTOMER_DELIVERY_CHECKLIST.md
  COMMERCIAL_DEPLOYMENT.md
  preflight-upgrade.sh
  rollback.sh
  upgrade.sh
  verify-license.sh
  checksums.txt
  release-manifest.json
  release-manifest.sig
```

交付验签：

```bash
python tools/commercial-manifest.py verify-release \
  --package-dir dist-commercial/datafusionx-enterprise-1.0.0 \
  --public-key <公司发布验签公钥>
```

正式发布时还应在交付单中记录镜像 digest、公开发布批次和 License 授权号。签名私钥不得进入本仓库、镜像和商业部署包。

公开商业发布必须满足以下规则：

- `Lynn-Lee/DataFusionX-Deploy` 是 DataFusionX Enterprise 的公开下载、推广和用户部署主通道，公开包默认使用 `DATAFUSIONX_COMMERCIAL_CUSTOMER_ID=public-release` 作为水印。
- 真实客户 ID、激活码、客户部署指纹、正式 License、授权中心 token、私钥、真实 `.env`、现场 runbook、真实拓扑、源码和 sourcemap 不得进入公开部署仓库。
- 客户商业使用由 `License-Server-Center` 签发的在线或离线 License 控制；公开包可被下载，但未授权部署只能停留在授权受限状态。
- 公开发布 workflow 固定使用 `public-release` 水印；如本地脚本临时覆盖 `DATAFUSIONX_COMMERCIAL_CUSTOMER_ID`，该值会进入发布包和镜像 label，只能填写非敏感水印，不得填写需要保密的真实客户信息。
- 商业部署包中的用户文档和 `CUSTOMER_DELIVERY_CHECKLIST.md` 必须随版本发布记录一起留档。

公开部署包包含面向用户重新编写的文档：

- `README.md`：公开仓库首页和快速开始。
- `INSTALLATION.md`：安装部署指南。
- `OPERATIONS_UPGRADE.md`：运维与升级指南。
- `USER_GUIDE.md`：产品使用手册。
- `CUSTOMER_DELIVERY_CHECKLIST.md`：客户部署检查清单。

如需生成公开下载包并推送镜像：

```bash
DATAFUSIONX_VERSION=1.0.0 \
DATAFUSIONX_IMAGE_REPOSITORY=ghcr.io/<org>/datafusionx \
DATAFUSIONX_PUSH_IMAGES=true \
DATAFUSIONX_SAVE_IMAGES=false \
COMMERCIAL_MANIFEST_PRIVATE_KEY=<公司发布签名私钥> \
DATAFUSIONX_COMMERCIAL_CUSTOMER_ID=public-release \
scripts/build-commercial-release.sh
```

该模式生成 `dist-commercial/DataFusionX-Enterprise-v1.0.0.tar.gz` 和 `.sha256`，包内 `.env.example` 固定引用：

```text
ghcr.io/<org>/datafusionx-backend:1.0.0
ghcr.io/<org>/datafusionx-frontend:1.0.0
```

## 自动公开商业发布

DataFusionX Enterprise 使用 `.github/workflows/commercial-release.yml` 自动生成客户可直接下载的商业部署包。

触发方式：

- 推送到 `main`：只触发源码 CI 和版本记录，不构建商业部署包。
- 推送到 `release/**`：生成候选版本，例如 `0.1.0-rc.123.abcdef0`，用于内部预验收；默认不发布到公开部署仓库。
- 推送正式 tag `vX.Y.Z`：生成正式版本 `X.Y.Z`，并同步 `Lynn-Lee/DataFusionX-Deploy`，作为最终商业交付版本。
- 手动 `workflow_dispatch`：填写 `version` 时生成指定版本；留空时生成快照版本；默认不发布到公开部署仓库，只有显式勾选 `publish_public_repo` 时才公开发布。

工作流会自动执行：

1. 构建商业后端镜像和商业前端镜像。
2. 推送固定版本镜像到 `ghcr.io/lynn-lee/datafusionx-backend:<version>` 和 `ghcr.io/lynn-lee/datafusionx-frontend:<version>`。
3. 渲染公开商业部署包，包内 Compose 和 Helm 只引用固定版本镜像。
4. 生成 signed `release-manifest`、`.tar.gz` 和 `.sha256`。
5. 校验部署包不包含源码、私钥、真实 License、激活码、客户部署指纹、授权中心 token、现场 runbook、真实拓扑、sourcemap、浮动镜像标签或源码构建配置，并校验用户文档、客户交付清单、商业构建水印和后端受保护目录源码清理状态。
6. 仅正式 tag 或显式手动发布时，同步最新部署入口到 `Lynn-Lee/DataFusionX-Deploy` 根目录，并将版本压缩包追加到 `releases/v<version>/`。

为避免 GitHub Actions 制品存储配额被大包耗尽，商业部署包默认不上传为 Actions artifact；如确需临时留存，可配置仓库变量 `ENABLE_COMMERCIAL_RELEASE_ARTIFACT=true`。

客户部署时可从公开部署仓库 clone 最新稳定部署入口：

```bash
git clone https://github.com/Lynn-Lee/DataFusionX-Deploy.git
cd DataFusionX-Deploy
cp .env.example .env
docker compose -f deploy/docker-compose.yml --env-file .env config --quiet
docker compose -f deploy/docker-compose.yml --env-file .env pull
docker compose -f deploy/docker-compose.yml --env-file .env up -d
```

也可以下载固定版本压缩包：

```bash
curl -LO https://github.com/Lynn-Lee/DataFusionX-Deploy/raw/main/releases/v1.0.0/DataFusionX-Enterprise-v1.0.0.tar.gz
curl -LO https://github.com/Lynn-Lee/DataFusionX-Deploy/raw/main/releases/v1.0.0/DataFusionX-Enterprise-v1.0.0.tar.gz.sha256
shasum -a 256 -c DataFusionX-Enterprise-v1.0.0.tar.gz.sha256
tar -xzf DataFusionX-Enterprise-v1.0.0.tar.gz
cd DataFusionX-Enterprise-v1.0.0
cp .env.example .env
```

升级既有商业部署时，应复用上一版本 `.env`，仅替换 `DATAFUSIONX_VERSION`、`DATAFUSIONX_BACKEND_IMAGE` 和 `DATAFUSIONX_FRONTEND_IMAGE` 为目标固定版本，并保留 License、密钥、部署 ID、数据库密码和外部数据面连接配置。升级前先执行：

```bash
DEFAULT_ADMIN_PASSWORD='<管理员密码>' ./preflight-upgrade.sh
```

脚本会检查固定版本镜像、关键环境变量、Compose 配置、商业 release manifest、PostgreSQL 元数据库备份、License volume 备份、运行中任务、健康检查和 License 状态。通过后可执行：

```bash
DEFAULT_ADMIN_PASSWORD='<管理员密码>' ./upgrade.sh
DEFAULT_ADMIN_PASSWORD='<管理员密码>' ./verify-license.sh
```

升级后必须验证 `/api/v1/health` 返回目标版本，前端首页可访问，backend、celery worker 和 CDC Guard worker 均运行正常。单 app 或主调度节点上 celery beat 必须运行正常；多 app HA 部署的非主节点必须保持 celery beat stopped / disabled，发布脚本不得在非主节点重启或 enable celery beat。静态资源还应包含当前品牌文案：`Plan the Sync, Guard the Change`、`DataFusionX Enterprise. Control-Plane Orchestration, DDL 卫士, Run Observability. Copyright © 2026 Lynn-Lee. All rights reserved.` 和 `DFX Enterprise｜规划同步 · 守护变`。

如需回滚，使用 preflight 输出的备份目录：

```bash
BACKUP_DIR='./backups/preflight-<时间戳>' CONFIRM_ROLLBACK=1 ./rollback.sh
DEFAULT_ADMIN_PASSWORD='<管理员密码>' ./verify-license.sh
```

`backups/preflight-<时间戳>/env.full.local`、`env.rollback.local`、`metadata.dump` 和 `licenses.tgz` 是本机敏感回滚材料，不得进入工单、公开聊天、公开仓库或交付包。对外排查只共享 `env.redacted`、`compose.rendered.yml`、`health.json`、`license-status.json` 和 `preflight-summary.txt`。

公开仓库是商业版下载和推广入口，但不是授权边界；授权边界由 `License-Server-Center` 签发的 License、客户 ID、部署指纹、版本范围、功能和额度共同控制。发布方应记录压缩包 sha256、release manifest 签名、后端镜像 digest、前端镜像 digest、公开发布批次和 License 授权号。

GitHub Secrets 必须配置：

```text
COMMERCIAL_MANIFEST_PRIVATE_KEY
PUBLIC_RELEASES_TOKEN
```

`COMMERCIAL_MANIFEST_PRIVATE_KEY` 只用于商业镜像完整性 manifest 和商业发布包 manifest 签名，不得放入仓库和商业部署包。发布验签公钥已内置为 `7sE7Bn3CJGIAd-CCDpeX-05wjTFsaS4kbM3vKU0tWNM`，不需要配置为 GitHub Secret。`PUBLIC_RELEASES_TOKEN` 必须能写入 `Lynn-Lee/DataFusionX-Deploy`，建议只授予该公开仓库的 contents read/write 权限。该 token 不得进入商业部署包、公开仓库或任何示例 `.env`。

## 公开部署仓库切换状态

DataFusionX Enterprise 当前以 `Lynn-Lee/DataFusionX-Deploy` 作为专属公开部署仓库。私有源码仓库仍是唯一研发、构建、签名和发布源头；公开部署仓库只保存用户部署入口、用户文档、校验工具、固定版本镜像引用和历史版本压缩包。旧多产品发布总仓如继续保留，只作为历史导航入口，不再由 DataFusionX Enterprise workflow 写入产品目录，避免两个公开入口内容漂移。

对齐项：

- 触发策略：`main` 只做源码 CI 和版本记录，`release/**` 生成 RC 候选包，正式 `vX.Y.Z` tag 生成最终商业交付包，手动 `workflow_dispatch` 用于临时包；正式 tag 和显式手动发布才同步 `Lynn-Lee/DataFusionX-Deploy`。
- 版本规则：正式 tag 和手动版本生成稳定版本，`release/**` 生成 `<base>-rc.<run_number>.<short_sha>` 候选版本，手动留空生成 `<base>-dev.<run_number>.<short_sha>` 快照版本。
- 镜像规则一致：后端和前端商业镜像推送到 GHCR，商业部署包只引用固定版本标签，不使用 `latest`。
- 公开仓库规则：根目录保存最新稳定部署入口，`releases/v<version>/` 保存历史版本压缩包和 sha256 文件。
- 安全检查一致：发布包和公开目录不得包含源码、私钥、授权中心 token、真实 License、现场 runbook、真实拓扑、sourcemap、源码 `build:` 配置或浮动镜像标签。
- 授权中心一致：在线激活、在线刷新和离线授权均通过 `License-Server-Center`，并固定提交各自产品码。

DataFusionX Enterprise 当前保留的产品差异：

- 包格式为 `DataFusionX-Enterprise-v<version>.tar.gz`。
- DataFusionX Enterprise 使用 `scripts/build-commercial-release.sh` 一个入口完成镜像构建、部署包渲染、签名和压缩。
- DataFusionX Enterprise 商业包内置 `tools/commercial-manifest.py`、`release-manifest.json` 和 `release-manifest.sig`，并使用固定商业发布验签公钥校验发布包。
- DataFusionX Enterprise 当前商业包已包含 Docker Compose、Helm Chart、环境模板、用户文档、商业部署说明、`LEGAL-NOTICE.md`、`preflight-upgrade.sh`、`upgrade.sh`、`rollback.sh`、`verify-license.sh`、Nginx 配置示例和截图目录说明。
- DataFusionX Enterprise 的商业发布签名 secret 名称为 `COMMERCIAL_MANIFEST_PRIVATE_KEY`。

## 客户部署流程

如果客户环境无法访问 GHCR，可使用离线交付包中的镜像 tar。客户现场导入镜像：

```bash
docker load -i images/datafusionx-backend-commercial-1.0.0.tar
docker load -i images/datafusionx-frontend-commercial-1.0.0.tar
```

复制环境变量模板：

```bash
cp .env.example .env
```

必须配置：

```text
POSTGRES_PASSWORD
JWT_SECRET_KEY
ENCRYPTION_SECRET_KEY
ACCESS_TOKEN_EXPIRES_MINUTES（默认 480，即 8 小时，可按客户安全策略调整）
LICENSE_PUBLIC_KEY
LICENSE_DEPLOYMENT_ID
COMMERCIAL_INTEGRITY_PUBLIC_KEY
```

`LICENSE_DEPLOYMENT_ID` 是客户部署的稳定设备种子，生成后不要随意变更；变更会导致部署指纹变化，需要重新签发或迁移 License。
`COMMERCIAL_INTEGRITY_PUBLIC_KEY` 是商业发布验签公钥，商业部署包默认已配置为 `7sE7Bn3CJGIAd-CCDpeX-05wjTFsaS4kbM3vKU0tWNM`；它不是 License 公钥，二者可以分离管理。

启动：

```bash
docker compose -f deploy/docker-compose.yml --env-file .env up -d
```

默认访问：

```text
前端：http://localhost:8080
后端：http://localhost:18000
```

## Helm 部署流程

客户 Kubernetes 环境可使用随包交付的 Helm Chart：

```bash
helm upgrade --install datafusionx ./helm/datafusionx-commercial \
  --set global.version=1.0.0 \
  --set image.backend=datafusionx-backend-commercial:1.0.0 \
  --set image.frontend=datafusionx-frontend-commercial:1.0.0 \
  --set global.publicUrl=https://datafusionx.example.com \
  --set secrets.postgresPassword=<数据库密码> \
  --set secrets.jwtSecretKey=<至少 32 位 JWT 密钥> \
  --set secrets.encryptionSecretKey=<至少 32 位加密密钥> \
  --set secrets.licensePublicKey=<License 公钥> \
  --set secrets.licenseDeploymentId=<稳定部署 ID>
```

Helm Chart 默认包含 PostgreSQL、Redis、Backend、Frontend、Celery Worker、Celery Beat 和授权文件 PVC；生产客户如已有托管 PostgreSQL/Redis，可基于该 Chart 调整外部依赖接入。无论使用 Compose、Helm 还是 systemd，`Celery Beat` 都应按单实例调度器管理；多 app 节点不能同时常驻运行多个 Beat，Redis 锁只作为重复派发的兜底保护。

## 在线激活

系统管理员登录后进入系统健康页，填写客户 ID 和在线激活码，DataFusionX Enterprise 会请求 `License-Server-Center`：

```text
POST /api/v1/licenses/activate
```

请求会携带：

- `project=datafusionx`
- `product=datafusionx`
- `customer_id`
- `deployment_fingerprint`
- 当前用量快照
- 运行时版本和环境信息

授权中心返回 signed License 后，DataFusionX Enterprise 使用内置 Ed25519 public key 验签，保存到 `license_records` 和 `/app/licenses/datafusionx-license.json`。

## 离线激活

客户无法访问授权中心时：

1. 系统管理员进入系统健康页。
2. 填写客户 ID。
3. 点击“生成离线申请”。
4. 将生成的 JSON 发回授权运营侧。
5. `License-Server-Center` 根据申请中的 `deployment_fingerprint` 签发离线 License。
6. 客户把 signed License JSON 粘贴到“离线 License JSON”并导入。

离线申请不包含私钥或敏感连接凭据，只包含客户 ID、部署指纹、版本、环境和用量快照。

离线 License 响应仍必须是授权中心使用 Ed25519 私钥签发的 signed License。DataFusionX Enterprise 导入时会校验项目码、客户 ID、部署指纹、有效期、版本范围、功能和额度；如果 `allowed_versions`、`min_version` 或 `max_version` 不允许当前 `APP_VERSION`，导入会失败。

## 授权与源码保护边界

DataFusionX Enterprise 客户侧只内置 Ed25519 public key，`License-Server-Center` 私钥只保存在授权中心。客户无法通过修改本地 License JSON 伪造签名。

DataFusionX Enterprise 后端会按 License 中的 `features` 和 `limits` 做商业版能力拦截。功能键覆盖项目、用户、连接、CDC、Batch、Batch 调度、DDL 卫士和告警通知；额度键覆盖用户数、项目数、任务数、源端连接数、目标端连接数和总连接数，目标端统一使用 `target_connections`。客户修改前端或直接调用 API 时，后端仍会返回 `LICENSE_FEATURE_DISABLED` 或 `LICENSE_LIMIT_EXCEEDED`。

私有化部署无法绝对阻止拥有主机 root 权限的客户逆向或修改运行环境。本方案通过以下方式提高篡改成本：

- 不交付源码仓库。
- 后端商业镜像删除核心业务目录、API 依赖和业务路由 `.py` 源码，仅保留编译扩展模块、路由聚合壳层、schema 和必要包初始化文件。
- Nuitka 编译阶段会去除 docstring、启用 LTO，并在可用时对扩展模块执行 `strip --strip-unneeded`，减少可读符号和调试信息。
- 前端禁用 sourcemap，使用 Terser 压缩和顶层变量混淆，只交付压缩后的静态产物。
- 生产环境默认 `LICENSE_REQUIRED=true`；商业构建版本会根据镜像内置商业标记强制要求 License，并强制执行生产级启动安全检查，不能通过把 `ENVIRONMENT` 改为 `local` 或把 `LICENSE_REQUIRED` 改为 `false` 来关闭授权拦截。
- 授权绑定客户 ID、部署指纹、版本、到期时间、功能和额度。
- 交付包生成 `checksums.txt` 和 signed `release-manifest`，客户可用公司发布公钥验签。
- 商业镜像启动时强制校验 signed integrity manifest，关键文件、API 壳层、schema、商业构建水印或编译模块被替换或删除时拒绝启动。
- 公开商业发布通过镜像 label 和商业构建水印记录发布水印与交付批次，便于定位公开版本来源。
- workflow 会阻止源码、私钥、真实 License、激活码、客户部署指纹、授权中心 token、现场 runbook、真实拓扑、sourcemap、浮动镜像标签或源码构建配置误发到公开部署仓库。

## 法务兜底条款

商业合同、报价单、交付单或 EULA 应明确禁止以下行为：

- 对 DataFusionX Enterprise 商业镜像、前端产物、License 文件或发布包进行逆向、反编译、反汇编、规避授权校验或绕过完整性校验。
- 修改、删除、替换商业版完整性 manifest、签名、公钥、授权校验逻辑或额度控制逻辑。
- 未经书面许可复制、出租、转让、托管、二次销售、二次分发 DataFusionX Enterprise 商业部署包。
- 将商业部署包用于授权客户、授权部署 ID、授权环境或授权期限之外的场景。
- 泄露、共享、转售激活码、离线 License、部署指纹或交付镜像。

技术保护不能替代合同约束；法务条款用于补齐客户拥有主机管理员权限时的追责边界。

## 运维注意事项

- 不要把 `.env`、真实数据库连接串、Token、私钥、云服务凭据、SSH Host、凭据路径、现场 runbook、客户部署指纹或真实拓扑提交到仓库。
- 不要在客户侧部署 `License-Server-Center` 私钥。
- 在线授权会由 Celery Beat 每天自动刷新；离线授权只做本地验签和到期检查。
- 授权过期、吊销、冻结或本地验签失败时，业务 API 返回 `LICENSE_REQUIRED`。
