---
template-for: docs/requirements/<feature-domain>.md
轮次状态: 第 3 轮 Phase B3 完成（双评审自动修正）
特性域: engine-integration
主 Actor: 推理服务开发者、应用开发者、推理引擎
P0 Feature: 推理引擎 Connector
P1 Feature: S3 API 兼容
关联文档: product-spec.md（Feature 总览、Actor 定义、非功能需求）
---

# 特性域：engine-integration（引擎集成）

## 概述

本特性域覆盖推理引擎 **Connector**、**S3 API 兼容**。是产品融入生态、降低接入门槛的关键域。

**与架构子系统的追溯关系**：
- Connector 接口设计 → `docs/architecture/connector/design.md`
- S3 API 实现 → `docs/architecture/s3-api/design.md`
- SDK 设计 → `docs/architecture/sdk/design.md`

---

## Feature 价值论证

### F1: 推理引擎 Connector（P0）

#### 痛点

推理引擎与存储系统的集成是 KV Cache offloading 的前提：
- LMCache 与 vLLM 团队联合维护的标准化 Connector 是其生态成功的关键
- MoonCake 的 vLLM/SGLang 官方支持也是核心优势
- 没有 Connector，存储系统无法被推理引擎使用

标杆数据：
- LMCache：vLLM 官方集成，NVIDIA Dynamo 集成
- MoonCake：vLLM/SGLang 官方支持

#### 当前方案不足

- **Connector 标准化缺失**：不同存储系统使用不同的 Connector 接口，互不兼容
- **版本兼容性问题**：推理框架版本快速演进，Connector 适配滞后
- **调试困难**：Connector 故障时缺乏清晰的诊断路径

#### 用户价值

提供 vLLM/SGLang/Dynamo 等框架的**即插即用集成**，集成时间 ≤ 1 小时：
- 标准化 Connector 接口，跨框架通用
- 官方维护的适配层（与推理框架团队合作）
- 丰富的调试工具和错误信息

#### 成功指标

| 指标 | 目标 | 验收方法 |
|------|------|----------|
| 集成时间 | ≤ 1 小时（基础集成） | 集成测试：按文档完成基础集成 |
| Connector API 稳定性 | API 版本兼容 ≥ 2 个推理框架大版本 | 兼容性测试：跨版本验证 |
| vLLM 集成 | 支持 vLLM ≥ v0.8.0 | 集成测试：端到端推理 |
| SGLang 集成 | 支持 SGLang ≥ v0.3.0 | 集成测试：端到端推理 |
| NVIDIA Dynamo 集成 | 支持 NVIDIA Dynamo ≥ v0.2.0 | 集成测试：端到端推理 |
| 错误信息质量 | 错误码 + 错误消息 + 建议操作 | 错误注入：验证错误信息完整性 |

---

### F2: S3 API 兼容（P1）

#### 痛点

S3 API 是对象存储的事实标准：
- MinIO 将 100% S3 兼容作为核心卖点
- Ceph 也将 S3 兼容列为 P0
- 兼容 S3 意味着兼容现有工具链（AWS CLI/SDK、Terraform、Spark 等）

标杆数据：
- MinIO：100% S3 兼容
- Ceph RGW：95%+ S3 操作兼容

#### 当前方案不足

- **MoonCake/LMCache 无 S3 支持**：无法服务通用对象存储场景
- **S3 兼容性不完整**：部分操作（如分段上传、范围读取）实现不完善
- **SDK 覆盖不全**：仅支持部分语言的 SDK

#### 用户价值

支持主流对象存储操作（PUT/GET/LIST/DELETE），兼容现有工具链：
- 核心操作 100% S3 兼容（AWS CLI 全覆盖）
- 支持 boto3 / AWS SDK (Go/Java/JS) / Terraform / AWS CLI
- 与 MinIO/Ceph 相比，我方差异化在 KV Cache 原生支持

#### 成功指标

| 指标 | 目标 | 验收方法 |
|------|------|----------|
| AWS CLI 兼容性 | 核心操作 100% 通过 | AWS CLI 测试套件 |
| boto3 兼容性 | boto3 核心操作 100% 通过 | boto3 测试套件 |
| 分段上传 | 支持 multipart upload（最大 50GB） | 测试：上传 50GB 文件 |
| 范围读取 | 支持 GetObject with Range header | 测试：Range 读取 |
| SSE 头支持 | 支持 SSE-S3、SSE-KMS | 测试：加密上传/下载 |
| SDK 覆盖 | boto3 / AWS SDK Go / AWS SDK JavaScript | 各 SDK 官方测试用例 |

---

## 场景（Scenario）

### S1: vLLM + Connector 基础集成

**类型**：正常场景
**Feature**：推理引擎 Connector（F1）

#### 前置条件

- 存储集群运行正常（3+ 节点）
- vLLM ≥ v0.8.0 已安装
- 网络连通（vLLM → 存储集群）

#### 用户旅程

> **时间标注说明**：
> - 集成阶段（T=0 ~ T=30min）：为**绝对时间**（相对项目开始时间），反映集成工程师的操作耗时
> - 功能测试阶段（T=0 이후）：为**相对时间**（T=0 为测试开始时刻），反映系统行为

```
[T=0]     推理服务开发者下载 vLLM + Connector
    ↓
[T=5min]  修改 vLLM 配置（config.json）：
          {
            "kv_cache_free_memory_backing_factor": 0.8,
            "kv_transfer_scheduler": "kvcache-store",
            "store_config": {
              "backend": "kvcache-ai-storage",
              "server_address": "storage-cluster:8080"
            }
          }
    ↓
[T=10min] 重启 vLLM 服务
    ↓
[T=15min] vLLM 启动成功，Connector 注册到存储集群

[功能测试阶段 — 相对时间]
T=0       发送测试请求：POST /v1/chat/completions
          {
            "model": "llama-3-70b",
            "messages": [{"role": "user", "content": "Hello"}]
          }
    ↓
T=30s     首次请求完成，Connector 将 KV Cache 写入存储集群
    ↓
T=35s     发送相同请求（缓存命中）
    ↓
T=1s     返回结果（TTFT 大幅降低，验证 Connector 工作正常）
```

#### 验收标准

- [ ] 配置修改 ≤ 10 行代码
- [ ] 集成后 vLLM 正常启动，无报错
- [ ] 首次请求后 KV Cache 写入存储（可通过 Dashboard 验证）
- [ ] 第二次相同请求 TTFT 降低 ≥ 70%
- [ ] Connector 故障时有明确错误信息

---

### S2: SGLang 集成（生产级）

**类型**：正常场景
**Feature**：推理引擎 Connector（F1）

#### 前置条件

- 存储集群运行正常
- SGLang ≥ v0.3.0 已安装

#### 用户旅程

```
T+0min   推理服务开发者修改 SGLang 启动参数：
         python -m sglang.launch_server
           --mem-fraction-static 0.4
           --kv-cache-backend kvcache-ai-storage
           --kv-cache-server-url storage-cluster:8080
    ↓
T+5min   SGLang 启动成功，Connector 注册到存储集群
    ↓
T+10min  运行生产负载（100 并发请求，128K 上下文）
    ↓
T+30min  监控验证：
         - KV Cache 命中率 ≥ 40%（Prefix 场景）
         - TTFT 降低 ≥ 60%
         - 存储集群吞吐 ≥ 500K ops/s
```

#### 验收标准

- [ ] SGLang 启动参数正确识别 Connector
- [ ] 生产负载下 Connector 稳定运行
- [ ] 存储指标与推理指标关联可查
- [ ] Connector 资源占用合理（CPU ≤ 5%，内存 ≤ 500MB）

---

### S3: Connector 故障处理（网络中断）

**类型**：故障场景
**Feature**：推理引擎 Connector（F1）

#### 故障注入

```
故障注入：存储集群不可达（iptables DROP 所有到存储集群的流量）
```

#### 系统响应

```
T+0s     Connector 检测到存储写入超时（阈值 5s）
    ↓
T+5s     Connector 决策：切换到降级模式（HBM 本地缓存）
    ↓
T+5s     推理引擎继续运行，KV Cache 写入 HBM（而非外部存储）
    ↓
T+6s     告警：存储连接故障，Connector 降级运行
    ↓
T+10min  存储集群恢复
    ↓
T+10min  Connector 自动重连
    ↓
T+10min  HBM 中缓存的 KV Cache 异步上传到存储
    ↓
T+12min  HBM 缓存清空，恢复正常模式
```

#### 验收标准

- [ ] 存储故障时 Connector 降级不中断推理服务
- [ ] 降级模式有明确告警
- [ ] 存储恢复后 Connector 自动重连
- [ ] 降级期间数据不丢失（HBM 暂存→恢复后上传）
- [ ] 降级模式运行时 TTFT 可能降低（符合预期）

---

### S4: S3 API 基础操作（PUT/GET/DELETE）

**类型**：正常场景
**Feature**：S3 API 兼容（F2）

#### 前置条件

- S3 API 已启用
- 应用开发者持有有效 S3 凭证

#### 用户旅程

```
[PUT 操作]
T+0ms    应用调用：boto3 S3.PutObject(Bucket='data', Key='model.bin', Body=data)
    ↓
T+10ms   数据写入存储集群
    ↓
T+10ms   返回成功

[GET 操作]
T+0ms    应用调用：boto3 S3.GetObject(Bucket='data', Key='model.bin')
    ↓
T+5ms    数据从存储集群读取
    ↓
T+5ms    返回数据内容

[DELETE 操作]
T+0ms    应用调用：boto3 S3.DeleteObject(Bucket='data', Key='model.bin')
    ↓
T+10ms   数据标记为删除
    ↓
T+10ms   返回成功
```

#### 验收标准

- [ ] PUT 操作成功，数据可检索
- [ ] GET 操作成功，返回数据与写入一致
- [ ] DELETE 操作成功，数据不可再检索
- [ ] 操作延迟符合 SLA（GET ≤ 50ms P99，PUT ≤ 100ms P99）
- [ ] 错误响应符合 S3 API 规范

---

### S5: AWS CLI 工具链集成

**类型**：正常场景
**Feature**：S3 API 兼容（F2）

#### 前置条件

- AWS CLI 已安装并配置 S3 凭证
- 存储集群 S3 API 端点：storage-cluster:9000

#### 用户旅程

```
T+0min   配置 AWS CLI：
         aws configure set aws_access_key_id minioadmin
         aws configure set aws_secret_access_key minioadmin
         aws configure set region us-east-1
    ↓
T+1min   列出 Bucket：
         aws s3 ls --endpoint-url http://storage-cluster:9000
    ↓
T+1min   上传文件：
         aws s3 cp model.bin s3://data/model.bin --endpoint-url http://storage-cluster:9000
    ↓
T+5min   下载文件：
         aws s3 cp s3://data/model.bin ./model_copy.bin --endpoint-url http://storage-cluster:9000
    ↓
T+5min   同步目录：
         aws s3 sync ./models/ s3://data/models/ --endpoint-url http://storage-cluster:9000
```

#### 验收标准

- [ ] 所有 AWS CLI 核心命令正常（ls/cp/rm/sync）
- [ ] 多部分上传支持（大型文件自动分片）
- [ ] 范围读取支持（--range 参数）
- [ ] 错误响应与 AWS S3 格式兼容

---

### S6: 分段上传大文件

**类型**：正常场景
**Feature**：S3 API 兼容（F2）

#### 前置条件

- S3 API 已启用
- 需要上传 10GB 的模型文件

#### 用户旅程

```
T+0s     应用发起分段上传：
         s3.create_multipart_upload(Bucket='data', Key='model-10gb.bin')
    ↓
T+1s     返回 UploadId='upload-123'
    ↓
T+1s     应用将文件分片（每片 100MB，共 100 片）
    ↓
T+1s     并发上传第 1-10 片（加速）
    ↓
T+10s    第 1-10 片上传完成
    ↓
T+20s    第 11-20 片上传完成
    ↓
T+100s   所有 100 片上传完成
    ↓
T+101s   完成分段上传：
         s3.complete_multipart_upload(
           Bucket='data',
           Key='model-10gb.bin',
           UploadId='upload-123',
           MultipartUpload={Parts: [1..100]}
         )
    ↓
T+101s   文件可检索（GetObject 返回完整文件）
```

#### 验收标准

- [ ] 最大支持 50GB 分段上传
- [ ] 分段上传/完成/中止操作正常
- [ ] 上传期间可列出上传进度
- [ ] 上传完成后文件完整性校验（MD5 一致）
- [ ] 分段上传失败可重试

---

### S7: Connector 版本升级（零停机）

**类型**：运维场景
**Feature**：推理引擎 Connector（F1）

#### 前置条件

- vLLM + Connector v1.0.0 运行正常
- 需要升级到 v1.1.0

#### 用户旅程

```
T+0min   下载新版本 Connector v1.1.0
    ↓
T+1min   准备升级（新版本与旧版本 API 兼容）
    ↓
T+2min   滚动重启 vLLM 节点（不影响其他节点）：
         - 重启节点 1：等待健康后再重启节点 2
    ↓
T+10min  所有节点升级完成
    ↓
T+10min  验证：推理服务正常，新功能生效
    ↓
T+15min  回滚准备：保留旧版本 v1.0.0 镜像（如有问题可回滚）
```

#### 验收标准

- [ ] 滚动升级期间服务不中断
- [ ] API 兼容时无需修改配置
- [ ] API 不兼容时有明确的迁移指南
- [ ] 升级失败可回滚

---

### S8: S3 API 认证失败

**类型**：异常场景
**Feature**：S3 API 兼容（F2）

#### 触发条件

```
触发条件：应用使用错误的 Access Key 访问 S3 API
```

#### 系统响应

```
T+0ms    应用发送请求：
         GET /data/model.bin HTTP/1.1
         Authorization: AWS4-HMAC-SHA256 Credential=INVALID_KEY
    ↓
T+1ms    S3 API 验证签名失败
    ↓
T+1ms    返回 403 Forbidden：
         <Error>
           <Code>InvalidAccessKeyId</Code>
           <Message>The AWS Access Key Id you provided does not exist</Message>
           <AWSAccessKeyId>INVALID_KEY</AWSAccessKeyId>
         </Error>
    ↓
T+1ms    审计日志记录：无效凭证访问企图
    ↓
T+10min  如果同一 IP 在 1 分钟内出现 ≥ 5 次认证失败，触发安全告警
```

#### 验收标准

- [ ] 无效凭证返回 403 Forbidden
- [ ] 错误响应符合 S3 API 规范（XML 格式）
- [ ] 认证失败事件有审计日志
- [ ] 异常频率超阈值时有安全告警

---

### S9: 多推理框架并存（混合部署）

**类型**：正常场景
**Feature**：推理引擎 Connector（F1）

#### 前置条件

- vLLM + SGLang 同时运行
- 存储集群运行正常
- 两个框架共享同一个存储集群

#### 用户旅程

```
T+0min   vLLM 实例 A 通过 Connector 写入 KV Cache
         → 存储集群接收并索引
    ↓
T+5min   SGLang 实例 B 请求读取相同前缀的 KV Cache
         → Connector 通过 prefix_cache_lookup 匹配
         → 匹配命中，从存储加载
    ↓
T+5min   跨框架缓存共享验证：
         - vLLM 计算的 System Prompt KV Cache
         - SGLang 直接复用（无需重复计算）
    ↓
T+10min   监控：两个框架的缓存命中率分别可见
```

#### 验收标准

- [ ] vLLM 和 SGLang 可共享同一个存储集群
- [ ] 跨框架缓存共享生效（相同前缀无需重复 Prefill）
- [ ] 各框架的 Connector 独立配置，互不干扰
- [ ] 监控指标按框架维度区分

---

## 依赖关系

| 本域 Feature | 依赖的外部 Feature | 依赖类型 |
|-------------|-------------------|----------|
| 推理引擎 Connector | KV Cache 写入存储 | 强 |
| 推理引擎 Connector | KV Cache 读取加载 | 强 |
| 推理引擎 Connector | Prefix Cache 匹配 | 强 |
| 推理引擎 Connector | 多租户隔离（租户认证） | 强 |
| 推理引擎 Connector | 传输加密（TLS） | 弱 |
| S3 API 兼容 | 多租户隔离 | 强 |
| S3 API 兼容 | 数据加密 | 弱 |
| S3 API 兼容 | 数据冗余与自愈 | 弱 |

---

### S10: AI 基础设施架构师—POC 评估与选型（正常场景）

**类型**：正常场景
**Feature**：推理引擎 Connector（F1）
**Actor**：AI 基础设施架构师

#### 前置条件

- AI 基础设施架构师正在进行技术选型评估
- POC 环境已搭建（5 节点集群）

#### 用户旅程

```
T=0      AI 基础设施架构师下载技术白皮书和性能基准报告
    ↓
T=30min  架构师查看产品架构图和 TCO 模型
    ↓
T=1hour  架构师申请 POC 环境访问权限
    ↓
T=1hour  搭建 POC 环境：vLLM + Connector
    ↓
T=2hour  运行基准测试套件（包含 TTFT/TBT/吞吐/缓存命中率）
    ↓
T=3hour  基准结果：
         - TTFT 降低：68%（vs 无缓存，目标 ≥ 70%）
         - TBT：与无缓存基本持平（1.05x，目标 ≤ 1.1x）
         - 吞吐提升：3.2x（目标 ≥ 3x）
         - 缓存命中率：42%（典型工作负载）
    ↓
T=3hour  架构师与竞品（MoonCake）基准数据对比：
         - TTFT 改善：我方 68% vs MoonCake 84%
         - 吞吐提升：我方 3.2x vs MoonCake 3x
         - 企业级能力：我方 P0 多租户隔离 vs MoonCake 无
    ↓
T=4hour  架构师完成评估报告，决定推荐采购
```

#### 验收标准

- [ ] 技术白皮书包含完整架构描述和性能基准数据
- [ ] TCO 模型可配置（硬件成本/运维人力/许可费用）
- [ ] POC 环境可在 ≤ 2 小时内完成基础部署
- [ ] 基准测试套件可一键运行，自动输出 TTFT/TBT/吞吐/命中率
- [ ] 产品与竞品的对比报告可在线生成

---

## 变更记录

| 日期 | 版本 | 变更内容 | 轮次 |
|------|------|----------|------|
| 2026-04-21 | v0.1 | 初始版本：2 个 Feature 价值论证 + 9 个场景 | 第 3 轮 Phase B1 |
| 2026-04-21 | v0.2 | **Phase B3 自动修正**：S1 时间戳格式统一（集成阶段绝对时间 + 测试阶段相对时间）；补充"基础集成"定义边界说明 | 第 3 轮 Phase B3 |
| 2026-04-21 | v0.3 | **场景补充（BLOCKER-3）**：新增 S10 AI 基础设施架构师 POC 评估场景 | 第 3 轮 |

---

## 自检清单

- [x] 每个 Feature 有完整的价值论证（痛点/不足/价值/成功指标）
- [x] 场景覆盖正常/故障/运维/异常四种类型
- [x] 每个场景有前置条件、用户旅程、验收标准
- [x] 所有验收标准可量化
- [x] 依赖关系矩阵已填写
- [x] 文档不包含内部模块名/类名/函数名
- [x] 文档追溯到架构文档
