# KV Cache Offloading 存储系统 — 全局需求总纲

> 版本: v1.0
> 日期: 2026-04-12
> 状态: 已评审 / 待验证假设
> 修正后置信度: 中 (70%)
> 置信度理由: chunk/block 粒度策略已补充并引用 ADR-004，但 RDMA 大规模部署的降级策略、热点 prefix 负载均衡等细节仍待进一步验证。

---

## 产品定位

本系统为面向大语言模型（LLM）推理场景的 **KV Cache Offloading 分布式缓存存储服务**。核心目标是将推理过程中生成的 KV Cache 从昂贵的 GPU HBM 卸载到成本更低的存储介质（DRAM、SSD、远程存储），并在后续请求的前缀匹配命中时快速加载复用，从而显著降低首 Token 时间（TTFT）、提升 GPU 利用率与整体吞吐。

## 部署环境

- **硬件**: NVIDIA GPU（A100/H100 为主，兼容降级路径），配备本地 DRAM 与 NVMe SSD
- **网络**: 优先支持 RoCE/RDMA，TCP 作为通用降级路径
- **编排**: Kubernetes 原生部署，支持 Helm / K8s manifest
- **监控**: Prometheus / Grafana，可选 OpenTelemetry Trace
- **目标引擎**: vLLM（MVP 深度适配），SGLang / TensorRT-LLM（预留扩展接口）

## 典型使用流程

1. **部署阶段**: 平台工程师通过 Helm 在 K8s 集群中部署缓存服务实例与全局元数据服务。
2. **集成阶段**: AI 应用开发者在推理引擎配置中启用 KV Cache Connector，完成握手与兼容性校验。
3. **运行阶段**: 推理引擎在 prefill 阶段将生成的 KV Cache 异步卸载到缓存服务；调度器在接收新请求时查询 prefix 匹配，命中则异步加载已缓存的 KV Cache。
4. **运维阶段**: 平台工程师通过监控面板观察命中率、延迟、容量趋势；根据需要执行扩容、缩容、策略调整或版本升级。
5. **故障阶段**: 节点故障或网络分区时，系统自动降级为 miss，引擎 fallback 到全量计算，不中断服务；故障恢复后副本自动修复。

---

## Actors

完整 Actor 定义与交互关系参见 [actors.md](actors.md)。以下给出核心 Actor 摘要：

| Actor | 类型 | 核心关注点 |
|-------|------|-----------|
| [AI 应用开发者](actors.md#1-ai-应用开发者-ai-application-developer) | 人类 | 易集成性、引擎兼容性、TTFT 收益、API 稳定性 |
| [平台工程师 / MLOps](actors.md#2-平台工程师--mlops-platform-engineer) | 人类 | 可观测性、K8s 原生支持、弹性伸缩、滚动升级无中断 |
| [系统管理员](actors.md#3-系统管理员-system-administrator) | 人类 | 节点级故障诊断、数据完整性、安全合规 |
| [推理引擎](actors.md#4-推理引擎-inference-engine) | 外部系统 | 最低侵入性、异步 API 零阻塞、加载失败安全降级 |
| [集群编排器](actors.md#5-集群编排器-cluster-orchestrator) | 外部系统 | 健康检查响应及时性、实例启停速度、状态持久化兼容 |
| [监控系统](actors.md#6-监控系统-monitoring-system) | 外部系统 | 指标覆盖完整、采集开销低、标签维度清晰 |
| [外部持久化存储](actors.md#7-外部持久化存储-external-persistent-storage) | 外部系统 | 高可用性 ≥ 99.9%、延迟上限可接受、带宽充足 |
| [缓存服务实例](actors.md#8-缓存服务实例-cache-service-instance) | 内部组件 | 本节点资源不超用、层级间高效迁移、故障快速释放 |
| [全局元数据服务](actors.md#9-全局元数据服务-global-metadata-service) | 内部组件 | 查询 P99 < 5ms、避免单点、最终一致窗口 < 100ms |
| [数据传输服务](actors.md#10-数据传输服务-data-transfer-service) | 内部组件 | 传输带宽高、CPU 开销低、错误可捕获、超时降级明确 |

---

## KV Cache 数据分块策略

本系统的 chunk/block 粒度策略遵循架构决策 [ADR-004](../adr.md#adr-004-cache-block粒度决策) 的分层异构粒度设计。以下是面向用户的粒度说明：

| 存储层级 | 粒度 | 说明 | 对 prefix 命中精度的影响 |
|----------|------|------|--------------------------|
| HBM (GPU 内存) | 16 tokens | 与 vLLM PagedAttention 对齐，最大化 GPU 内存利用率 | 最小复用单元为 16 tokens，短 prefix 也能精确命中 |
| DRAM (本地内存) | 256 tokens | 优化 PCIe 传输效率，LMCache 生产验证的可行粒度 | 命中长度按 256 tokens 向上取整，128~255 tokens 的 prefix 会加载 256 tokens，存在少量冗余读取 |
| SSD (本地磁盘) | 256 tokens (约 2MB 数据) | 基于 ADR-004 修正后的 SSD 最优 IO 大小，按 4KB 对齐头部元数据 | 同 DRAM 层，256 tokens 对齐；顺序 IO 效率最优 |
| Remote (分布式远端) | 65536 tokens | 最大化网络带宽利用率，减少跨节点 RPC 次数 | 最小复用单元大，适合长上下文冷数据的批量加载；短 prefix 命中时可能加载大量冗余数据 |

**配置说明**：
- HBM 和 DRAM 层粒度为系统默认，通常不建议修改，除非 workload 以超长序列（平均 > 4K tokens）为主。
- SSD 和 Remote 层粒度在部署时可通过配置参数调整，但需在初始化前确定，运行中不可动态变更。
- 同一 prefix 在不同层级之间命中时，系统会自动处理粒度对齐（如 HBM 16 tokens 与 DRAM 256 tokens 的转换），用户无需感知。

## 全局非功能需求摘要

以下提取自各特性域非功能需求及 features 草案，作为系统级验收的关键量化目标。

### 性能

| 子项 | 目标值 |
|------|--------|
| TTFT (cache hit) | P50 降低 ≥ 50% vs 无缓存基线；P99 降低 ≥ 33% |
| TTFT (cache miss) | 增量 < 15% vs 无缓存基线 |
| TPOT 影响 | 开启 offloading 后 P99 增量 < 5% |
| 加载延迟 | HBM→GPU < 1ms；DRAM→GPU P99 < 10ms；SSD→GPU P99 < 100ms；Remote→GPU P99 < 50ms (RDMA) / < 200ms (TCP) |
| 吞吐上限 | 单机 DRAM 传输 ≥ 40 GB/s；SSD 顺序读 ≥ 标称带宽 70% |

### 可用性

| 子项 | 目标值 |
|------|--------|
| 服务可用性 | 单节点 99.9% / 分布式 HA 模式 99.99% |
| 故障降级率 | 单节点/单盘故障时 100% 请求可降级为 miss 并完成推理 |
| 故障感知时间 | 节点无心跳到系统标记为故障 < 15s |
| RTO | 单节点故障后副本恢复或降级完成 < 5 分钟 |
| RPO | 已确认写入的数据 0 丢失；未确认写入允许丢失 |

### 容量与扩展性

| 子项 | 目标值 |
|------|--------|
| 单机缓存上限 | SSD ≥ 20TB；DRAM ≥ 512GB |
| 分布式缓存上限 | 10 节点集群 ≥ 100TB 聚合缓存 |
| 元数据内存上限 | 单机索引内存 < 5GB（支持 10K 活跃序列） |
| 节点扩展 | 新增节点 60s 内承担 ≥ 5% 写入；10 分钟内达到负载均衡 |
| 查询吞吐 | 单机实例 ≥ 10,000 QPS prefix 查询 |
| 线性扩展比 | 3 节点相对单节点有效查询吞吐 ≥ 2.5x |

### 一致性

| 子项 | 目标值 |
|------|--------|
| 索引一致性 | 允许最终一致性；不一致窗口 < 100ms |
| 数据完整性 | 已确认写入的数据 100% 通过 checksum 校验 |
| 并发安全 | 多引擎并发读写同一 prefix，返回数据 100% 一致 |
| 跨节点一致性 | 网络分区恢复后，各节点元数据视图 30s 内达成一致 |

### 安全

| 子项 | 目标值 |
|------|--------|
| 访问控制 | 未授权管理 API 请求 100% 拒绝 |
| 传输加密 | TCP 路径支持 TLS 1.3 |
| 数据隔离 | 多租户场景下跨租户访问 100% 拒绝 |
| 审计日志 | 所有管理操作记录审计日志，保留 ≥ 30 天 |

### 可观测性

| 子项 | 目标值 |
|------|--------|
| 指标覆盖 | ≥ 50 个 Prometheus 指标，覆盖 5 大维度 |
| 指标采集开销 | /metrics 响应 P99 < 50ms；主流程 CPU 占用 < 3% |
| Trace 完整性 | 1% 采样下端到端 span 缺失率 < 5% |
| 告警时效 | 关键故障 1 分钟内触发告警 |

---

## 文档地图

| 特性域 | 说明 | 文档链接 |
|--------|------|----------|
| Cache Offloading | Prefix Cache 加载、异步存储、跨层/跨节点迁移 | [cache-offloading.md](cache-offloading.md) |
| Data Lifecycle | 缓存写入与持久化、淘汰与分层迁移、数据清理与失效 | [data-lifecycle.md](data-lifecycle.md) |
| Engine Integration | 引擎连接与握手、调度器侧 Prefix 查询、Worker 侧异步流水线 | [engine-integration.md](engine-integration.md) |
| Cluster Management | 节点加入与退出、故障检测与自动恢复、负载均衡与容量调度 | [cluster-management.md](cluster-management.md) |
| Observability | 全链路性能指标、故障诊断与追踪、容量与成本分析 | [observability.md](observability.md) |

---

## 需求追溯关系

- **架构决策**: 全局架构约束与 ADR 记录参见 [docs/adr.md](../adr.md)
- **系统总纲与子系统架构**: [docs/architecture/README.md](../architecture/README.md)
- **接口规格**: [docs/interfaces/](../interfaces/)
- **迭代计划**: [docs/iteration-plan.md](../iteration-plan.md)（待补充）

---

## Actor → Feature Domain 快速索引

| Actor | 主要关注特性域 |
|-------|---------------|
| AI 应用开发者 | [engine-integration.md](engine-integration.md)、[cache-offloading.md](cache-offloading.md) |
| 平台工程师 / MLOps | [cluster-management.md](cluster-management.md)、[observability.md](observability.md)、[data-lifecycle.md](data-lifecycle.md) |
| 系统管理员 | [cluster-management.md](cluster-management.md)、[observability.md](observability.md) |
| 推理引擎 | [cache-offloading.md](cache-offloading.md)、[engine-integration.md](engine-integration.md)、[data-lifecycle.md](data-lifecycle.md) |
| 集群编排器 | [cluster-management.md](cluster-management.md) |
| 监控系统 | [observability.md](observability.md) |
| 外部持久化存储 | [data-lifecycle.md](data-lifecycle.md) |
| 缓存服务实例 | [cache-offloading.md](cache-offloading.md)、[data-lifecycle.md](data-lifecycle.md)、[cluster-management.md](cluster-management.md) |
| 全局元数据服务 | [cluster-management.md](cluster-management.md)、[cache-offloading.md](cache-offloading.md) |
| 数据传输服务 | [cache-offloading.md](cache-offloading.md)、[data-lifecycle.md](data-lifecycle.md) |
