# DataFusionX Enterprise 产品使用手册

当前发布版本：`0.1.0-deploy-smoke`

DataFusionX Enterprise 是企业私有化数据同步控制台。它负责连接管理、任务配置、执行计划生成、Flink SQL 作业提交、运行观测、调度、审计、授权和权限治理。它不托管生产数据面资源，不自动创建 Kafka Topic、Debezium Connector、TiCDC Changefeed、Flink 集群、生产目标表或数据库授权 SQL。

## 首次使用流程

1. 系统管理员登录控制台。
2. 完成 License 在线激活或离线导入。
3. 创建项目。
4. 添加项目成员并分配角色。
5. 配置源端连接和目标端连接。
6. 创建 CDC、Batch 或 SQL 作业。
7. 发布执行计划并完成审批。
8. 启动作业或配置调度。
9. 在运行中心查看状态、指标、日志、告警和一致性校验。

## 角色

- `viewer`：只读查看项目资源、任务和运行状态。
- `operator`：管理连接、同步任务和 SQL 作业，但不能管理成员和审批。
- `admin`：管理项目、成员、审批、资源授权和关键治理动作。

## License

未授权或 License 过期时，业务 API 会受到限制。客户应在系统健康或授权管理入口查看：

- 当前客户 ID。
- 部署指纹。
- License 有效期。
- 授权功能。
- 授权额度。
- 在线刷新或离线导入状态。

## 连接管理

源端支持 MySQL、TiDB、PostgreSQL、Oracle 和 SQL Server。目标端支持 StarRocks、MySQL、TiDB、PostgreSQL、Oracle 和 SQL Server。

连接密码会加密保存，接口响应不会返回明文密码。编辑连接时，不填写密码表示保留原凭据。

## CDC 同步

CDC 同步消费客户外部已创建的 Kafka Topic，经外部 Flink SQL Gateway 提交作业写入目标端。发布 CDC 作业前应确认：

- Kafka Topic 已由客户外部创建。
- Debezium、Canal 或 TiCDC 消息格式符合兼容矩阵。
- 目标表已存在。
- 关系型目标端具备兼容主键或唯一约束。
- 不存在同 JDBC endpoint、同库、同 schema、同表的自循环风险。
- DDL 卫士策略符合现场要求。

## Batch 同步

Batch 同步适合全量、增量、回灌和切片批处理。系统支持从多张源表批量生成多个单表任务草稿，但仍保持一表一任务、一表一执行计划、一表一运行观测。

Batch 运行后可查看：

- 条数校验。
- 主键抽样比对。
- 关键字段 checksum。
- 失败分类和告警。

校验失败只产生告警和审计，不自动修改目标端数据。

## SQL 作业

SQL 作业只提交到外部 Flink SQL Gateway，不直接 JDBC 连接生产库执行 SQL。

支持：

- `SINGLE_SQL` 单 SQL 作业。
- `SEQUENTIAL_BATCH` 多步骤串行跑批。
- 参数定义、默认值、枚举、数值范围和字符串正则约束。
- 输入资产和输出资产声明。
- 发布审批、调度、停止、刷新、失败续跑和结果预览。

默认阻断生产表级 `DROP`、`ALTER`、`TRUNCATE`、`DELETE`、`UPDATE`、`MERGE`、`GRANT`、`REVOKE` 等高危语句。

## 运行中心

运行中心统一展示 CDC、Batch 和 SQL 作业运行记录。常用排查入口：

- 状态和失败分类。
- Flink Job 状态。
- Kafka lag。
- 端到端事件延迟。
- Flink Slot 容量快照。
- 步骤日志和最终 SQL。
- 告警和一致性校验。

## 告警通知

支持企业微信、飞书、Slack、邮件、通用 Webhook 和 Alertmanager。Webhook URL、签名密钥和邮件配置中的敏感字段会加密保存并脱敏展示。

## 审计

关键动作会写入审计，包括发布执行计划、审批、部署作业、调度启停、运行重试、DDL 卫士确认、审计清理和配置导入导出。

审计日志支持脱敏 CSV 导出和按保留天数清理。

## 安全边界

DataFusionX Enterprise 只做控制面。以下资源必须由客户外部准备和治理：

- Kafka Topic。
- Debezium Connector。
- TiCDC Changefeed。
- Flink 集群和 Flink SQL Gateway。
- StarRocks 或关系型目标表。
- 数据库授权 SQL。
- 生产数据面资源容量和运维。
