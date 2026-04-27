# S2 元数据服务架构设计

> **文档状态**：🟡 Phase A 初稿（待 architect-reviewer 质疑）
> **关联 ADR**：ADR-003（索引策略）、ADR-004（一致性模型）、ADR-009（元数据存储引擎）
> **关联接口**：I4, I5, I6, I10, I11
> **模板**：arch-subsystem.md

---

## 设计目标

S2 元数据服务是系统的控制平面核心，负责**全局 KV Cache 数据的位置索引、前缀匹配和一致性保障**。

**在系统中的定位**：
- S2 是唯一管理全局 Block Table（KVBlock 位置索引）的子系统
- S2 是唯一执行 Prefix Hash Chain 前缀匹配的子系统
- S2 通过分区 Raft 保证元数据强一致性（ADR-004 元数据层）
- S2 不直接操作 NVMe SSD 数据（由 S1 负责），不参与数据面传输（由 S3 负责）

**边界约束**：
- Block Table 更新：S1 写入 NVMe 后通过 I4 请求 S2 更新，S2 通过 Raft majority 确认后返回 COMMITTED
- 位置查询：S5 通过 I5 查询 KVBlock 位置，S2 从内存哈希表直接返回（无 I/O）
- 前缀匹配：S5 通过 I6 批量查询 Prefix Hash Chain，S2 在内存中完成链式遍历
- Raft 通信：S2 通过 I11 委托 S3 传输层进行节点间 Raft 消息传输
- 数据分布查询：S4 通过 I10 查询 key range 内的数据分布

**核心挑战**：
1. 在内存哈希表中支持百万~千万级 chunk 的 O(1) 查找，同时维护 Prefix Hash Chain 的链式索引
2. 分区 Raft 在 4~16 节点下达到 QPS > 10K/s（ADR-004 H2），不成为写入路径瓶颈
3. 异步 WAL 与 Raft 日志的协调：本地 WAL 记录所有本地变更，Raft 日志记录跨节点协调操作（ADR-009 X3）
4. WAL 丢失后的元数据重建：需扫描 NVMe SSD 重建内存状态，100TB 约 9.3h（ADR-009）
5. Block Table 分片策略：避免热点分片，支持 Phase 2 自动扩展

---

## 核心概念

| 概念 | 定义 | 与周边系统的关系 |
|------|------|-----------------|
| **BlockEntry** | Block Table 中的一条记录，包含 key（chunk_id）、location（node_id + offset）、status（COMMITTED/AVAILABLE）、refcount、checksum、tier_info（层级/pin 状态/access_count）。内存中以 uthash 哈希表存储，持久化到本地 WAL | S1 通过 I4 创建/更新 BlockEntry；S5 通过 I5 查询 BlockEntry；S4 通过 I10 批量查询 |
| **PrefixChain** | Prefix Hash Chain 索引节点，每个节点对应一个 token 序列的 SHA-256 哈希值，通过 parent 指针形成链式结构。用于前缀匹配：从目标 prompt 的最长前缀开始，沿链回溯查找已缓存的最长匹配 | S5 通过 I6 发起批量前缀查找；PrefixChain 节点与 BlockEntry 通过 chunk_id 关联 |
| **MetaPartition** | 元数据分区，Block Table 按 key 哈希分片后的一个子集。每个 MetaPartition 由一个独立的 Raft 组管理，包含该分片内的所有 BlockEntry 和关联的 PrefixChain 节点 | 分区数量在集群初始化时确定（Phase 1 固定 16 分区），每个分区 3 副本分布在不同节点 |
| **MetaWAL** | 本地预写日志，记录内存哈希表的增量变更（insert/update/delete）。与 Raft 日志互补：Raft 日志记录跨节点协调操作，MetaWAL 记录所有本地变更。崩溃恢复时先从 Raft 恢复协调状态，再从 MetaWAL 恢复本地状态 | S2 内部概念，不暴露给其他子系统。WAL 文件存储在 NVMe SSD 上（通过 SPDK 写入） |
| **RaftGroup** | 一个 Raft 一致性组实例，管理一个 MetaPartition 的 3 副本。负责 leader 选举、日志复制、成员变更。每个节点上运行多个 RaftGroup（分区数/节点数个） | S2 通过 I11 委托 S3 传输 Raft 消息；RaftGroup 的 leader 处理该分区的所有写请求 |

---

## 方案对比

> ADR-003/004/009 已决策索引策略、一致性模型和存储引擎选型。本节聚焦 S2 **内部架构组织方式**：Raft 分区策略、Block Table 与 Prefix Index 的关系、元数据分片粒度。

### 方案 A：统一分区模型（Unified Partition）

**核心思路**：Block Table 和 Prefix Hash Chain 共享同一套分区方案。每个 MetaPartition 管理一个 key 哈希范围内的所有 BlockEntry 和 PrefixChain 节点。写入 BlockEntry 时同步更新关联的 PrefixChain 节点，两者在同一个 Raft 日志中原子提交。

**参考来源**：TiKV Region-based Raft（每个 Region 是一个 Raft 组管理一个 key range）`☑ 标杆产品`

**优点**：
1. **原子一致性**：BlockEntry 和 PrefixChain 在同一 Raft 组内更新，无跨组事务问题
2. **实现简单**：单一分区方案，无需协调两套分片逻辑
3. **查询局部性**：同一 key 的 BlockEntry 和 PrefixChain 在同一分区，单次 RPC 可完成

**缺点**：
1. **前缀匹配跨分区**：Prefix Hash Chain 的链式遍历可能跨越多个分区（父子 chunk 的 key 哈希落在不同分区），导致前缀匹配需要多次跨分区 RPC
2. **热点放大**：热门 prefix 的所有 chunk 可能集中在少数分区，导致这些分区的 Raft leader 成为瓶颈
3. **分区扩展时 PrefixChain 断裂**：分区分裂时需要处理跨分区的 PrefixChain 指针，增加分裂复杂度

**适用场景**：前缀匹配查询频率低、Block Table 点查为主的场景。

---

### 方案 B：分离索引模型（Separated Index）

**核心思路**：Block Table 和 Prefix Hash Chain 使用不同的组织方式。Block Table 按 chunk_id 哈希分区，每个分区一个 Raft 组。Prefix Hash Chain 作为独立的二级索引，维护在每个节点的本地内存中（非 Raft 复制），通过 Block Table 的 Raft 日志回放重建。前缀匹配在本地完成，命中后通过 chunk_id 查询 Block Table 获取位置。

**参考来源**：LMCache 单节点 Prefix Hash Chain（本地索引）+ CockroachDB 二级索引（从主索引派生）`☑ 标杆产品`

**优点**：
1. **前缀匹配纯本地**：PrefixChain 在每个节点本地维护完整副本，前缀匹配无需跨节点 RPC，P99 < 1ms
2. **Block Table 分区无干扰**：Block Table 分区策略不受 PrefixChain 约束，可独立优化
3. **分区扩展简单**：Block Table 分裂时无需处理 PrefixChain 指针
4. **与 LMCache 标杆对齐**：LMCache 的 Prefix Hash Chain 就是单节点本地索引

**缺点**：
1. **PrefixChain 一致性延迟**：PrefixChain 从 Raft 日志异步派生，存在短暂不一致窗口（新写入的 BlockEntry 已 COMMITTED 但 PrefixChain 尚未更新）
2. **内存开销翻倍**：每个节点维护全量 PrefixChain 副本，N 节点集群的 PrefixChain 总内存 = N × 全量索引大小
3. **重建成本**：节点重启时需从 Raft 日志回放重建 PrefixChain，重建时间与 chunk 总量成正比

**适用场景**：前缀匹配是高频操作、追求最低前缀查询延迟、可接受短暂不一致窗口的场景。

---

### 被排除方案

#### 方案 C：全局单 Raft 组（Single Raft Group）

**核心思路**：所有元数据（Block Table + PrefixChain）放在一个 Raft 组中，不分区。

**参考来源**：etcd 单 Raft 组模型 `☑ 标杆产品`

**排除理由**：
1. **吞吐瓶颈**：单 Raft 组的写入吞吐受限于 leader 单线程处理能力。ADR-004 H2 要求 QPS > 10K/s，单 Raft 组在 16 节点、百万级 chunk 下预计 QPS < 5K/s（参考 etcd 基准：~10K/s 写入，但 etcd 数据量远小于本系统）
2. **leader 单点热点**：所有写入和强一致读都路由到 leader，16 个 Prefill 节点并发写入时 leader CPU 饱和
3. **无法水平扩展**：元数据规模增长时无法通过增加分区来分散负载

### 决策 rationale

选择 **方案 B（分离索引模型）**，原因如下：

1. **时间复杂度**：
   - 方案 A：前缀匹配 O(L × P_cross)，L 为链长度，P_cross 为跨分区概率。128K token prompt 约 1000 个 chunk（128 token/chunk），跨分区概率约 (P-1)/P（P=16 分区时约 94%），导致前缀匹配需要 ~940 次跨分区 RPC
   - 方案 B：前缀匹配 O(L) 纯本地内存遍历，128K token prompt 约 1000 次哈希比较，耗时 < 500μs
   - 在目标场景（128K token 前缀匹配 P99 < 5ms）下，方案 B 的本地遍历远优于方案 A 的跨分区 RPC

2. **空间效率**：
   - 方案 A：PrefixChain 仅存储在所属分区的 Raft 组中，总内存 = 全量索引 × 3（Raft 副本）
   - 方案 B：PrefixChain 在每个节点维护全量副本，总内存 = 全量索引 × N（节点数）。16 节点下约 16 × 500MB = 8GB（估算：1000 万 chunk × 48 字节/PrefixChain 节点 ≈ 480MB）
   - 方案 B 内存开销更高，但在 1TB DRAM/节点的配置下，500MB/节点的 PrefixChain 开销可接受（< 0.05%）

3. **一致性/正确性**：
   - 方案 A：BlockEntry 和 PrefixChain 原子更新，无一致性窗口
   - 方案 B：PrefixChain 从 Raft 日志异步派生，存在短暂不一致窗口（估算 < 10ms）。在此窗口内，新写入的 KVBlock 无法通过前缀匹配命中，但可通过 I5 点查命中。对于 KV Cache 场景，短暂的前缀匹配不一致可接受（最坏情况：推理引擎多做一次 Prefill 计算，约 5s GPU 时间）
   - 方案 B 在 crash 场景下：PrefixChain 从 Raft 日志回放重建，正确性由 Raft 日志保证

4. **工程复杂度**：
   - 方案 A：需要处理跨分区 PrefixChain 遍历的分布式事务，实现复杂度高（估算 8-10 人周）
   - 方案 B：PrefixChain 为纯本地内存结构，实现简单（估算 3-4 人周）。Block Table 分区逻辑独立，可复用 TiKV 风格的 Region 分片
   - 团队对 C 语言 + uthash 的熟悉度高，方案 B 的本地哈希表 + 链式索引实现风险低

**关键 trade-off**：
- 我们放弃了方案 A 的原子一致性（BlockEntry + PrefixChain 同步更新），换取方案 B 的前缀匹配纯本地执行（P99 < 1ms vs 方案 A 的 P99 ~10-50ms）
- 这个取舍在 KV Cache 场景是可接受的，因为：① 前缀匹配是最高频操作（每个新请求都需要）；② 短暂不一致窗口（< 10ms）的代价仅是偶尔多一次 Prefill 计算；③ LMCache 标杆验证了本地 PrefixChain 的可行性

---

## 架构设计

```
┌─────────────────────────────────────────────────────────────────────┐
│                         S2 元数据服务                                │
│                                                                     │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │                    请求路由层（Partition Router）                │  │
│  │  I4/I5/I6/I10 请求 → hash(key) % partition_count → 目标分区    │  │
│  └───────────────────────────┬───────────────────────────────────┘  │
│                              │                                      │
│  ┌───────────────────────────┼───────────────────────────────────┐  │
│  │                    分区管理层                                   │  │
│  │                           │                                    │  │
│  │  ┌─────────────┐  ┌─────────────┐       ┌─────────────┐      │  │
│  │  │ Partition 0 │  │ Partition 1 │  ...  │ Partition 15│      │  │
│  │  │ (Raft组 #0) │  │ (Raft组 #1) │       │ (Raft组 #15)│      │  │
│  │  │             │  │             │       │             │      │  │
│  │  │ ┌─────────┐ │  │ ┌─────────┐ │       │ ┌─────────┐ │      │  │
│  │  │ │BlockEntry│ │  │ │BlockEntry│ │       │ │BlockEntry│ │      │  │
│  │  │ │ uthash   │ │  │ │ uthash   │ │       │ │ uthash   │ │      │  │
│  │  │ └─────────┘ │  │ └─────────┘ │       │ └─────────┘ │      │  │
│  │  │ ┌─────────┐ │  │ ┌─────────┐ │       │ ┌─────────┐ │      │  │
│  │  │ │MetaWAL  │ │  │ │MetaWAL  │ │       │ │MetaWAL  │ │      │  │
│  │  │ └─────────┘ │  │ └─────────┘ │       │ └─────────┘ │      │  │
│  │  └─────────────┘  └─────────────┘       └─────────────┘      │  │
│  └───────────────────────────────────────────────────────────────┘  │
│                                                                     │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │              PrefixChain 本地索引（全量副本）                    │  │
│  │                                                               │  │
│  │  ┌─────────────────────────────────────────────────────────┐  │  │
│  │  │  PrefixChain 内存哈希表（uthash）                        │  │  │
│  │  │  key: prefix_hash (SHA-256)                             │  │  │
│  │  │  value: {chunk_id, parent_hash, token_range, refcount}  │  │  │
│  │  │                                                         │  │  │
│  │  │  更新来源：监听所有分区的 Raft 日志（异步派生）             │  │  │
│  │  └─────────────────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────────────┘  │
│                                                                     │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │                    Raft 引擎层                                 │  │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐                    │  │
│  │  │RaftGroup0│  │RaftGroup1│  │RaftGroupN│  → I11 → S3 传输层  │  │
│  │  └──────────┘  └──────────┘  └──────────┘                    │  │
│  └───────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
```

### 核心流程 1：Block Table 写入（I4）

1. S1 完成 NVMe 写入后，调用 I4: `update_block_table(key, location, COMMITTED)`
2. 请求路由层计算 `hash(key) % 16`，定位目标 MetaPartition
3. 若本节点是该分区的 Raft leader：
   a. 将 BlockEntry 变更编码为 Raft 日志条目
   b. 追加到 Raft 日志，等待 majority 确认（2/3 节点 ACK）
   c. Apply 到本地内存哈希表（uthash insert/update）
   d. 写入本地 MetaWAL（异步，不阻塞返回）
   e. 返回 COMMITTED 给 S1
4. 若本节点不是 leader：转发请求到 leader 节点（通过 I11 → S3）
5. PrefixChain 更新：Raft 日志 apply 后，异步触发 PrefixChain 本地索引更新

### 核心流程 2：Block 位置查询（I5）

1. S5 调用 I5: `lookup_block(key)`
2. 请求路由层计算 `hash(key) % 16`，定位目标 MetaPartition
3. 从本地内存哈希表直接查找（O(1)，无 I/O）
4. 若本节点持有该分区的副本（leader 或 follower）：直接返回 `{node_id, offset, status}`
5. 若本节点不持有该分区：转发到持有该分区的最近节点
6. 未命中返回 NOT_FOUND

### 核心流程 3：前缀匹配（I6）

1. S5 调用 I6: `batch_prefix_lookup(hash_chain)`，hash_chain 为 prompt token 序列按 chunk 粒度计算的 SHA-256 哈希链
2. 在本地 PrefixChain 索引中执行链式遍历：
   a. 从最长前缀（hash_chain 末尾）开始，逐级向前回溯
   b. 每级查找 O(1)（uthash 查找）
   c. 找到最长匹配位置后，收集所有匹配 chunk 的 chunk_id
3. 对每个匹配的 chunk_id，从 Block Table 查询位置（可能跨分区，批量并行查询）
4. 返回 `{match_length, chunk_list: [{chunk_id, node_id, offset}]}`

---

## 数据模型

### 核心数据结构

| 实体 | 用途 | 关键字段 | 持久化方式 |
|------|------|----------|-----------|
| BlockEntry | KVBlock 全局位置索引 | `chunk_id: sha256_t, node_id: uint16_t, offset: uint64_t, status: block_status_e, refcount: uint32_t, checksum: uint32_t, tier: tier_info_t, created_at: uint64_t` | 内存 uthash + MetaWAL + Raft 日志 |
| PrefixNode | Prefix Hash Chain 节点 | `prefix_hash: sha256_t, chunk_id: sha256_t, parent_hash: sha256_t, token_start: uint32_t, token_end: uint32_t, chunk_size_level: uint8_t` | 内存 uthash（从 Raft 日志异步派生，不独立持久化） |
| MetaWALRecord | WAL 日志记录 | `seq_no: uint64_t, op_type: wal_op_e, key: sha256_t, payload: block_entry_t, timestamp: uint64_t` | NVMe SSD（SPDK 写入） |
| RaftLogEntry | Raft 日志条目 | `term: uint64_t, index: uint64_t, op_type: raft_op_e, partition_id: uint16_t, payload: bytes` | NVMe SSD（SPDK 写入，Raft 库管理） |
| PartitionMeta | 分区元信息 | `partition_id: uint16_t, key_range: {start, end}, leader_node: uint16_t, members: [node_id; 3], epoch: uint64_t` | Raft 日志（成员变更通过 Raft 协议） |

### 状态机

#### BlockEntry 状态机

```
[WRITING] --S1 NVMe写入完成 + I4请求--> [COMMITTED] --所有副本ACK(I4 batch)--> [AVAILABLE]
    │                                       │                                      │
    │                                       │                                      │
    └──S1写入失败──> [FAILED]               └──TTL过期/显式删除──> [TOMBSTONE]      └──TTL过期/显式删除──> [TOMBSTONE]
                       │                                              │                                      │
                       └──GC回收──> (删除)                            └──GC回收──> (删除)                    └──GC回收──> (删除)
```

| 状态 | 进入条件 | 退出条件 | 停留期间的行为约束 |
|------|----------|----------|------------------|
| WRITING | S1 开始写入 NVMe（S2 尚未收到 I4 请求） | S1 调用 I4 更新状态 | S2 不感知此状态（S1 内部状态），I5 查询返回 NOT_FOUND |
| COMMITTED | I4 请求经 Raft majority 确认 | 所有副本 ACK 或 TTL 过期 | I5 查询返回 `{location, COMMITTED}`；Decode 节点可发起读取（数据在主副本已持久化） |
| AVAILABLE | S1 所有副本写入完成后通过 I4 批量更新 | TTL 过期或显式删除 | I5 查询返回 `{location, AVAILABLE}`；所有副本就绪，读取可路由到任意副本 |
| TOMBSTONE | TTL 过期或推理引擎显式删除 | GC 回收 | I5 查询返回 NOT_FOUND；空间标记为可回收；保留 tombstone 用于副本同步 |
| FAILED | S1 写入失败 | GC 回收 | I5 查询返回 NOT_FOUND；触发告警 |

#### RaftGroup 状态机

```
[FOLLOWER] --选举超时--> [CANDIDATE] --获得majority投票--> [LEADER]
    ▲                       │                               │
    │                       │ 发现更高term                   │ 发现更高term
    │                       ▼                               ▼
    └───────────────── [FOLLOWER] <──────────────────── [FOLLOWER]
```

| 状态 | 进入条件 | 退出条件 | 停留期间的行为约束 |
|------|----------|----------|------------------|
| FOLLOWER | 初始状态 / 发现更高 term | 选举超时（150-300ms 随机） | 接受 leader 日志复制；响应投票请求；I4 写请求转发到 leader；I5 读请求可本地处理（follower read） |
| CANDIDATE | 选举超时触发 | 获得 majority 投票 / 发现更高 term / 选举超时 | 发起 RequestVote RPC；自增 term；投票给自己 |
| LEADER | 获得 majority 投票 | 发现更高 term / 网络分区导致失去 majority | 处理所有 I4 写请求；发送 AppendEntries 心跳（100ms 间隔）；管理日志复制和提交 |

### 生命周期

**BlockEntry 生命周期**：
1. **创建**：S1 完成 NVMe 写入后调用 I4，S2 在 Raft majority 确认后创建 BlockEntry（COMMITTED 状态）
2. **升级**：S1 所有副本 ACK 后通过 I4 批量更新为 AVAILABLE
3. **访问**：S5 通过 I5/I6 查询，S2 更新 access_count（原子递增，不走 Raft）
4. **淘汰**：TTL 过期或推理引擎显式删除，标记为 TOMBSTONE
5. **回收**：后台 GC 线程定期扫描 TOMBSTONE 条目，超过保留期（默认 1h）后物理删除

**PrefixNode 生命周期**：
1. **创建**：Raft 日志 apply BlockEntry 时，异步派生对应的 PrefixNode
2. **查询**：I6 前缀匹配时遍历
3. **删除**：关联的 BlockEntry 变为 TOMBSTONE 时，异步删除对应 PrefixNode
4. **重建**：节点重启时，从 Raft 日志回放重建全量 PrefixNode

---

## 并发模型

### 线程模型

| 线程/角色 | 数量 | 职责 | 与其他角色的同步方式 |
|-----------|------|------|---------------------|
| Raft IO Reactor | 1 per node | 处理所有 Raft 组的日志复制、心跳、选举定时器；驱动 MetaWAL 写入（SPDK 异步 I/O） | 与 Request Handler 通过 rte_ring 通信（无锁） |
| Request Handler | 1 per node（SPDK reactor 线程） | 处理 I4/I5/I6/I10 请求；路由到目标分区；执行内存哈希表读写 | 与 Raft IO Reactor 通过 rte_ring 提交 Raft 日志条目 |
| PrefixChain Updater | 1 per node | 监听 Raft 日志 apply 事件，异步更新本地 PrefixChain 索引 | 从 Raft IO Reactor 通过 rte_ring 接收 apply 事件 |
| GC Worker | 1 per node | 定期扫描 TOMBSTONE 条目，物理删除过期记录；WAL 截断 | 与 Request Handler 通过 rte_ring 提交删除请求 |

### 锁策略

| 锁名称 | 保护的数据/资源 | 锁类型 | 持有范围 | 锁顺序（全局编号） |
|--------|----------------|--------|----------|------------------|
| `partition_rwlock[i]` | 第 i 个分区的 BlockEntry uthash | rwlock | Request Handler 内 | L1（最外层） |
| `prefix_rwlock` | PrefixChain 全局 uthash | rwlock | PrefixChain Updater 写 / Request Handler 读 | L2 |

**锁顺序规则**：
- 全局锁获取顺序：`partition_rwlock[i]` → `prefix_rwlock`
- 禁止在持有 `prefix_rwlock` 时获取任何 `partition_rwlock`
- I5 点查：获取 `partition_rwlock[i]` 读锁 → 查找 → 释放
- I6 前缀匹配：获取 `prefix_rwlock` 读锁 → 遍历 PrefixChain → 释放 → 对每个匹配的 chunk_id 获取对应 `partition_rwlock[i]` 读锁查询位置
- I4 写入：获取 `partition_rwlock[i]` 写锁 → 更新 uthash → 释放（Raft 日志提交在锁外完成）

### 无锁结构

- 无锁结构名称：`rte_ring`（SPDK/DPDK 内置）
- 适用场景：Raft IO Reactor ↔ Request Handler ↔ PrefixChain Updater ↔ GC Worker 之间的消息传递
- 正确性验证手段：DPDK 社区已通过形式化验证 + 大规模生产验证
- ABA 问题的处理：rte_ring 基于 head/tail 索引的 CAS 操作，不存在 ABA 问题
- 内存回收策略：rte_ring 中传递的是消息指针，消息本身从预分配内存池分配，由接收方负责归还

### 关键并发场景分析

**场景 1：I4 写入与 I5 读取并发**
- I4 写入路径：Raft 日志提交（无锁）→ apply 时获取 `partition_rwlock[i]` 写锁 → 更新 uthash → 释放
- I5 读取路径：获取 `partition_rwlock[i]` 读锁 → 查找 → 释放
- 保证：I5 要么看到更新前的状态，要么看到更新后的状态（rwlock 保证）。Raft majority 确认后 apply，保证 I5 读到的是已提交的数据

**场景 2：I6 前缀匹配与 PrefixChain 更新并发**
- I6 读取路径：获取 `prefix_rwlock` 读锁 → 遍历 → 释放
- PrefixChain Updater：获取 `prefix_rwlock` 写锁 → 插入/删除节点 → 释放
- 保证：I6 遍历期间 PrefixChain 不会被修改。短暂不一致窗口（< 10ms）在 PrefixChain Updater 尚未处理最新 Raft apply 事件时存在

**场景 3：多个 Raft 组并发选举**
- 每个 RaftGroup 独立运行选举定时器，互不干扰
- Raft IO Reactor 单线程串行处理所有 Raft 组的事件，避免并发冲突
- 风险：16 个 Raft 组同时选举时，Raft IO Reactor 可能短暂过载（估算：16 × RequestVote RPC ≈ 16 × 10μs = 160μs，可接受）

---

## 错误处理策略

### 错误分类

| 错误类型 | 示例 | 处理原则 |
|----------|------|----------|
| 可恢复错误 | Raft leader 切换（1-5s）、网络临时超时、WAL 写入临时失败 | 重试 + 指数退避（初始 10ms，最大 1s，最多 5 次）；记录 WARN 日志 |
| 局部故障 | 单个 Raft 组 leader 不可用、单个分区 WAL 损坏 | 隔离故障分区；其他分区继续服务；触发 Raft 重新选举或 WAL 重建 |
| 全局故障 | 多数节点不可用（Raft 无法形成 majority）、内存耗尽 | 拒绝所有写入（I4 返回 UNAVAILABLE）；读取路径降级（I5 从本地缓存返回，I6 返回空匹配）；触发 P0 告警 |
| 编程错误 | 哈希表状态不一致、Raft 日志序号跳跃 | assert 失败 → coredump；快速失败，依赖 Raft 副本接管 |

### 降级策略

**元数据服务暂时不可用（Raft leader 选举窗口 1-5s）**：
- 写入路径（I4）：返回 UNAVAILABLE，S1 本地数据标记为 UNCOMMITTED（孤儿数据），推理引擎收到错误后可重试
- 读取路径（I5）：优先命中本地内存缓存（follower 可直接返回已 apply 的数据），缓存未命中时返回 UNAVAILABLE
- 前缀匹配（I6）：PrefixChain 为本地索引，不受 Raft leader 选举影响，可继续服务。但匹配结果中的位置信息可能需要查询 Block Table（I5），此时可能返回部分结果

**单分区故障**：
- 仅影响该分区 key range 内的 I4/I5 请求
- 其他分区正常服务
- 调度器（S4）可感知分区故障，将请求路由到可用分区覆盖的 key range

### 熔断 / 限流

| 机制 | 触发阈值 | 生效行为 | 恢复策略 |
|------|----------|----------|----------|
| Raft 写入熔断 | 单分区 Raft 日志积压 > 10000 条 或 apply 延迟 > 100ms 持续 30s | 该分区拒绝新 I4 请求，返回 OVERLOADED | 积压降至 5000 条以下后恢复 |
| 内存限流 | BlockEntry 总内存 > 4GB（单节点 5GB 阈值的 80%） | 拒绝新 BlockEntry 创建（I4 返回 QUOTA_EXCEEDED）；触发 GC 加速 | 内存降至 3GB 以下后恢复 |
| PrefixChain 限流 | PrefixChain 更新队列积压 > 50000 条 | 暂停 PrefixChain 更新（不影响 Block Table 写入） | 积压清空后恢复 |

### 告警阈值

| 告警项 | 触发条件 | 级别 | 响应 SLA |
|--------|----------|------|----------|
| Raft leader 选举频繁 | 同一分区 5 分钟内选举 > 3 次 | P1 | 15 分钟内响应 |
| WAL 写入延迟异常 | WAL fsync P99 > 10ms 持续 1 分钟 | P1 | 15 分钟内响应 |
| 内存使用超阈值 | BlockEntry 内存 > 4GB | P1 | 15 分钟内响应 |
| Raft majority 不可用 | 任一分区无法形成 majority 持续 > 10s | P0 | 5 分钟内响应 |
| PrefixChain 不一致窗口过大 | PrefixChain 更新延迟 > 1s | P2 | 30 分钟内响应 |
| 元数据重建触发 | WAL 损坏触发 NVMe 扫描重建 | P0 | 5 分钟内响应 |

---

## 可观测性设计

### 关键指标

| 指标类别 | 指标名 | 类型 | 说明 |
|----------|--------|------|------|
| RED | `meta_i4_requests_total` | Counter | I4 写入请求总数（按 partition_id、status 标签） |
| RED | `meta_i4_errors_total` | Counter | I4 写入错误数（按 error_type 标签） |
| RED | `meta_i4_duration_seconds` | Histogram | I4 写入延迟分布（含 Raft majority 确认） |
| RED | `meta_i5_requests_total` | Counter | I5 查询请求总数 |
| RED | `meta_i5_duration_seconds` | Histogram | I5 查询延迟分布 |
| RED | `meta_i6_requests_total` | Counter | I6 前缀匹配请求总数 |
| RED | `meta_i6_duration_seconds` | Histogram | I6 前缀匹配延迟分布 |
| RED | `meta_i6_match_length` | Histogram | I6 前缀匹配命中长度分布（token 数） |
| USE | `meta_block_entry_count` | Gauge | BlockEntry 总数（按 partition_id 标签） |
| USE | `meta_block_entry_memory_bytes` | Gauge | BlockEntry 内存占用 |
| USE | `meta_prefix_node_count` | Gauge | PrefixNode 总数 |
| USE | `meta_prefix_node_memory_bytes` | Gauge | PrefixNode 内存占用 |
| USE | `meta_raft_log_pending` | Gauge | Raft 日志待 apply 条数（按 partition_id） |
| USE | `meta_wal_size_bytes` | Gauge | MetaWAL 文件大小 |
| Custom | `meta_raft_leader_changes_total` | Counter | Raft leader 切换次数（按 partition_id） |
| Custom | `meta_raft_commit_duration_seconds` | Histogram | Raft majority 确认延迟 |
| Custom | `meta_prefix_update_lag_seconds` | Gauge | PrefixChain 更新延迟（相对 Raft apply） |
| Custom | `meta_gc_tombstone_count` | Gauge | 待回收 TOMBSTONE 条目数 |

### 日志策略

| 日志级别 | 输出内容 | 采样策略 |
|----------|----------|----------|
| ERROR | Raft majority 不可用、WAL 写入失败、内存分配失败、哈希表状态不一致 | 100% |
| WARN | Raft leader 切换、I4 重试、WAL fsync 延迟 > 5ms、内存使用 > 80% 阈值 | 100% |
| INFO | 分区 leader 变更、GC 回收统计、WAL 截断、PrefixChain 重建完成 | 100% |
| DEBUG | 单次 I4/I5/I6 请求详情、Raft 日志条目内容、PrefixChain 遍历路径 | 按需开启（默认关闭） |

### 追踪点

| 追踪点名称 | 所在阶段 | 携带的关键标签 |
|------------|----------|----------------|
| `meta.i4.receive` | I4 请求接收 | request_id, chunk_id, partition_id |
| `meta.i4.raft_submit` | Raft 日志提交 | request_id, partition_id, raft_term |
| `meta.i4.raft_committed` | Raft majority 确认 | request_id, partition_id, commit_latency_us |
| `meta.i4.applied` | 内存哈希表更新完成 | request_id, partition_id |
| `meta.i5.lookup` | I5 查询执行 | request_id, chunk_id, hit/miss |
| `meta.i6.prefix_start` | I6 前缀匹配开始 | request_id, chain_length |
| `meta.i6.prefix_done` | I6 前缀匹配完成 | request_id, match_length, chunks_found |
| `meta.raft.election` | Raft 选举事件 | partition_id, new_leader, term |
| `meta.wal.fsync` | WAL fsync 完成 | partition_id, fsync_latency_us, bytes_written |
| `meta.gc.sweep` | GC 扫描完成 | tombstones_collected, memory_freed_bytes |

---

## 接口契约

| 接口名 | 输入 | 输出 | 前置条件 | 后置条件 | 异常返回 | 性能约束 |
|--------|------|------|----------|----------|----------|----------|
| `I4: update_block_table` | `key: sha256_t, location: {node_id, offset}, status: block_status_e` | `result: {ok/error, committed_index}` | S1 已完成本地 NVMe 写入 | BlockEntry 已在 Raft majority 确认并 apply 到内存 | UNAVAILABLE（Raft 无 leader）、OVERLOADED（日志积压）、QUOTA_EXCEEDED（内存超限） | P99 < 1ms（Raft majority 确认，低-中负载） |
| `I5: lookup_block` | `key: sha256_t` | `result: {node_id, offset, status} / NOT_FOUND` | 无 | 无副作用（纯读） | UNAVAILABLE（本节点不持有该分区且无法转发） | P99 < 100μs（本地内存查找） |
| `I6: batch_prefix_lookup` | `hash_chain: sha256_t[], chain_length: uint32_t` | `result: {match_length, chunks: [{chunk_id, node_id, offset}]}` | hash_chain 按 token 序列顺序排列 | 无副作用（纯读） | UNAVAILABLE（PrefixChain 正在重建） | P99 < 5ms（128K token，~1000 chunk 链） |
| `I10: query_data_distribution` | `key_range: {start, end}` | `result: [{node_id, block_count, total_size}]` | 无 | 无副作用（纯读） | UNAVAILABLE | P99 < 5ms（Phase 1 逐 key 扫描） |
| `I11: raft_send` | `msg: raft_msg_t, target_node: uint16_t` | `result: {ok/error}` | S3 传输层可用 | 消息已发送（不保证到达） | NETWORK_ERROR（目标节点不可达） | P99 < 500μs（RDMA/TCP） |

---

## 与周边子系统的边界

| 相邻子系统 | 交互方式 | 数据/控制流 | 责任归属 |
|------------|----------|-------------|----------|
| S1 存储引擎 | I4 同步调用（Raft majority） | S1 → S2：写入完成后更新 Block Table；S1 → S2：副本 ACK 后批量更新 AVAILABLE 状态 | S1 负责：重试 I4（最多 3 次，指数退避）；S2 负责：Raft 日志持久化和 majority 确认 |
| S3 传输层 | I11 异步消息 | S2 → S3：Raft 协议消息（AppendEntries/RequestVote/Heartbeat） | S2 负责：Raft 协议逻辑和消息编码；S3 负责：消息传输和超时检测 |
| S4 调度器 | I10 同步调用 | S4 → S2：查询 key range 内的数据分布 | S4 负责：查询频率控制（避免过载 S2）；S2 负责：返回准确的分布信息 |
| S5 连接器 | I5/I6 同步调用 | S5 → S2：Block 位置查询和前缀匹配 | S5 负责：请求参数合法性校验、超时控制；S2 负责：查询结果正确性 |

**边界责任说明**：
- **S2 负责**：元数据一致性（Raft 保证）、内存索引维护、WAL 持久化、PrefixChain 派生
- **调用方负责**：请求重试策略（I4 由 S1 重试，I5/I6 由 S5 重试）、超时控制、参数合法性
- **协商标定**：I4 的 BlockEntry 格式（S1 和 S2 共同定义）；I11 的 Raft 消息序列化格式（S2 和 S3 共同定义）

---

## 风险与缓解

| 风险 | 可能性 | 影响 | 缓解策略 |
|------|--------|------|----------|
| WAL 丢失后元数据重建时间过长（100TB 约 9.3h） | 中 | 高 | 增量 checkpoint（每 10 分钟快照内存哈希表到 NVMe）缩短重建时间至分钟级；重建期间只读模式保证数据安全；Raft 日志辅助恢复协调状态 |
| 单分区 Raft leader 成为热点 | 中 | 高 | 16 分区分散负载；热点检测（单分区 QPS > 平均值 3 倍时告警）；Phase 2 支持分区分裂 |
| PrefixChain 全量副本内存开销超预期 | 低 | 中 | 监控 PrefixNode 内存占用；超阈值时降级为按需加载（牺牲前缀匹配延迟）；Phase 2 评估 LMDB 存储 PrefixChain |
| Raft 日志回放重建 PrefixChain 时间过长 | 中 | 中 | PrefixChain 快照（与 BlockEntry checkpoint 同步）；增量回放（仅回放快照之后的日志） |
| 多个 Raft 组同时选举导致短暂不可用 | 低 | 高 | 选举超时随机化（150-300ms）分散选举时间；Raft pre-vote 机制减少不必要选举 |
| 内存哈希表在千万级 chunk 下性能退化 | 低 | 中 | uthash 在千万级 key 下 O(1) 查找性能稳定（哈希冲突率 < 1%）；监控哈希冲突率；超阈值时评估切换到更高效的哈希实现 |
| Block Table 分区数（16）在大规模下不足 | 中 | 中 | Phase 1 固定 16 分区（4~16 节点足够）；Phase 2 支持动态分区分裂（参考 TiKV Region Split） |
| Raft 库选型风险（C 语言成熟 Raft 库有限） | 中 | 高 | 候选：willemt/raft（C 语言，MIT 协议，~3000 行）；备选：自研精简 Raft（~5000 行，仅实现 leader 选举 + 日志复制）；Phase 1 第 2 周进行 Raft 库原型验证 |

---

## 待决策问题

1. **Raft 库选型**：
   - 选项 A：willemt/raft（C 语言开源库，~3000 行，MIT 协议）
   - 选项 B：自研精简 Raft（仅 leader 选举 + 日志复制 + 成员变更，~5000 行）
   - 需要：Phase 1 第 2 周原型验证 willemt/raft 的性能和稳定性

2. **Follower Read 策略**：
   - 选项 A：所有 I5 读请求路由到 leader（强一致，但 leader 负载高）
   - 选项 B：follower 可直接返回已 apply 的数据（可能读到稍旧数据，但负载分散）
   - 需要：评估 KV Cache 场景对读一致性的实际要求（COMMITTED 后 Decode 节点读取是否可接受 follower read）

3. **增量 Checkpoint 格式**：
   - 选项 A：全量快照（简单，但 5GB 数据快照耗时 ~1-2s）
   - 选项 B：增量快照（仅记录上次快照后的变更，复杂但快速）
   - 需要：评估 10 分钟间隔内的变更量，决定全量 vs 增量

---

## 参考

- [ADR-003: KV Cache 索引策略决策](../adr.md#adr-003-kv-cache-索引策略决策)
- [ADR-004: KV Cache 存储系统一致性模型决策](../adr.md#adr-004-kv-cache-存储系统一致性模型决策)
- [ADR-009: 元数据存储引擎选型](../adr.md#adr-009-元数据存储引擎选型)
- [标杆分析：LMCache](../reference/arch-lmcache.md) — Prefix Hash Chain 索引设计
- [标杆分析：MoonCake](../reference/arch-mooncake.md) — Block Table 分布式设计
- [S1 存储引擎架构设计](../storage/design.md) — I4 接口调用方

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
- [x] 所有设计决策都与系统级总纲中的全局约束（一致性模型、故障假设、性能基线）保持一致
- [x] 可观测性设计中已定义 RED/USE 指标、日志级别策略和关键追踪点

