# 里程碑计划

> **版本**：v0.3
> **规划日期**：2026-04-22
> **状态**：三重评审通过 ✅

---

## 文档追溯关系

| 追溯文档 | 路径 | 关系 |
|----------|------|------|
| 产品需求总纲 | `docs/requirements/product-spec.md` | Feature 清单（8 P0 / 11 P1 / 1 P2）是本计划的根本输入 |
| 系统架构总纲 | `docs/architecture/design.md` | 5 个子系统划分和 Phase 1/2/3 演进路线约束里程碑边界 |
| ADR 决策记录 | `docs/architecture/adr.md` | 9 个 ADR 的待验证假设驱动 Spike 验证任务和风险缓冲 |
| cache-offloading 特性域 | `docs/requirements/cache-offloading.md` | 3 P0 + 2 P1 Feature 的场景和验收标准 |
| data-lifecycle 特性域 | `docs/requirements/data-lifecycle.md` | 2 P0 + 2 P1 + 1 P2 Feature |
| cluster-management 特性域 | `docs/requirements/cluster-management.md` | 1 P0 + 3 P1 Feature |
| security-governance 特性域 | `docs/requirements/security-governance.md` | 1 P0 + 3 P1 Feature |
| engine-integration 特性域 | `docs/requirements/engine-integration.md` | 1 P0 + 1 P1 Feature |

---

## 执行摘要

**项目规模**：面向 LLM 推理场景的企业级分布式对象存储系统（KV Cache Offloading Storage），C 语言开发，Linux 环境，5 个子系统（存储引擎 / 元数据服务 / 传输层 / 调度器 / 连接器）。

**时间跨度**：12 个月，分 4 个里程碑。

**团队 Velocity 假设**：
- 团队规模：4-6 名 C 语言开发工程师 + AI 辅助编码
- AI 辅助编码范式下的 Velocity 校准：传统估算的 0.6-0.7 倍（AI 加速编码但增加集成调试成本，RDMA/SPDK 等底层系统编程 AI 辅助效果有限）
- 单迭代周期：2 周
- 单迭代容量：20-30 故事点（基于 AI 辅助编码范式）
- 故事点定义：S=1-2 点（1 周内）/ M=3-5 点（1-2 周）/ L=8-13 点（2-4 周）/ XL=21+ 点（必须拆解）

**整体规模估算**：
- M1（MVP）：~180-220 故事点，6 个迭代（12 周）
- M2（增强）：~150-180 故事点，6 个迭代（12 周）
- M3（成熟）：~120-150 故事点，6 个迭代（12 周）
- M4（企业级）：~80-100 故事点，4 个迭代（8 周）
- **总计**：~530-650 故事点，约 44-48 周

**关键约束**：
- 4/9 ADR 置信度 <= 68%（ADR-003/004/008/009），需在 M1 前 4 周集中验证
- SPDK + RDMA 技术栈团队首次接触，学习曲线风险
- 子系统架构文档（`docs/architecture/<subsystem>/design.md`）均为"待产出"状态，需在 M1 早期完成

---

## 里程碑划分

| 里程碑 | 周期估算 | 故事点范围 | 核心交付 | 对应 Phase | 对应 Feature |
|--------|----------|-----------|---------|-----------|-------------|
| **M1: MVP 端到端可运行** | 12 周（6 迭代） | 180-220 SP | 端到端 KV Cache 写入/读取/Prefix 命中，单集群 4 节点可运行 | Phase 1 | 8 P0 Feature 的 MVP 子集 |
| **M2: 性能增强与生产就绪** | 12 周（6 迭代） | 150-180 SP | 性能优化 + PD 调度增强 + TCP 降级 + 基础可观测性 | Phase 2 前半 | P1 核心 Feature（PD 传输、可观测性、数据压缩） |
| **M3: 企业级能力** | 12 周（6 迭代） | 120-150 SP | 多租户完善 + QoS + 审计 + S3 API + 加密 | Phase 2 后半 + Phase 3 前半 | P1 企业级 Feature |
| **M4: 大规模验证与成熟** | 8 周（4 迭代） | 80-100 SP | 100+ 节点验证 + 跨版本升级 + 快照克隆 + 跨区域复制评估 | Phase 3 | P1 剩余 + P2 Feature |

---

## 里程碑 M1: MVP 端到端可运行

### 目标

**核心目标**：端到端 KV Cache 写入/读取/Prefix 命中，单集群 4 节点可运行。

**达成标准**：
1. 推理引擎（vLLM）通过 Connector 完成 KV Cache 写入 → 读取 → Prefix 匹配的完整闭环
2. 4 节点集群部署，RDMA 数据面 + TCP 控制面
3. SPDK Blobstore 存储引擎 + DRAM 缓存 + NVMe SSD 持久化
4. 内存哈希表 + 异步 WAL + Prefix Hash Chain 索引
5. 分区 Raft（3 副本）元数据强一致
6. 3 副本异步数据复制
7. 轻量级启发式路由（本地优先 + 一致性哈希）
8. 基础命名空间隔离 + 基础 RBAC
9. 端到端集成测试通过

**MVP 边界（做什么 / 不做什么）**：

| 做 | 不做 |
|----|------|
| SPDK Blobstore 存储引擎 | 自研日志结构引擎（M2） |
| RDMA 双边操作（SPDK Reactor 原生 CQ） | 独立 RDMA 线程（M2） |
| TCP 控制平面 | TCP 数据面降级路径（M2） |
| 3 副本异步复制 | 纠删码（M2+） |
| LRU 本地淘汰 | Connector API hints（M2） |
| 基础命名空间隔离 + RBAC | 细粒度 QoS / SIEM 集成（M3） |
| vLLM Connector SDK | SGLang 适配（M2） |
| 基础 Prometheus 指标 | 完整 Dashboard / 告警模板（M2） |

### 风险评估

| # | 风险 | 可能性 | 影响 | 来源 | 缓冲策略 |
|---|------|--------|------|------|----------|
| R1 | SPDK Reactor 与 RDMA libibverbs 兼容性问题 | 中 | 高 | ADR-006 H2 | M1-I1 Spike 验证，失败则切换独立 RDMA 线程方案 |
| R2 | 分布式 Block Table 分片性能不达标 | 中 | 高 | ADR-003 H1/H2 | M1-I1 Spike 原型验证，失败则简化为单节点索引 |
| R3 | WAL 重建算法复杂度超预期（100TB 约 9.3h） | 中 | 高 | ADR-009 | M1-I2 Spike 验证增量 checkpoint 方案 |
| R4 | Raft 库集成周期超预期 | 中 | 中 | ADR-004 | 预留 2 周缓冲；备选方案：先用单节点元数据 |
| R5 | C 语言 RDMA 开发学习曲线 | 中 | 中 | ADR-001 H5 | 参考 InfiniStore 实现；4 人周原型验证 |
| R6 | 多个低置信度 ADR 假设同时被证伪 | 中 | 极高 | ADR-009(62%)/ADR-008(65%)/ADR-003(68%)/ADR-004(68%) | M1 前 4 周集中验证；2 个以上假设被证伪则触发架构方向重评估 |

**缓冲预算**：M1 总计 180-220 SP，其中 ~20 SP（约 10%）为风险缓冲，分配给 Spike 验证和意外返工。

### 迭代总览

| 迭代 | 主题 | 故事点范围 | 核心目标 |
|------|------|-----------|---------|
| M1-I1 | 基础设施 + Spike 验证 | 25-35 SP | 构建环境搭建、CI 骨架、SPDK/RDMA Spike 验证、分布式索引 Spike |
| M1-I2 | 存储引擎 + 元数据基础 | 30-40 SP | SPDK Blobstore 封装、WAL 基础实现、内存哈希表索引、Raft 库集成 |
| M1-I3 | 传输层 + 索引增强 | 60-80 SP | RDMA 双边操作、TCP 控制面、Prefix Hash Chain、WAL checkpoint（4 周，含 I2 遗留 P10 消化 + 高风险缓冲） |
| M1-I4 | 调度器 + Connector + 多租户 | 30-40 SP | 启发式路由、vLLM Connector SDK、命名空间隔离、基础 RBAC |
| M1-I5 | 端到端集成 + 数据复制 | 30-35 SP | 写入→读取→Prefix 匹配闭环、3 副本异步复制、LRU 淘汰 |
| M1-I6 | 集成测试 + 缓冲 | 25-30 SP | 端到端集成测试、4 节点集群验证、缺陷修复、风险缓冲消化 |

> **说明**：迭代边界为初始估算，实际执行中根据 Velocity 滚动调整。详细的 Wave 分组和就绪检查在第二层迭代执行计划（`iteration-m1-i*.md`）中定义。

### Proposal Backlog（M1）

> **命名规范**：`<subsystem>-<action>-<object>`
> **估算基准**：AI 辅助编码范式（传统估算 × 0.6-0.7）
> **粒度要求**：每个 proposal 1-4 周（S/M/L），XL 必须拆解

#### 基础设施（Infrastructure）

| # | Proposal 名称 | 估算 | 大小 | 依赖 | 风险 | 说明 |
|---|--------------|------|------|------|------|------|
| P01 | infra-setup-build | 5 SP | M | 无 | 低 | CMake/Meson 构建系统、SPDK/DPDK/libibverbs 依赖管理、CI 骨架（编译+单元测试） |
| P02 | infra-setup-devenv | 3 SP | M | 无 | 低 | 开发环境标准化（Docker 开发镜像、RDMA 模拟环境 rxe/siw、SPDK vhost 模拟） |
| P03 | infra-define-interface | 5 SP | M | 无 | 低 | 5 个子系统间 12 个接口的 C 头文件定义（I1-I12），含数据结构和错误码体系 |
| P04 | infra-setup-testframework | 3 SP | M | P01 | 低 | cmocka 测试框架集成、测试 runner 脚本、覆盖率收集（gcov/lcov） |

#### Spike 验证（高风险 ADR 假设验证）

| # | Proposal 名称 | 估算 | 大小 | 依赖 | 风险 | 说明 |
|---|--------------|------|------|------|------|------|
| P05 | spike-verify-spdk-rdma | 8 SP | L | P01, P02 | **高** | 验证 ADR-006 H2：SPDK Reactor 线程模型与 RDMA libibverbs CQ 轮询的兼容性；失败则切换独立 RDMA 线程方案 |
| P06 | spike-verify-distributed-index | 5 SP | M | P01 | **高** | 验证 ADR-003 H1/H2：分布式 Block Table 分片方案的查询延迟和一致性；失败则简化为单节点索引 |
| P07 | spike-verify-raft-integration | 5 SP | M | P01 | **高** | 验证 ADR-004：C 语言 Raft 库（willemt/raft 或 canonical/raft）集成复杂度和性能；失败则先用单节点元数据 |
| P08 | spike-verify-wal-checkpoint | 5 SP | M | P01 | **高** | 验证 ADR-009：WAL 增量 checkpoint 方案在 100TB 规模下的重建时间（目标 < 2h vs 当前估算 9.3h） |

#### S1 存储引擎（Storage Engine）

| # | Proposal 名称 | 估算 | 大小 | 依赖 | 风险 | 说明 |
|---|--------------|------|------|------|------|------|
| P09 | storage-impl-blobstore | 13 SP | L | P01, P05 | 中 | SPDK Blobstore 封装层：blob 创建/删除/读写、IO channel 管理、Reactor 线程集成；对应 ADR-002 Phase 1 方案 |
| P10 | storage-impl-dram-cache | 8 SP | L | P03 | 低 | DRAM 缓存层：slab 分配器、LRU 淘汰策略、缓存命中/未命中统计；对应 F1 写入存储的 L1 层 |
| P11 | storage-impl-tiering | 8 SP | L | P09, P10 | 中 | 数据分层：DRAM→SSD 异步下沉、热度统计、分层决策引擎；对应 ADR-008 Phase 1 两层方案 |
| P12 | storage-impl-replication | 8 SP | L | P09, P03(I5) | 中 | 3 副本异步复制：写入转发、副本同步、副本状态机；对应 ADR-005 Phase 1 方案 |
| P13 | storage-impl-checksum | 3 SP | M | P09 | 低 | CRC32C 数据校验：写入时计算、读取时验证、损坏检测与上报 |

#### S2 元数据服务（Metadata Service）

| # | Proposal 名称 | 估算 | 大小 | 依赖 | 风险 | 说明 |
|---|--------------|------|------|------|------|------|
| P14 | metadata-impl-hashtable | 8 SP | L | P03, P06 | 中 | 内存哈希表索引：uthash 封装、Block Table 分片、chunk_hash→位置映射；依赖 P06 Spike 结论 |
| P15 | metadata-impl-wal | 8 SP | L | P01, P08 | 中 | 异步 WAL：追加写入、批量刷盘、崩溃恢复重放、增量 checkpoint；依赖 P08 Spike 结论 |
| P16 | metadata-impl-prefix-index | 8 SP | L | P14 | 中 | Prefix Hash Chain 索引：token 序列前缀匹配、索引构建/查询/失效传播；对应 F3 Prefix Cache 匹配 |
| P17a | metadata-impl-raft-core | 8 SP | L | P07, P03(I4) | **高** | Raft 核心集成：C 语言 Raft 库绑定、日志存储适配、Leader 选举、日志复制；依赖 P07 Spike 结论，关键路径 |
| P17b | metadata-impl-raft-snapshot | 5 SP | M | P17a | 中 | Raft 快照与恢复：快照触发策略、快照传输、崩溃恢复重放、日志截断；拆分自 P17 以降低单 proposal 风险 |
| P18 | metadata-impl-partition | 5 SP | M | P14, P17a | 中 | 元数据分区管理：分区分配、分区迁移、分区路由表维护 |

#### S3 传输层（Transport Layer）

| # | Proposal 名称 | 估算 | 大小 | 依赖 | 风险 | 说明 |
|---|--------------|------|------|------|------|------|
| P19 | transport-impl-rdma | 13 SP | L | P05, P03(I3) | **高** | RDMA 双边操作数据面：连接管理、Send/Recv 封装、CQ 轮询、零拷贝传输；依赖 P05 Spike 结论，关键路径 |
| P20 | transport-impl-tcp | 5 SP | M | P03(I3) | 低 | TCP 控制面：连接池、心跳、消息序列化/反序列化；MVP 阶段仅用于控制面 |
| P21 | transport-impl-protocol | 5 SP | M | P19, P20 | 低 | 传输协议封装：统一的消息头格式、请求/响应匹配、超时重试机制 |

#### S4 调度器（Scheduler）

| # | Proposal 名称 | 估算 | 大小 | 依赖 | 风险 | 说明 |
|---|--------------|------|------|------|------|------|
| P22 | scheduler-impl-routing | 8 SP | L | P03(I6,I7), P14 | 中 | 轻量级启发式路由：本地优先策略、一致性哈希分配、路由表维护；对应 ADR-001 Phase 1 方案 |
| P23 | scheduler-impl-placement | 5 SP | M | P22, P17 | 中 | 副本放置策略：机架感知、负载均衡、放置约束检查 |

#### S5 连接器（Connector）

| # | Proposal 名称 | 估算 | 大小 | 依赖 | 风险 | 说明 |
|---|--------------|------|------|------|------|------|
| P24 | connector-impl-sdk | 8 SP | L | P03(I1,I2), P21 | 中 | vLLM Connector SDK：C 语言客户端库、异步写入/读取 API、连接管理、错误处理；对应 F8 推理引擎连接器 |
| P25 | connector-impl-prefix-api | 5 SP | M | P24, P16 | 中 | Prefix Cache 查询 API：prefix_cache_lookup 接口、批量预取调度、缓存未命中回退处理 |

#### 多租户基础（Cross-cutting）

| # | Proposal 名称 | 估算 | 大小 | 依赖 | 风险 | 说明 |
|---|--------------|------|------|------|------|------|
| P26 | security-impl-namespace | 5 SP | M | P14, P03 | 低 | 基础命名空间隔离：租户→命名空间映射、元数据隔离、存储配额基础框架；对应 F7 多租户隔离 MVP |
| P27 | security-impl-rbac | 5 SP | M | P26 | 低 | 基础 RBAC：角色定义（admin/operator/viewer）、权限检查中间件、Token 认证框架 |
| P28 | observability-impl-metrics | 3 SP | M | P01 | 低 | 基础 Prometheus 指标：/metrics 端点、写入/读取 ops/latency、各层容量、缓存命中率 |
| P35 | storage-impl-avalanche-guard | 3 SP | M | P10, P11 | 低 | 缓存雪崩防护：TTL 随机化（±20% 抖动）、速率限制器（令牌桶）、热点 key 检测与自动多副本提升；对应 cache-offloading S8 场景 |

#### 集成测试（独立立项）

| # | Proposal 名称 | 估算 | 大小 | 依赖 | 风险 | 说明 |
|---|--------------|------|------|------|------|------|
| P29 | inttest-verify-storage-metadata | 8 SP | L | P09, P14, P15 | 中 | 存储引擎×元数据集成：写入→索引→读取闭环、WAL 崩溃恢复后数据一致性、分层下沉触发索引更新 |
| P30 | inttest-verify-transport-e2e | 8 SP | L | P19, P20, P21 | 中 | 传输层端到端：RDMA 数据面写入/读取、TCP 控制面心跳/路由同步、跨节点数据传输正确性 |
| P31 | inttest-verify-replication | 8 SP | L | P12, P17, P19 | **高** | 3 副本复制集成：写入→副本同步→读取一致性、单节点故障→副本重建、Raft 元数据与数据副本状态一致 |
| P32 | inttest-verify-prefix-e2e | 5 SP | M | P16, P24, P25 | 中 | Prefix 匹配端到端：写入 KV Cache→构建 Prefix 索引→查询命中→加载数据→验证正确性 |
| P33 | inttest-verify-cluster-4node | 8 SP | L | P22, P23, P26, P27 | 中 | 4 节点集群验证：集群组建→路由分配→多租户隔离→读写负载→节点故障→恢复，对应 M1 达成标准 |
| P34 | inttest-verify-connector-vllm | 5 SP | M | P24, P25, P33 | 中 | vLLM Connector 集成：模拟 vLLM 调用 Connector SDK 完成写入→读取→Prefix 匹配完整闭环 |

### Backlog 统计

| 类别 | Proposal 数量 | 故事点合计 | 占比 |
|------|-------------|-----------|------|
| 基础设施 | 4 | 16 SP | 7% |
| Spike 验证 | 4 | 23 SP | 10% |
| S1 存储引擎 | 6 | 43 SP | 19% |
| S2 元数据服务 | 6 | 47 SP | 20% |
| S3 传输层 | 3 | 23 SP | 10% |
| S4 调度器 | 2 | 13 SP | 6% |
| S5 连接器 | 2 | 13 SP | 6% |
| 多租户/可观测 | 3 | 13 SP | 6% |
| **集成测试** | **6** | **42 SP** | **18%** |
| **合计** | **36** | **233 SP** | **100%** |

> **集成测试占比 18%（6/36 proposal，42/233 SP），满足 ≥15% 要求。**
>
> **总估算 233 SP 略超 180-220 SP 上限**，这是因为包含了风险缓冲、Spike 验证和评审修正新增 proposal。实际执行中，Spike 验证如果顺利（假设被确认），对应的实现 proposal 估算可下调 10-15%。如果 Spike 失败触发备选方案，则需要在滚动更新中重新评估。

### 关键路径分析

```
关键路径 1（SPDK-RDMA 数据面）：
P01 → P05(Spike) → P09(Blobstore) → P12(Replication) → P31(集成测试) → P33(4节点验证)
                  → P19(RDMA)      → P21(Protocol)    → P30(传输集成)  ↗

关键路径 2（元数据一致性）：
P01 → P07(Spike) → P17a(Raft核心) → P17b(Raft快照) → P18(Partition) → P22(Routing) → P33(4节点验证)
P01 → P06(Spike) → P14(HashTable) → P16(Prefix) → P25(Prefix API) → P32(Prefix集成) → P34(vLLM集成)

关键路径 3（端到端闭环）：
P24(SDK) → P25(Prefix API) → P34(vLLM集成)
```

**关键路径上的高风险 Proposal**：P05、P06、P07、P08、P17a、P19（共 6 个，占 Backlog 的 17%）

**关键路径总长度**：约 10-12 周（不含缓冲），12 周含缓冲，与 M1 周期匹配。

### 接口冻结点

| 冻结时间点 | 接口 | 涉及 Proposal | 说明 |
|-----------|------|--------------|------|
| M1-I1 结束 | I1-I12 头文件定义 | P03 | 所有子系统间接口的 C 头文件在 M1-I1 冻结，后续仅允许向后兼容的扩展 |
| M1-I2 结束 | I3 传输层接口实现 | P19, P20, P21 | 传输层 API 冻结，上层（调度器、连接器）可开始集成 |
| M1-I3 结束 | I1/I2 Connector 接口实现 | P24 | Connector SDK API 冻结，vLLM 集成测试可开始 |
| M1-I4 结束 | I4 元数据接口实现 | P17, P18 | 元数据服务 API 冻结，集成测试可开始 |

### MVP 前置条件

| 条件 | 验证方式 | 负责 Proposal | 截止时间 |
|------|---------|--------------|---------|
| SPDK Reactor + RDMA CQ 兼容 | Spike 原型 | P05 | M1-I1 |
| 分布式索引分片可行 | Spike 原型 | P06 | M1-I1 |
| Raft 库集成可行 | Spike 原型 | P07 | M1-I1 |
| WAL checkpoint 性能达标 | Spike 原型 | P08 | M1-I1 |
| 子系统架构文档完成 | 文档评审 | 架构师 | M1-I1 |

> **决策门**：M1-I1 结束时，如果 2 个以上 Spike 失败，触发架构方向重评估（参见风险 R6）。

---

## 里程碑 M2: 性能增强与生产就绪（粗略）

### 目标

**核心目标**：性能优化达到生产级指标 + PD 分离传输 + TCP 降级路径 + 基础可观测性体系。

**达成标准**：
1. 单节点写入吞吐 ≥ 500K ops/s（64KB chunk），读取 P99 ≤ 500 μs（跨节点 RDMA）
2. PD 分离传输吞吐 ≥ 10 GB/s/节点
3. RDMA 故障自动降级 TCP，切换时间 ≤ 50ms
4. 数据压缩（LZ4）降低 SSD 写入放大
5. SGLang Connector 适配
6. Grafana Dashboard + 告警模板
7. Connector API hints（预取提示）

**对应 Feature**：
- P1: PD 分离传输（F4）、热点数据多副本（F5）
- P1: 数据压缩、可观测性 Dashboard、SGLang 适配
- P0 增强：写入/读取性能优化到生产级指标

**预估规模**：150-180 SP，6 个迭代（12 周）

**主要风险**：
- RDMA→TCP 降级路径的延迟抖动控制
- PD 传输拥塞控制算法调优
- 性能优化可能需要多轮迭代

> **近详远略**：M2 的详细 Backlog 和 Wave 分组将在 M1-I5 结束时基于实际 Velocity 制定。

---

## 里程碑 M3: 企业级能力（粗略）

### 目标

**核心目标**：多租户完善 + QoS + 审计日志 + S3 兼容 API + 传输加密。

**达成标准**：
1. 细粒度 QoS（租户级 IOPS/带宽限制）
2. 完整审计日志（SIEM 集成）
3. S3 兼容 API 网关
4. TLS 1.3 传输加密 + 租户级数据加密（AES-256-GCM）
5. 在线扩缩容（零停机）
6. 50+ 节点集群验证

**对应 Feature**：
- P1: QoS 资源隔离、审计日志与合规、S3 兼容 API、传输加密
- P1: 在线扩缩容增强

**预估规模**：120-150 SP，6 个迭代（12 周）

**主要风险**：
- QoS 限流精度与性能开销的平衡
- S3 API 兼容性测试矩阵庞大
- 加密对热路径性能的影响

> **近详远略**：M3 的详细 Backlog 将在 M2-I4 结束时制定。

---

## 里程碑 M4: 大规模验证与成熟（粗略）

### 目标

**核心目标**：100+ 节点大规模验证 + 跨版本升级 + 高级特性。

**达成标准**：
1. 100+ 节点集群稳定运行 7×24h
2. 跨版本滚动升级（零停机）
3. 快照与克隆（Copy-on-Write）
4. 跨区域复制评估（技术可行性验证）
5. 全量性能基准测试报告

**对应 Feature**：
- P1: 跨版本升级
- P2: 快照与克隆
- 评估: 跨区域复制

**预估规模**：80-100 SP，4 个迭代（8 周）

**主要风险**：
- 100+ 节点下的元数据分区扩展性
- 滚动升级的状态兼容性验证
- 跨区域复制的网络延迟和一致性挑战

> **近详远略**：M4 的详细 Backlog 将在 M3-I4 结束时制定。

---

## 三重评审记录

### 产品经理视角

**结论**：通过（CRITICAL 已修正）

- P0 Feature 全部在 M1 覆盖，P1 Feature 合理分布在 M2/M3，优先级排序与产品价值一致
- CRITICAL：~~M1 Backlog 中缺少"缓存雪崩防护"（S8 场景）的独立 proposal~~ → ✅ 已修正：新增 P35 `storage-impl-avalanche-guard`（3 SP）
- M2 的 SGLang 适配优先级需根据市场反馈动态调整

### 架构师视角

**结论**：通过（CRITICAL 已修正）

- 5 个子系统的 Proposal 分解与架构边界一致，接口冻结点设置合理
- CRITICAL：~~P17（Raft 集成）估算 13 SP 可能偏乐观~~ → ✅ 已修正：P17 拆分为 P17a（Raft 核心集成 8 SP）+ P17b（Raft 快照/恢复 5 SP），总计 13 SP 不变但风险分散
- P05（SPDK-RDMA Spike）和 P19（RDMA 实现）之间的依赖是关键路径瓶颈，建议 P19 在 P05 验证通过后立即启动，不等待 I1 结束

### 项目经理视角

**结论**：通过（CRITICAL 已修正）

- 关键路径长度 10-12 周 + 缓冲 = 12 周，与 M1 周期匹配，余量紧张但可控
- CRITICAL：~~高风险 Proposal 集中在关键路径上（P05→P19、P07→P17），任一失败将直接影响 M1 交付~~ → ✅ 已缓解：P17 拆分降低单点风险；决策门机制（M1-I1 结束时评估 Spike 结果）提供早期预警
- 集成测试 6 个 proposal（18%）满足 ≥15% 要求，P31 和 P33 依赖链最长，建议在 M1-I4 就开始准备测试环境
- 建议：M1-I1 结束后立即进行第一次 Velocity 校准，如果实际 Velocity < 20 SP/迭代，需要在 M1-I2 就启动范围裁剪讨论

---

## 变更记录

| 日期 | 版本 | 变更内容 |
|------|------|----------|
| 2026-04-22 | v0.1 | 初始版本：4 个里程碑划分 + M1 详细 Backlog（34 个 Proposal）+ 关键路径分析 + 三重评审 |
| 2026-04-22 | v0.2 | 三重评审 CRITICAL 修正：P17 拆分为 P17a/P17b、新增 P35 缓存雪崩防护、统计更新（36 Proposal / 233 SP）|
| 2026-04-22 | v0.3 | M1-I3 评审 CRITICAL 联动更新：M1-I3 迭代周期从 2 周/30-40 SP 变更为 4 周/60-80 SP（I2 遗留 P10 消化 + 高风险缓冲）；P17b 从高风险降为中风险；关键路径高风险 Proposal 从 7 个调整为 6 个（17%）|

---

## 自检清单

- [x] 里程碑数量 3-5 个，每个有明确达成标准
- [x] M1 Backlog 粒度 1-4 周（S/M/L），无 XL
- [x] Proposal 命名遵循 `<subsystem>-<action>-<object>`
- [x] 集成测试独立立项，占比 ≥ 15%（实际 18%）
- [x] 关键路径已识别，高风险任务占比 ≤ 40%（实际 17%）
- [x] 近详远略：M1 详细 Backlog，M2/M3/M4 粗略描述
- [x] 依赖关系标注完整（每个 Proposal 的依赖列）
- [x] 接口冻结点已定义
- [x] 三重评审通过（3 个 CRITICAL 已修正）
- [x] 文档追溯关系已建立（8 个输入文档）
