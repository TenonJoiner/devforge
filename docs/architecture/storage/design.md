# S1 存储引擎架构设计

> **文档状态**：✅ 终稿（Phase C 修正定稿，经 architect-reviewer 质疑修正）
> **关联 ADR**：ADR-002（存储引擎）、ADR-005（冗余策略）、ADR-008（分层策略）
> **关联接口**：I1, I2, I4, I7, I8, I9, I12
> **Reviewer 质疑**：3 P0 + 4 P1 + 3 P2，全部已回应修正

---

## 设计目标

S1 存储引擎是系统的数据平面核心，负责**单节点上 KV Cache 数据的完整生命周期管理**：从 RDMA 接收数据、写入 NVMe SSD、管理 DRAM↔SSD 分层、执行 LRU 淘汰、到异步副本复制。

**在系统中的定位**：
- S1 是唯一直接操作 NVMe SSD 和 DRAM 数据缓存的子系统
- S1 不负责全局数据分布决策（由 S4 调度器负责）和全局索引管理（由 S2 元数据服务负责）
- S1 内部合并了三个模块：存储模块（NVMe I/O）、分层模块（DRAM↔SSD 迁移）、冗余模块（副本复制）

**边界约束**：
- 数据写入：S1 作为 RDMA 服务端主导数据拉取（ADR-007），不由客户端推送
- 元数据确认：S1 写入 NVMe 后调用 S2 进行 Raft majority 确认（I4），S1 不参与 Raft 协议
- 副本传输：S1 发起异步副本复制请求（I9），由 S3 传输层执行 RDMA 传输
- 分层决策：Phase 1 完全本地自治（LRU），Phase 2 接受 Connector API hints

**核心挑战**：
1. 在 SPDK 用户态 I/O 框架下实现高吞吐（≥ 10 GB/s 写入）低延迟（P50 < 1ms）的 KV Cache 存储
2. 管理 DRAM 缓存层，在有限内存（~1TB/节点）下最大化命中率
3. 协调写入路径中的多个异步操作（RDMA 拉取 → NVMe 写入 → 元数据确认 → 副本复制）
4. Phase 1 使用 Blobstore 保底，同时为 Phase 2 日志结构引擎预留替换接口

---

## 核心概念

| 概念 | 定义 | 与周边系统的关系 |
|------|------|-----------------|
| **KVBlock** | KV Cache 数据的基本存储单元，包含 header（key、校验和、版本、层级标记）+ payload（32MB~100MB 的 KV 张量数据）。WORM 语义：写入后不可修改，只能整体淘汰或删除 | S5 连接器通过 I1 写入 KVBlock；S2 元数据服务记录 KVBlock 的全局位置（Block Table） |
| **TierSlot** | DRAM 缓存层的分配单元。预分配的固定大小内存区域（对齐到 2MB hugepage），用于缓存热数据。每个 TierSlot 关联一个 KVBlock 的引用 | S1 内部概念，不暴露给其他子系统。LRU 淘汰以 TierSlot 为粒度 |
| **WriteContext** | 一次写入操作的完整上下文，封装了从 RDMA 拉取到 NVMe 写入到元数据确认的全部状态。状态机驱动，每个阶段完成后回调推进下一阶段 | 生命周期跨越 S3（RDMA 传输）、S1（NVMe 写入）、S2（元数据确认） |
| **ReplicaTask** | 异步副本复制任务，包含目标节点列表、重试计数、超时信息。写入主路径完成后入队，后台线程消费 | S1 创建 ReplicaTask，通过 I9 委托 S3 传输层执行 RDMA 传输 |
| **StorageBackend** | 存储引擎的抽象接口层，定义 alloc/write/read/free 四个核心操作 + get_stats/maintenance 两个扩展点。Phase 1 实现为 SPDK Blobstore 后端，Phase 2 替换为日志结构后端，上层代码无需修改。get_stats 返回后端特定统计（如碎片率），maintenance 触发后端特定维护操作（如 GC）；Phase 1 BlobstoreBackend 的 maintenance 为空操作（回应 Reviewer P1-3） | S1 内部抽象，隔离存储引擎实现细节，保障 Phase 1→2 平滑演进 |

---

## 方案对比

> ADR-002 已决策存储引擎选型（Phase 1 Blobstore / Phase 2 日志结构），本节聚焦 S1 **内部架构组织方式**：写入路径设计、DRAM 缓存管理、冗余模块集成方式。

### 方案 A：直写式架构（Write-Through + 独立 DRAM Cache）

**核心思路**：写入路径直接落盘 NVMe（通过 StorageBackend），DRAM 缓存作为独立的读缓存层管理。写入完成后，热数据异步提升到 DRAM 缓存。冗余模块作为 S1 内部独立组件，在 NVMe 写入确认后触发异步副本复制。

**参考来源**：InfiniStore 内存池管理 + SPDK Blobstore 原生写入模型 `☑ 标杆产品`

**架构草图**：
```
┌─────────────────────────────────────────────────────┐
│                    S1 存储引擎                        │
│                                                     │
│  ┌─────────────┐    ┌─────────────┐                 │
│  │ WriteContext │───>│ StorageBackend                │
│  │ 状态机       │    │ (Blobstore)  │──> NVMe SSD    │
│  └──────┬──────┘    └─────────────┘                 │
│         │                                           │
│         │ 写入完成后                                  │
│         ├──> ┌─────────────┐                        │
│         │    │ DRAM Cache   │  独立 LRU 管理          │
│         │    │ (TierSlot池) │  读命中直接返回          │
│         │    └─────────────┘                        │
│         │                                           │
│         └──> ┌─────────────┐                        │
│              │ ReplicaManager│  异步副本复制           │
│              │ (独立队列)    │──> I9 → S3             │
│              └─────────────┘                        │
└─────────────────────────────────────────────────────┘
```

**优点**：
1. **写入路径简单可靠**：数据直接落盘，持久化语义清晰，不存在 DRAM 缓冲丢失风险
2. **DRAM 缓存独立管理**：缓存层与存储层解耦，LRU 策略可独立调优，不影响写入路径
3. **与 Blobstore 天然契合**：Blobstore 本身是直写模型，无需额外适配
4. **故障恢复简单**：崩溃后只需从 NVMe 恢复，DRAM 缓存可丢弃重建

**缺点**：
1. **写入延迟受 NVMe 限制**：每次写入必须等 NVMe 完成（~100μs），无法通过 DRAM 缓冲降低 P50
2. **读缓存冷启动**：重启后 DRAM 缓存为空，需要时间预热，期间读延迟较高
3. **DRAM 利用率不最优**：写入路径不经过 DRAM，热数据需要额外的"提升"操作才能进入缓存

**适用场景**：写入吞吐优先、持久化语义要求严格、可接受 NVMe 写入延迟作为 P50 基线的场景。

---

### 方案 B：写缓冲式架构（Write-Buffer + 统一 DRAM 层）

**核心思路**：写入路径先写入 DRAM 缓冲区（TierSlot），立即返回成功，后台异步刷盘到 NVMe。DRAM 同时承担写缓冲和读缓存双重角色，统一管理。冗余模块在 DRAM 写入完成后即触发副本复制（不等 NVMe 刷盘）。

**参考来源**：LMCache Write-All 策略 + MoonCake DRAM 为主存储模型 `☑ 标杆产品`

**架构草图**：
```
┌─────────────────────────────────────────────────────┐
│                    S1 存储引擎                        │
│                                                     │
│  ┌─────────────┐    ┌──────────────────────┐        │
│  │ WriteContext │───>│ 统一 DRAM 层          │        │
│  │ 状态机       │    │ (写缓冲 + 读缓存)     │        │
│  └──────┬──────┘    │ TierSlot 池           │        │
│         │           └──────────┬───────────┘        │
│         │                      │                    │
│         │ DRAM 写入完成后       │ 后台异步刷盘         │
│         ├──> 元数据确认(I4)     │                    │
│         │                      ▼                    │
│         │              ┌─────────────┐              │
│         │              │ StorageBackend              │
│         │              │ (Blobstore)  │──> NVMe SSD  │
│         │              └─────────────┘              │
│         │                                           │
│         └──> ┌─────────────┐                        │
│              │ ReplicaManager│  DRAM 写入后即触发     │
│              │ (独立队列)    │──> I9 → S3             │
│              └─────────────┘                        │
└─────────────────────────────────────────────────────┘
```

**优点**：
1. **写入延迟极低**：DRAM 写入 ~1μs，P50 可降至 < 100μs（不含元数据确认）
2. **DRAM 利用率最优**：写入数据天然在 DRAM 中，无需额外提升操作，新写入数据立即可被高速读取
3. **副本复制更快**：从 DRAM 发起 RDMA 传输比从 NVMe 读取再传输更快
4. **与 MoonCake 模型一致**：MoonCake 验证了 DRAM 为主存储的可行性

**缺点**：
1. **持久化语义复杂**：DRAM 写入成功 ≠ 持久化成功，崩溃时 DRAM 中未刷盘数据丢失
2. **与 ADR-004 分层一致性冲突**：ADR-004 要求"本地 NVMe 写入即确认"，写缓冲模式下确认时机提前到 DRAM，改变了持久化语义
3. **DRAM 容量压力**：写缓冲占用 DRAM 空间，与读缓存竞争，高写入负载下可能挤压读缓存命中率
4. **刷盘失败处理复杂**：后台刷盘失败时，已确认的写入需要回滚或重试，错误处理路径复杂

**适用场景**：写入延迟极致优化、DRAM 容量充足、可接受更复杂持久化语义的场景。

---

### 被排除方案

#### 方案 C：分层对象模型（Session→Sequence→Block 层次结构）

**核心思路**：将 KVBlock 组织为三层对象模型——Session（推理会话）包含多个 Sequence（token 序列），每个 Sequence 包含多个 Block（固定大小数据块）。存储引擎感知这三层语义，按 Session 粒度管理生命周期，按 Sequence 粒度管理 Prefix 复用。

**参考来源**：vLLM PagedAttention Block Manager `☑ 开源项目`

**排除理由**：
1. **违反职责边界**：Session/Sequence 是推理引擎的概念，S1 存储引擎不应感知推理语义。Prefix 复用由 S2 元数据服务的 Prefix Hash Chain 索引管理（ADR-003），S1 只需提供扁平的 KVBlock 存取接口
2. **与 ADR-001 PD 语义架构预留冲突**：ADR-001 要求 Phase 1 接口参数包含 op_type 区分 prefill_write/decode_read，但不要求存储引擎理解 Session/Sequence 语义。分层对象模型过度耦合推理语义，限制了存储引擎的通用性
3. **工程复杂度过高**：三层对象模型需要维护 Session→Sequence→Block 的引用关系、级联删除、跨层 GC，估计增加 3000-5000 行代码，且与 Blobstore 的扁平 blob 模型不兼容
4. **空间开销**：每个 Session/Sequence 对象需要额外元数据（~200 bytes/对象），百万级 Session 下额外占用 ~200MB 内存，挤压 DRAM 缓存空间

---

### 决策 rationale

选择 **方案 A（直写式架构）**，原因如下：

1. **时间复杂度**：
   - 方案 A：写入路径 O(1)（Blobstore alloc + NVMe write），读取路径 O(1)（DRAM cache lookup + fallback NVMe read）
   - 方案 B：写入路径 O(1)（DRAM write），但刷盘路径引入 O(N) 批量写入调度，且刷盘失败需 O(K) 重试
   - 在目标写入吞吐 ≥ 10 GB/s 下，方案 A 的 NVMe 直写延迟（~100μs/32MB）远低于 P50 < 1ms 目标，写缓冲的延迟优势不构成决定性差异

2. **空间效率**：
   - 方案 A：DRAM 100% 用于读缓存，1TB DRAM 可缓存 ~30,000 个 32MB KVBlock
   - 方案 B：DRAM 需分配写缓冲区（高写入负载下可能占用 10-30%），读缓存有效容量降至 700MB-900MB
   - 在单节点 1TB DRAM 规模下，方案 A 的读缓存容量优势约 10-30%，直接影响 DRAM 命中率（ADR-008 H1 假设 80% 热数据覆盖）

3. **一致性/正确性**：
   - 方案 A：NVMe 写入完成即持久化，与 ADR-004 "本地 NVMe 写入即确认"完全一致，崩溃恢复只需从 NVMe 读取
   - 方案 B：DRAM 写入确认但未持久化，崩溃时丢失未刷盘数据，**与 ADR-004 数据层持久化语义冲突**。虽然 KV Cache 可重算，但丢失数据意味着命中率下降和重计算开销
   - 方案 A 在 crash-stop 故障场景下行为确定，方案 B 需要额外的 WAL 或 journal 保证持久化，增加复杂度

4. **工程复杂度**：
   - 方案 A：~2000-3000 行核心代码（StorageBackend 抽象 + DRAM Cache + ReplicaManager），与 Blobstore 直写模型天然契合
   - 方案 B：~4000-5000 行核心代码（统一 DRAM 层 + 后台刷盘调度 + 刷盘失败处理 + 写缓冲/读缓存空间竞争管理）
   - 团队首次接触 SPDK，方案 A 降低学习曲线和交付风险

**关键 trade-off**：
- 我们放弃了方案 B 的极致写入延迟（DRAM 写入 ~1μs vs NVMe 写入 ~100μs），换取方案 A 的持久化语义简洁性和与 ADR-004 的一致性
- 这个取舍在我们的场景是可接受的，因为：① 32MB KVBlock 的 NVMe 写入延迟（~100μs）远低于 P50 < 1ms 目标；② 写入路径的主要延迟瓶颈是 Raft majority 确认（~100μs-3ms），而非 NVMe 写入；③ DRAM 100% 用于读缓存可最大化命中率，对读密集的 KV Cache 场景收益更大

---

## 架构设计

### 高层架构

```
┌─────────────────────────────────────────────────────────────────────┐
│                         S1 存储引擎（单节点）                         │
│                                                                     │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │                     请求处理层（SPDK Reactor 线程）              │  │
│  │                                                               │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐           │  │
│  │  │ I1 kv_put   │  │ I2 kv_get   │  │ I12 replica  │           │  │
│  │  │ Handler     │  │ Handler     │  │ _receive     │           │  │
│  │  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘           │  │
│  │         │                │                │                   │  │
│  │         ▼                ▼                ▼                   │  │
│  │  ┌─────────────────────────────────────────────────────────┐  │  │
│  │  │              WriteContext / ReadContext 状态机             │  │  │
│  │  └─────────────────────────┬───────────────────────────────┘  │  │
│  └────────────────────────────┼──────────────────────────────────┘  │
│                               │                                     │
│  ┌────────────────────────────┼──────────────────────────────────┐  │
│  │                     存储模块                                   │  │
│  │                            │                                   │  │
│  │  ┌─────────────────────────▼───────────────────────────────┐  │  │
│  │  │              StorageBackend 抽象接口                      │  │  │
│  │  │  ┌──────────────────┐  ┌──────────────────┐             │  │  │
│  │  │  │ Phase 1:         │  │ Phase 2:         │             │  │  │
│  │  │  │ BlobstoreBackend │  │ LogStructBackend │             │  │  │
│  │  │  └────────┬─────────┘  └────────┬─────────┘             │  │  │
│  │  └───────────┼─────────────────────┼───────────────────────┘  │  │
│  │              │                     │                           │  │
│  │              ▼                     ▼                           │  │
│  │        ┌──────────┐         ┌──────────┐                      │  │
│  │        │ NVMe SSD │         │ NVMe SSD │                      │  │
│  │        │ (SPDK)   │         │ (SPDK)   │                      │  │
│  │        └──────────┘         └──────────┘                      │  │
│  └────────────────────────────────────────────────────────────────┘  │
│                                                                     │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │                     分层模块                                    │  │
│  │  ┌──────────────────────────────────────────────────────────┐  │  │
│  │  │              DRAM Cache（TierSlot 池）                    │  │  │
│  │  │  ┌──────────┐  ┌──────────┐  ┌──────────┐               │  │  │
│  │  │  │ TierSlot │  │ TierSlot │  │ TierSlot │  ...          │  │  │
│  │  │  │ (2MB对齐) │  │ (2MB对齐) │  │ (2MB对齐) │               │  │  │
│  │  │  └──────────┘  └──────────┘  └──────────┘               │  │  │
│  │  │                                                          │  │  │
│  │  │  LRU 链表 + 哈希索引（O(1) 查找 + O(1) 淘汰）             │  │  │
│  │  │  pin 标记（不参与 LRU 淘汰）                               │  │  │
│  │  └──────────────────────────────────────────────────────────┘  │  │
│  └────────────────────────────────────────────────────────────────┘  │
│                                                                     │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │                     冗余模块                                    │  │
│  │  ┌──────────────────────────────────────────────────────────┐  │  │
│  │  │              ReplicaManager                               │  │  │
│  │  │  ┌──────────────┐  ┌──────────────┐                      │  │  │
│  │  │  │ ReplicaTask  │  │ ReplicaTask  │  ...                 │  │  │
│  │  │  │ 队列(rte_ring)│  │ 队列(rte_ring)│                      │  │  │
│  │  │  └──────────────┘  └──────────────┘                      │  │  │
│  │  │  异步消费 → I9 → S3 传输层                                 │  │  │
│  │  └──────────────────────────────────────────────────────────┘  │  │
│  └────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
```

### 核心流程

#### 写入流程（I1 kv_put）

1. S5 连接器通过 I1 发送 kv_put RPC（控制面），携带 key、hints、RDMA MR 信息
2. S1 请求处理层创建 WriteContext，进入状态机 `INIT` 状态
3. S1 通过 StorageBackend 分配 NVMe 空间（Blobstore blob alloc）
4. S1 作为 RDMA 服务端，通过 I7 从连接器拉取 KVBlock 数据到预分配的 DMA 缓冲区
5. RDMA 完成回调：校验 CRC32C → 通过 StorageBackend 写入 NVMe SSD
6. NVMe 写入完成回调：通过 I4 请求 S2 元数据服务更新 Block Table（Raft majority）
7. Raft 确认回调：通过 I1 回调通知 S5 写入成功
8. 后台：创建 ReplicaTask 入队，冗余模块异步通过 I9 传输到 2 个副本节点
9. 后台：分层模块判断是否将数据提升到 DRAM 缓存（基于访问频率预测）

#### 读取流程（I2 kv_get）

1. S5 连接器通过 I2 发送 kv_get 请求
2. S1 先查 DRAM Cache（哈希索引 O(1)）
   - 命中：直接通过 I7 RDMA 传输返回数据，更新 LRU 位置
   - 未命中：通过 StorageBackend 从 NVMe SSD 读取，RDMA 传输返回，同时异步提升到 DRAM Cache
3. 读取完成后通过 I2 回调返回数据

#### 副本接收流程（I12 replica_receive）

1. S3 传输层通过 I12 将远端副本数据推送到 S1
2. S1 通过 StorageBackend 写入本地 NVMe SSD
3. 更新本地 WAL（仅记录本地存在该 KVBlock 副本的事实，不走 Raft）
4. 返回 ACK/NACK 给源节点

> 回应 Reviewer P1-1：副本位置信息同步机制——副本节点接收成功后，由**源节点**（ReplicaTask REPLICATED 状态）通过 I4 批量通知 S2 更新 Block Table，增加副本位置信息（{key, replica_node_id, AVAILABLE}）。选择源节点上报而非副本节点自行上报，原因：① 源节点已持有 ReplicaTask 上下文，知道所有副本目标节点的 ACK 状态；② 避免副本节点直接调用 I4 引入额外的 Raft 写入（源节点可批量合并多个副本位置更新为一次 I4 调用）。

---

## 数据模型

### 核心数据结构

| 实体 | 用途 | 关键字段 | 持久化方式 |
|------|------|----------|-----------|
| KVBlock | KV Cache 数据存储单元 | `key: hash128_t, payload_size: uint32_t, crc32c: uint32_t, version: uint64_t, tier: tier_e, flags: uint16_t` | NVMe SSD（通过 StorageBackend） |
| KVBlockHeader | KVBlock 的持久化头部 | `magic: uint32_t, key: hash128_t, payload_size: uint32_t, crc32c: uint32_t, version: uint64_t, create_ts: uint64_t, refcount: uint32_t` | NVMe SSD（KVBlock 前 64 字节） |
| TierSlot | DRAM 缓存分配单元 | `slot_id: uint32_t, kvblock_key: hash128_t, dma_buf: void*, size: size_t, lru_prev/next: tier_slot_t*, pinned: bool, access_count: uint32_t` | 内存（崩溃后丢弃重建） |
| WriteContext | 写入操作状态机 | `state: write_state_e, key: hash128_t, rdma_mr: rdma_mr_t, blob_id: uint64_t, retry_count: uint8_t, start_ts: uint64_t, callback: write_cb_t` | 内存（操作完成后释放） |
| ReplicaTask | 异步副本复制任务 | `key: hash128_t, targets[2]: node_id_t, retry_count: uint8_t, created_ts: uint64_t, status: replica_status_e` | 内存（rte_ring 队列） |

### 状态机

#### WriteContext 状态机

```
[INIT] ──alloc_ok──> [SPACE_ALLOCATED] ──rdma_done──> [DATA_RECEIVED]
                                                           │
                                                     crc_ok │ crc_fail
                                                           │      │
                                                           ▼      ▼
                                                    [WRITING_NVME] [ERROR]
                                                           │
                                                     nvme_done
                                                           │
                                                           ▼
                                                    [META_CONFIRMING]
                                                           │
                                                  raft_ok  │  raft_fail(retry<3)
                                                           │      │
                                                           ▼      ▼
                                                    [COMMITTED]  [META_CONFIRMING]
                                                           │         (retry)
                                                     callback      raft_fail(retry>=3)
                                                           │              │
                                                           ▼              ▼
                                                      [DONE]         [ERROR]
```

| 状态 | 进入条件 | 退出条件 | 停留期间的行为约束 |
|------|----------|----------|------------------|
| INIT | I1 请求到达 | StorageBackend 空间分配完成（异步回调） | 仅允许 StorageBackend alloc 异步操作（回应 Reviewer P0-2a：Blobstore blob alloc 本身是异步 I/O，INIT 状态允许此操作） |
| SPACE_ALLOCATED | 空间分配成功 | RDMA 数据拉取完成 | DMA 缓冲区已从预分配池获取；blob 已分配但未写入 |
| DATA_RECEIVED | RDMA 完成回调 | CRC 校验完成 | 数据在 DMA 缓冲区中 |
| WRITING_NVME | CRC 校验通过 | NVMe 写入完成回调 | SPDK 异步 I/O 进行中 |
| META_CONFIRMING | NVMe 写入完成 | Raft majority 确认或重试耗尽 | 等待 S2 响应，最多重试 3 次；DMA 缓冲区在进入此状态时释放回池（回应 Reviewer 风险补充：数据已写入 NVMe，不再需要 DMA buf，避免长时间占用） |
| COMMITTED | Raft 确认成功 | 回调 S5 完成 | 触发 ReplicaTask 入队 |
| DONE | 回调完成 | — | WriteContext 释放回池 |
| ERROR | 任何阶段失败 | 回调 S5 错误码 | 异步资源释放链：DMA buf 归还池（同步）→ blob 异步删除（`spdk_bs_delete_blob` 回调）→ 回调完成后 WriteContext 释放回池。ERROR 状态内部是一个两步异步清理过程（回应 Reviewer P0-2b） |

#### ReplicaTask 状态机

```
[QUEUED] ──dequeue──> [TRANSFERRING] ──rdma_ack──> [REPLICATED]
                           │
                      rdma_nack(retry<3)    rdma_nack(retry>=3)
                           │                       │
                           ▼                       ▼
                     [TRANSFERRING]           [DEGRADED]
                       (retry)
```

| 状态 | 进入条件 | 退出条件 | 停留期间的行为约束 |
|------|----------|----------|------------------|
| QUEUED | WriteContext COMMITTED 后入队 | 冗余模块 dequeue | 在 rte_ring 中等待 |
| TRANSFERRING | 开始 RDMA 传输 | 目标节点 ACK 或重试耗尽 | I9 异步传输进行中 |
| REPLICATED | 所有目标节点 ACK | I4 通知 S2 状态更新完成 | 通过 I4 通知 S2 将数据状态从 COMMITTED 更新为 AVAILABLE（回应 Reviewer P0-1：补充 AVAILABLE 状态上报，使 S4 调度器可区分"主副本就绪"和"所有副本就绪"进行路由决策） |
| DEGRADED | 重试 3 次仍失败 | 运维介入或节点恢复 | 标记副本降级，通过 I8 心跳上报调度器；S2 中数据保持 COMMITTED 状态（非 AVAILABLE） |

### 生命周期

**KVBlock 生命周期**：

1. **创建**：I1 kv_put → WriteContext 状态机驱动 → NVMe 持久化 + 元数据 COMMITTED
2. **缓存提升**：首次读取或写入后异步提升 → DRAM TierSlot 分配 → 数据拷贝到 DRAM
3. **活跃使用**：I2 kv_get 命中 DRAM Cache → LRU 位置更新 → 引用计数递增（S2 管理）
4. **缓存淘汰**：DRAM 空间不足 → LRU 尾部 TierSlot 回收（非 pinned）→ 数据仍在 NVMe SSD
5. **删除**：引用计数归零（S2 通知）→ StorageBackend 释放 NVMe 空间 → DRAM TierSlot 回收

**资源分配与释放责任**：
- DMA 缓冲区：WriteContext 创建时从预分配池获取，META_CONFIRMING 进入时释放回池（数据已在 NVMe），ERROR 时释放回池
- TierSlot：分层模块分配，LRU 淘汰或 KVBlock 删除时释放
- Blobstore blob：StorageBackend 分配，KVBlock 删除时释放（异步）
- ReplicaTask：WriteContext COMMITTED 时创建，REPLICATED/DEGRADED 时释放

> 回应 Reviewer P1-4：DMA 缓冲区池设计
>
> | 参数 | 值 | 说明 |
> |------|-----|------|
> | 单个缓冲区大小 | 32MB（Phase 1 固定） | 对齐 hugepage，通过 `spdk_dma_malloc` 分配 |
> | 池大小 | 64 个缓冲区（共 2GB hugepage） | 支持 64 个并发写入 |
> | 缓冲区耗尽策略 | 排队等待（FIFO），等待超时 500ms 后返回 EBUSY | 不丢弃请求，背压传导到 S5 连接器 |
> | 内存来源 | 启动时一次性从 hugepage 预分配，运行期间不增长 | 与 DRAM Cache TierSlot 池共享 hugepage 总量，启动配置中明确划分比例 |
>
> SPDK hugepage 总量分配（1TB DRAM 节点，估算）：
> - DMA 缓冲区池：2GB（64 × 32MB）
> - Blobstore 元数据缓存：~5-10GB（取决于 blob 数量）
> - DRAM Cache TierSlot 池：~980-990GB（剩余全部用于读缓存）
> - 实际可用缓存容量约为标称 DRAM 的 98%（回应 Reviewer 风险补充：SPDK hugepage 与 DRAM Cache 竞争）

---

## 并发模型

### 线程模型（基于 SPDK Reactor）

S1 运行在 SPDK Reactor 框架内，采用 run-to-completion 模型：每个 reactor 线程绑定一个 CPU core，通过 poller 轮询处理事件，无上下文切换。

| 线程/角色 | 数量 | 职责 | 与其他角色的同步方式 |
|-----------|------|------|---------------------|
| IO Reactor | 1~2（按 NVMe 设备数） | NVMe I/O 处理、Blobstore 操作、WriteContext/ReadContext 状态机推进 | 无锁：所有 I/O 操作在同一 reactor 线程内完成 |
| Network Reactor | 1 | RDMA CQ 轮询（Phase 1 事件驱动）、I1/I2/I12 请求接收、I7/I9 传输发起 | 与 IO Reactor 通过 rte_ring 无锁队列通信 |
| Replica Worker | 1 | 消费 ReplicaTask 队列、管理副本传输状态、重试逻辑 | 从 IO Reactor 通过 rte_ring 接收 ReplicaTask |
| Heartbeat Timer | 复用 IO Reactor | 周期性（1s）通过 I8 上报节点状态 | spdk_poller_register 注册定时器 |

### 锁策略

| 锁名称 | 保护的数据/资源 | 锁类型 | 持有范围 | 锁顺序（全局编号） |
|--------|----------------|--------|----------|------------------|
| `dram_cache_lock` | TierSlot 哈希索引 + LRU 链表 | rwlock | 读：kv_get 查找；写：TierSlot 分配/淘汰 | #1 |
| `blob_alloc_lock` | Blobstore blob 分配表 | spinlock | StorageBackend alloc/free | #2 |

**锁顺序规则**：
- 全局锁获取顺序：`dram_cache_lock(#1) → blob_alloc_lock(#2)`
- 热路径（kv_get DRAM 命中）仅需 `dram_cache_lock` 读锁，无竞争
- 禁止在持有锁时调用 I4/I7/I9 等跨子系统接口

**热路径无锁设计**：
- WriteContext/ReadContext 状态机在单个 reactor 线程内推进，无需锁
- IO Reactor 与 Network Reactor 之间通过 rte_ring 无锁队列通信
- ReplicaTask 入队/出队通过 rte_ring 无锁操作

### 无锁结构

- 无锁结构名称：`rte_ring`（SPDK 内置，来自 DPDK）
- 适用场景：IO Reactor ↔ Network Reactor 跨线程通信、ReplicaTask 队列
- 正确性验证手段：DPDK 社区已通过大规模生产验证；本项目通过 TSan 验证集成正确性
- ABA 问题的处理：rte_ring 基于 CAS 操作，内部使用序列号避免 ABA
- 内存回收策略：rte_ring 本身是固定大小环形缓冲区，不涉及动态内存回收；队列中的 WriteContext/ReplicaTask 从预分配池获取和归还

### DRAM Cache 并发访问

> 回应 Reviewer P0-3：LRU 链表位置更新不是原子操作（涉及 3 次指针修改），在持有读锁时多线程并发更新会导致数据竞争。采用 reviewer 建议的方案 (c)：access_count 原子递增 + 后台定期重排。

DRAM Cache 的并发模型（修正后）：
- **读路径**（高频，热路径）：获取 `dram_cache_lock` 读锁 → 哈希查找 → `__atomic_fetch_add(&slot->access_count, 1, __ATOMIC_RELAXED)` 原子递增访问计数 → 释放读锁。**不修改 LRU 链表**，避免读路径上的写竞争
- **LRU 重排**（低频，后台）：IO Reactor 注册 spdk_poller（间隔 100ms），获取 `dram_cache_lock` 写锁 → 根据 access_count 对 LRU 链表重排（高访问计数移向头部）→ 重置 access_count → 释放写锁。单次重排耗时与 TierSlot 数量成正比，~30,000 个 slot 约 ~1ms
- **淘汰路径**（低频）：获取 `dram_cache_lock` 写锁 → 从 LRU 尾部选择非 pinned 的 TierSlot 回收 → 释放写锁
- **提升路径**（低频）：获取 `dram_cache_lock` 写锁 → 分配 TierSlot + 插入 LRU 头部 → 释放写锁
- **pin/unpin**（极低频）：获取 `dram_cache_lock` 写锁 → 修改 pinned 标记 → 释放写锁

读写比预期 50:1~500:1（ADR-009），读路径仅需读锁 + 原子递增（无写竞争），与"热路径零分配"原则兼容。后台重排的 100ms 间隔在 LRU 精度和锁竞争之间取平衡——KV Cache 的访问模式变化较慢（秒级），100ms 重排精度足够。

---

## 错误处理策略

### 错误分类

| 错误类型 | 示例 | 处理原则 |
|----------|------|----------|
| 可恢复错误 | RDMA 传输超时、NVMe 临时繁忙（EAGAIN）、S2 元数据服务暂时不可用 | 重试 + 指数退避（最多 3 次），记录 warning 日志 |
| 局部故障 | 单块 NVMe SSD 损坏、DRAM ECC 错误、单个副本节点不可达 | 隔离故障组件；SSD 损坏标记坏块并从副本恢复；副本不可达标记 DEGRADED |
| 全局故障 | Blobstore 元数据损坏、SPDK reactor 崩溃、所有副本不可用 | 拒绝新写入；进入只读模式；触发 P0 告警；等待运维介入 |
| 编程错误 | WriteContext 状态机非法跃迁、CRC 校验失败（内部数据）、rte_ring 溢出 | 记录 panic 信息 + coredump；快速失败（fail-fast） |

### 降级策略

**DRAM Cache 降级**：
- 触发条件：DRAM ECC 错误或 DRAM 使用率 > 95%
- 降级行为：停止新的 TierSlot 分配，所有读请求直接走 NVMe SSD
- 恢复条件：DRAM 使用率降至 < 80% 或 ECC 错误清除

**副本降级**：
- 触发条件：目标副本节点连续 3 次 RDMA 传输失败
- 降级行为：标记该副本为 DEGRADED，通过 I8 心跳上报调度器；新写入仅复制到可用副本
- 恢复条件：目标节点恢复后，调度器触发副本重建

**元数据服务不可用降级**：
- 触发条件：I4 update_block_table 连续 3 次超时（每次 1s）
- 降级行为：本地数据标记为 UNCOMMITTED（孤儿数据），返回写入错误给 S5
- 恢复条件：S2 恢复后，S1 重试 UNCOMMITTED 数据的元数据确认

### 熔断 / 限流

| 机制 | 触发阈值 | 生效行为 | 恢复策略 |
|------|----------|----------|----------|
| 写入限流 | NVMe 写入队列深度 > 256 或 DRAM 使用率 > 95% | 拒绝新 I1 请求，返回 BUSY | 队列深度 < 128 或 DRAM < 80% 后恢复 |
| 副本熔断 | 单节点副本失败率 > 50% 持续 30s | 停止向该节点发送副本请求 | 半开探测（每 10s 发送 1 个探测请求），连续 3 次成功后恢复 |
| 全局写入熔断 | NVMe 空间使用率 > 95% | 拒绝所有新写入，仅允许读取和删除 | 空间使用率 < 85% 后恢复 |

### 告警阈值

| 告警项 | 触发条件 | 级别 | 响应 SLA |
|--------|----------|------|----------|
| NVMe 写入延迟异常 | P99 > 2ms 持续 5 分钟 | P1 | 30 分钟内响应 |
| DRAM 缓存命中率过低 | 命中率 < 50% 持续 10 分钟 | P1 | 30 分钟内响应 |
| 副本降级 | 任一副本节点 DEGRADED | P1 | 30 分钟内响应 |
| NVMe 空间不足 | 使用率 > 90% | P2 | 2 小时内响应 |
| CRC 校验失败 | 任何一次 CRC 校验失败 | P0 | 5 分钟内响应 |
| Blobstore 元数据损坏 | Blobstore 初始化失败或操作返回元数据错误 | P0 | 5 分钟内响应 |

---

## 可观测性设计

### 关键指标

| 指标类别 | 指标名 | 类型 | 说明 |
|----------|--------|------|------|
| RED | `s1_write_requests_total` | Counter | 写入请求总数（按状态：success/error/timeout） |
| RED | `s1_read_requests_total` | Counter | 读取请求总数（按状态和缓存命中：dram_hit/ssd_hit/miss） |
| RED | `s1_write_latency_seconds` | Histogram | 写入延迟分布（buckets: 100μs, 500μs, 1ms, 2ms, 5ms, 10ms） |
| RED | `s1_read_latency_seconds` | Histogram | 读取延迟分布（按 DRAM/SSD 分别统计） |
| USE | `s1_nvme_utilization_ratio` | Gauge | NVMe SSD 空间使用率 |
| USE | `s1_dram_utilization_ratio` | Gauge | DRAM Cache 使用率 |
| USE | `s1_nvme_queue_depth` | Gauge | NVMe I/O 队列深度 |
| Custom | `s1_dram_cache_hit_ratio` | Gauge | DRAM 缓存命中率（滑动窗口 60s） |
| Custom | `s1_replica_queue_depth` | Gauge | 副本复制队列深度 |
| Custom | `s1_replica_degraded_count` | Gauge | 当前降级副本数 |
| Custom | `s1_lru_evictions_total` | Counter | LRU 淘汰次数 |
| Custom | `s1_crc_failures_total` | Counter | CRC 校验失败次数 |

### 日志策略

| 日志级别 | 输出内容 | 采样策略 |
|----------|----------|----------|
| ERROR | CRC 校验失败、Blobstore 操作失败、全局故障 | 100% |
| WARN | 副本传输失败、元数据确认超时、DRAM 使用率 > 90% | 100% |
| INFO | 节点启动/停止、DRAM Cache 预热完成、副本状态变更 | 100% |
| DEBUG | 单次写入/读取详细跟踪、LRU 淘汰详情、状态机跃迁 | 按需开启或 1% 采样 |

### 追踪点

> 回应 Reviewer P2-1：补充分布式追踪点定义。

| 追踪点名称 | 所在阶段 | 携带的关键标签 |
|------------|----------|----------------|
| `s1.write.init` | WriteContext 创建 | request_id, key, payload_size, source_node |
| `s1.write.space_allocated` | Blobstore blob 分配完成 | request_id, blob_id, alloc_latency_us |
| `s1.write.rdma_received` | RDMA 数据拉取完成 | request_id, transfer_size, rdma_latency_us |
| `s1.write.nvme_written` | NVMe 写入完成 | request_id, nvme_latency_us |
| `s1.write.meta_confirmed` | Raft majority 确认 | request_id, raft_latency_us, retry_count |
| `s1.write.done` | 写入完成回调 | request_id, total_latency_us, status |
| `s1.read.start` | kv_get 请求到达 | request_id, key |
| `s1.read.cache_hit` | DRAM Cache 命中 | request_id, tier=dram, lookup_latency_us |
| `s1.read.cache_miss` | DRAM Cache 未命中，走 SSD | request_id, tier=ssd, nvme_read_latency_us |
| `s1.read.done` | 读取完成回调 | request_id, total_latency_us, from_tier |
| `s1.replica.enqueued` | ReplicaTask 入队 | request_id, key, target_nodes |
| `s1.replica.completed` | 所有副本 ACK | request_id, replica_latency_us |
| `s1.replica.degraded` | 副本降级 | request_id, failed_node, retry_count |

trace_id 由 S5 连接器在请求入口生成，通过 I1/I2 请求参数传递到 S1，S1 在所有追踪点中携带 trace_id，支持跨子系统的端到端延迟分析。

---

## 接口契约

| 接口名 | 输入 | 输出 | 前置条件 | 后置条件 | 异常返回 | 性能约束 |
|--------|------|------|----------|----------|----------|----------|
| `kv_put(key, hints, rdma_mr)` | key: hash128_t; hints: put_hints_t（含 op_type）; rdma_mr: RDMA MR 描述符 | write_result_t: {status, version, latency_us} | key 非空；rdma_mr 已注册；NVMe 空间可用 | 数据已持久化到本地 NVMe + 元数据 COMMITTED；ReplicaTask 已入队 | ENOMEM（空间不足）、EBUSY（队列满）、EIO（NVMe 错误）、ETIMEOUT（元数据确认超时） | P50 < 1ms; P99 < 5ms |
| `kv_get(key)` | key: hash128_t | read_result_t: {status, data_ptr, size, crc32c, from_tier} | key 已 COMMITTED（S2 确认） | 数据通过 RDMA 传输到请求方；LRU 位置已更新 | ENOENT（未找到）、EIO（SSD 读取错误）、ECRC（校验失败） | DRAM 命中 P50 < 500μs; SSD P50 < 2ms |
| `replica_receive(key, block)` | key: hash128_t; block: 数据缓冲区 | replica_ack_t: {status, key} | 本地 NVMe 空间可用 | 数据已持久化到本地 NVMe；本地 WAL 已更新 | ENOMEM、EIO | P50 < 500μs |
| `heartbeat_report()` | — | node_status_t: {node_id, dram_usage, nvme_usage, active_conns, health, replica_degraded_count} | — | 状态已上报给 S4 | — | 周期 1s，耗时 < 1ms |

---

## 与周边子系统的边界

| 相邻子系统 | 交互方式 | 数据/控制流 | 责任归属 |
|------------|----------|-------------|----------|
| S2 元数据服务 | 同步 RPC（I4） | S1 写入 NVMe 后请求 S2 更新 Block Table（key→location 映射 + COMMITTED 状态） | `☑ 协商标定`：S1 负责提供 key+location，S2 负责 Raft 一致性确认；I4 超时由 S1 重试 3 次 |
| S3 传输层 | 异步 RDMA（I7, I9） | S1 通过 I7 发起 RDMA 数据拉取/推送；通过 I9 发起异步副本复制 | `☑ S1 负责`：S1 决定何时传输、传输什么；S3 负责 RDMA/TCP 协议细节和连接管理 |
| S3 传输层 | 异步回调（I12） | S3 接收远端副本数据后回调 S1 的 replica_receive | `☑ 协商标定`：S3 负责 RDMA 接收和数据完整性校验；S1 负责本地持久化和 WAL 更新 |
| S4 调度器 | 异步心跳（I8） | S1 周期性上报节点状态（DRAM/NVMe 使用率、健康状态、副本降级信息） | `☑ S1 负责`：S1 负责采集和上报状态；S4 负责基于状态做路由决策 |
| S5 连接器 | 异步 RPC + RDMA（I1, I2） | S5 发起 kv_put/kv_get 请求，S1 处理并回调 | `☑ 协商标定`：S5 负责参数合法性校验和超时控制；S1 负责数据处理和持久化；RDMA MR 由 S5 注册，S1 使用 |

**边界责任说明**：
- **S1 负责**：NVMe I/O、DRAM 缓存管理、LRU 淘汰决策、副本复制发起、CRC 校验、DMA 缓冲区管理
- **调用方负责**：S5 负责 key 合法性、RDMA MR 注册、请求超时控制；S4 负责路由决策
- **协商标定**：I4 的超时和重试策略（S1 重试 3 次，每次 1s）；I12 的数据完整性校验（S3 校验 RDMA 传输，S1 校验 CRC）

---

## 风险与缓解

| 风险 | 可能性 | 影响 | 缓解策略 |
|------|--------|------|----------|
| Blobstore GC 在高写入负载下产生延迟抖动 | 高 | 中 | 监控 GC 频率和耗时；限制 GC 并发度；Phase 2 日志结构引擎消除 GC |
| DRAM 缓存命中率低于 ADR-008 H1 假设（80%） | 中 | 高 | 容量规划工具预估热数据集大小；支持 pin/unpin 接口（Phase 2）；LRU 策略可替换为 LRU-K 或 ARC |
| StorageBackend 抽象层引入性能开销 | 低 | 中 | 抽象层仅为函数指针间接调用（~1ns），热路径无虚函数表查找；原型验证确认开销可忽略 |
| WriteContext 状态机复杂度导致边界条件 bug | 中 | 高 | 状态机跃迁表驱动实现（非 if-else 链）；每个状态跃迁有 assert 校验；TSan 验证并发正确性 |
| rte_ring 队列溢出导致 ReplicaTask 丢失 | 低 | 高 | 队列大小预分配为 4096（远大于并发写入数）；溢出时记录 ERROR 日志 + 计数器递增；**兜底恢复机制**：S2 定期 scrub（每 10 分钟）检查副本数不足的 KVBlock，触发补副本任务下发给 S1（回应 Reviewer P1-2） |
| Phase 1→Phase 2 StorageBackend 替换时数据迁移 | 中 | 高 | 双引擎并行运行期：新写入走日志结构引擎，旧数据后台迁移；迁移完成后停止 Blobstore |
| Blobstore blob alloc 延迟在高并发下不可控（Reviewer 隐性假设） | 中 | 中 | 原型压测：1000 并发 blob alloc 的 P99 延迟；若 > 100μs 考虑预分配 blob 池 |
| 单 IO Reactor 在多 NVMe 设备下成为 CPU 瓶颈（Reviewer 隐性假设） | 中 | 中 | 原型验证：单 reactor 在 4 块 NVMe SSD 下的 CPU 利用率；瓶颈时增加 IO Reactor 数量 |

---

## 待决策问题

1. **DRAM Cache 预热策略**：
   - 选项 A：冷启动，完全依赖读请求驱动缓存填充
   - 选项 B：启动时从 NVMe SSD 扫描最近访问的 KVBlock 预加载到 DRAM
   - 需要：原型验证预热时间和对启动延迟的影响

2. **KVBlock 大小是否固定**：
   - ~~选项 A：固定 32MB（简化 Blobstore 分配和 DRAM TierSlot 管理）~~
   - ~~选项 B：可变大小（32MB~128MB），按实际 KV Cache 大小分配~~
   - **决策（回应 Reviewer P2-2）**：Phase 1 固定为 32MB。理由：① 简化 DMA 缓冲区池和 TierSlot 管理；② Blobstore blob 粒度统一；③ 大于 32MB 的 KV Cache 由 S5 连接器拆分为多个 32MB KVBlock。Phase 2 再根据 vLLM/SGLang 实际 KV Cache 大小分布评估是否支持可变大小

3. **Phase 2 日志结构引擎的 GC 策略**：
   - 选项 A：后台 GC（类似 LSM-Tree compaction）
   - 选项 B：WORM 场景下无需 GC（数据只写不改，删除时标记，空间回收靠 segment 整体回收）
   - 需要：分析 KV Cache 删除模式（TTL 过期 vs 显式删除 vs LRU 淘汰）

---

## 参考

- [标杆分析：InfiniStore](../reference/arch-infinistore.md) — 内存池管理、RDMA 双边传输
- [标杆分析：LMCache](../reference/arch-lmcache.md) — 分层缓存策略、Write-All 模型
- [标杆分析：MoonCake](../reference/arch-mooncake.md) — DRAM 为主存储、PD 分离传输
- [ADR-002：存储引擎决策](../adr.md#adr-002) — Blobstore 保底 + 日志结构演进
- [ADR-005：冗余策略决策](../adr.md#adr-005) — 3 副本异步复制
- [ADR-008：分层策略决策](../adr.md#adr-008) — 混合分层 + LRU 本地自治

---

## 架构师自检清单

- [x] 本方案至少对比了 2 个候选方案和 1 个被排除方案，且每个方案都有明确的参考来源
- [x] 决策 rationale 包含时间复杂度、空间效率、一致性/正确性、工程复杂度四个维度的量化比较
- [x] 核心数据结构已列出，状态机包含完整的进入/退出条件和停留期间的行为约束
- [x] 并发模型中明确了锁的类型、范围、全局获取顺序，且无锁结构已说明验证手段
- [x] 错误处理策略覆盖了可恢复错误、局部故障、全局故障和编程错误，并定义了降级/熔断/限流触发条件
- [x] 关键接口的输入、输出、前置条件、后置条件、异常返回、性能约束均已明确
- [x] 与每个周边子系统的边界已明确责任归属
- [x] 文档中没有出现具体的函数实现、变量命名、代码级别的注释或伪代码细节
- [x] 所有设计决策都与系统级总纲中的全局约束保持一致
- [x] 可观测性设计中已定义 RED/USE 指标、日志级别策略和关键追踪点
