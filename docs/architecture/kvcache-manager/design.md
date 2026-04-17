# KVCache Manager 子系统架构设计

**文档状态**: 修正定稿  
**更新日期**: 2026-04-12  
**关联 ADR**: ADR-001（整体架构）、ADR-003（分层存储）、ADR-006（集成接口）  
**置信度**: 中高（78%）  
**下一步**: 进入控制面协议详细设计与协调状态机原型验证

---

## 1. 设计目标

### 1.1 核心问题

KVCache Manager 是分布式 KV Cache Offloading 系统的**控制面协调中枢**。它回答的关键问题是：在一个由推理引擎、元数据索引、分层存储、网络传输多个子系统构成的分布式环境中，如何确保一次 KV Cache 的分配、加载、保存、淘汰请求在多个子系统之间以一致且可预期的语义执行，并且任何一个子系统的局部故障都不会蔓延为整个请求的失败或数据损坏。

如果没有 KVCache Manager，或该子系统设计不当，将直接导致：

- **子系统间语义失配**：Connector 期望的 "allocate-then-load" 两阶段语义与 Storage 的实际分配策略不一致，导致引擎在加载时遭遇无声的 block 缺失；
- **级联故障失控**：Metadata 索引更新延迟 50ms 期间 Storage 已完成数据迁移，引擎读取到过期的位置信息，触发不可预期的 segment fault 或脏读；
- **全局状态碎片化**：每个子系统各自维护局部的热度视图、容量视图和故障视图，没有统一的协调者来在全局层面做冲突消解和资源仲裁；
- **TTFT 不可预测**：即使每个子系统单独都满足延迟 SLO，跨子系统调用链的叠加和重试会导致首 token 时间出现长尾抖动。

### 1.2 核心职责边界

KVCache Manager 的职责聚焦于**跨子系统请求的协调、状态同步和故障隔离**，不替代任何子系统的内部决策：

- **不负责前缀匹配的具体实现**：由 Metadata 子系统维护 Radix Tree 和 Chunk-Hash；KVCache Manager 只发起查询请求并解释返回的 SegmentMap；
- **不负责数据物理搬运**：由 Storage 子系统的 DataMover 和 TierManager 执行跨层拷贝；KVCache Manager 只在必要时发起 "promote/demote" 协调指令；
- **不负责引擎特定数据结构转换**：由 Connector 子系统的 Engine Adapter 完成 vLLM BlockTable 到内部语义的映射；KVCache Manager 只与 `KVStoreInterface` 交互；
- **不负责网络传输协议细节**：由 Transport 子系统管理 RDMA QP、TCP 连接和重试策略；KVCache Manager 只传递逻辑节点 ID 和优先级标记。

KVCache Manager 是**所有需要跨子系统一致性操作的唯一入口**。当 Connector 需要知道 "这段 token 序列应该加载到哪里" 时，它首先与 KVCache Manager 协商；当 Storage 完成一次跳层直达的异步迁移后，它通过 KVCache Manager 将变更广播到受影响的 Metadata 分片和 Connector 缓存。

### 1.3 质量目标

| 维度 | 目标 | 说明 |
|------|------|------|
| 协调延迟 | 跨子系统查询编排 < 100μs | **仅 KVCache Manager 内部**：单节点内 Metadata→Storage→Connector 在 C 库层面的协调往返，不含引擎适配与 Python 侧开销 |
| 状态一致性 | 子系统间视图差异窗口 < 50ms | 从 Storage 完成迁移到 Metadata 索引更新、Connector 缓存失效的完整传播时间 |
| 故障隔离 | 单个子系统故障导致请求失败率 < 0.1% | 通过降级读取和本地重算路径实现 |
| 可扩展性 | 支持 100+ 节点的控制面拓扑同步 | 通过一致性哈希分段和 gossip 增量传播 |
| 可用性 | 控制面自身可用性目标 99.95% | 单节点故障时 11s 内完成切换（继承 Metadata 子系统的 RTO） |

**协调延迟目标拆解（可控 vs 不可控）**：
100μs 的目标特指 KVCache Manager 作为嵌入式 C 库时，内部的跨子系统协调开销边界。它不涵盖 ADR-006 Library 模式下引擎侧不可控的延迟。具体拆解如下：

| 延迟来源 | 预算 | 可控性 | 说明 |
|----------|------|--------|------|
| Metadata Client 本地查询（C 库内部） | ~15-25μs | KVCache Manager 可控 | 向本地或同机架 Metadata 节点发起前缀查询，不含网络解析 |
| Storage Client 预留/加载协商（C 库内部） | ~15-25μs | KVCache Manager 可控 | 与本地 Storage TierManager 的内存通信 |
| Orchestration Controller 编排计算 | ~10-20μs | KVCache Manager 可控 | Plan 生成、状态机推进、session 上下文更新 |
| Connector Client 结果回传（C 库内部） | ~5-10μs | KVCache Manager 可控 | 将 Coordination Plan 返回给 Connector C 层接口 |
| **小计：KVCache Manager 内部可控开销** | **~45-80μs** | — | 满足 < 100μs 目标，预留 20μs 抖动缓冲 |
| Engine Adapter 数据转换 | ~20-100μs | Connector 子系统可控 | BlockTable 到内部语义的映射，由 Connector 实现优化 |
| Python vLLM 侧 GIL / API 调用 | ~0.5-2ms | 引擎侧不可控 | ADR-006 的 Python Library 接口必须穿越的语言边界开销 |
| RDMA / TCP 实际 DMA 与网络往返 | ~10-200μs | Transport 子系统可控 | 取决于物理距离和传输协议选择 |

此表中，KVCache Manager 只承诺并优化自身可控的 45-80μs 区间。Python GIL 等引擎侧开销不在本目标范围内，但设计上通过"尽量预计算 Plan 在 C 层完成"来减少 Python 路径的调用次数。

## 2. 总体架构与模块设计

### 2.1 模块关系图

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        KVCache Manager Subsystem                             │
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │                     Orchestration Controller                          │  │
│  │              (跨子系统请求编排 / 状态机推进 / 故障决策)                 │  │
│  └─────────────────────────────┬────────────────────────────────────────┘  │
│                                │                                            │
│         ┌──────────────────────┼──────────────────────┐                    │
│         │                      │                      │                    │
│         ▼                      ▼                      ▼                    │
│  ┌──────────────┐      ┌──────────────┐      ┌──────────────┐            │
│  │   Session    │      │   Topology   │      │   Policy     │            │
│  │   Tracker    │      │   Registry   │      │   Engine     │            │
│  │  (请求生命周期)│      │  (控制面拓扑) │      │  (全局策略)   │            │
│  └──────┬───────┘      └──────┬───────┘      └──────┬───────┘            │
│         │                     │                     │                     │
│         └─────────────────────┼─────────────────────┘                     │
│                               │                                           │
│                               ▼                                           │
│  ┌──────────────────────────────────────────────────────────────────────┐│
│  │                     Subsystem Gateway Layer                           ││
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐            ││
│  │  │ Connector│  │ Metadata │  │ Storage  │  │ Transport│            ││
│  │  │  Client  │  │  Client  │  │  Client  │  │  Client  │            ││
│  │  └──────────┘  └──────────┘  └──────────┘  └──────────┘            ││
│  └─────────────────────────────┬───────────────────────────────────────┘│
│                                │                                         │
│    ┌───────────────────────────┼───────────────────────────┐             │
│    │                           │                           │             │
│    ▼                           ▼                           ▼             │
│ ┌───────┐                 ┌───────┐                   ┌───────┐          │
│ │Connector│                │Metadata│                  │Storage│          │
│ │Subsystem│                │Subsystem│                 │Subsystem│         │
│ └───────┘                 └───────┘                   └───────┘          │
│                                                               ▲          │
│                                                               │          │
│                                                          ┌────┴────┐     │
│                                                          │Transport│     │
│                                                          │Subsystem│     │
│                                                          └─────────┘     │
└────────────────────────────────────────────────────────────────────────────┘
```

### 2.2 模块职责与协作

#### Orchestration Controller（编排控制器）

- **职责**：KVCache Manager 的核心心脏。接收来自 Connector 子系统的请求，将其分解为对 Metadata、Storage、Transport 的协调子任务，维护每个请求的状态机，处理子任务失败时的回滚或降级策略。
- **输入**：来自 Connector 的 `kv_session_start`、`layer_load_request`、`layer_save_request`、`session_finalize` 等协调请求。
- **输出**：协调结果（成功、降级成功、失败需重算）、异步事件通知（晋升完成、缓存失效、容量告警）。
- **协作**：向下调用 Subsystem Gateway Layer 的四个客户端；向 Session Tracker 注册和注销请求生命周期；从 Policy Engine 获取当前时刻的全局策略参数（如是否允许预取、是否进入保守模式）。

#### Session Tracker（请求生命周期跟踪器）

- **职责**：为每个推理请求维护一个跨子系统的协调上下文（session context），记录该请求已经访问过的 Metadata 分段结果、Storage 分配的 block 句柄、以及各层的加载/保存状态。
- **输入**：Orchestration Controller 在请求到达时创建的 session entry；各子系统客户端返回的异步完成事件。
- **输出**：session 状态查询结果；用于故障恢复时的部分完成快照。
- **协作**：与 Orchestration Controller 同生命周期；session 在 `session_finalize` 后保留 10 秒（用于对账和异步事件收敛），然后异步回收。

#### Topology Registry（控制面拓扑注册表）

- **职责**：维护 KVCache Manager 控制面自身所需的拓扑视图，包括：当前活跃的本节点 Metadata 分片范围、Storage TierManager 的健康状态、Connector 实例的分布、以及 Transport 子系统提供的节点间距离矩阵缓存。
- **输入**：各子系统的心跳和状态变更事件；gossip 协议传播的节点增删信息。
- **输出**：子系统客户端在路由时的目标节点选择提示；故障隔离时的可用路径列表。
- **协作**：KVCache Manager 将 Metadata 的路由查询**完全委托给 Metadata 子系统自身**——不缓存、不推断 Metadata 的一致性哈希环或分片范围。Topology Registry 只缓存两类轻量信息：
  1. **控制面节点信息**：其他 KVCache Manager 实例的位置、Storage TierManager 的健康状态、Connector 实例分布；
  2. **Transport 距离矩阵**：来自 Transport 子系统的节点间延迟估计（只读缓存）。
  对 Metadata 的调用，KVCache Manager 始终先路由到**固定的本地 Metadata 代理节点**（或 Metadata 提供的 service discovery endpoint），由 Metadata 子系统内部完成一致性哈希定位。此设计消除了 Topology Registry 与 Metadata 路由信息的职责重叠风险。

#### Policy Engine（全局策略引擎）

- **职责**：在全局层面制定跨子系统的协调策略，包括：当前是否启用 PrefetchEngine、跳层直达的晋升/淘汰阈值、SSD 抖动时的保守模式切换、以及多实例共享节点时的 IO 限速配额。
- **输入**：Storage 子系统上报的热度统计和容量压力信号；运维配置中心的策略更新；自动熔断机制触发的模式切换信号。
- **输出**：策略参数快照，下发到 Orchestration Controller 和 Subsystem Gateway Layer。
- **协作**：Policy Engine 的决策分为两层。其中，**全局约束参数**（统一策略版本号、保守模式开关、全局 IO 限速配额、跳层直达的 cluster-wide 启用/禁用标志）对 Storage 子系统具有**强制约束力**，Storage Client 在执行前必须校验版本号，版本不匹配则拒绝执行。**具体的 tiering 执行策略**（如某个 block 晋升为 L1 还是 L2、局部热度是否满足晋升阈值）由 Storage 子系统内的 Tiering Manager 自治决策，KVCache Manager 不干预。这两层的冲突仲裁规则如下：
  - 若强制约束与 Storage 自治决策在物理上冲突（如在全局保守模式下 Storage 局部热度仍建议晋升），以强制约束为准，Storage 侧忽略局部建议；
  - 若仅涉及资源竞争（如多个节点同时请求同一集群 IO 配额），由 Policy Engine 的配额令牌机制裁决，Storage 在未获得配额令牌前不得发起跨层迁移。

#### Subsystem Gateway Layer（子系统网关层）

- **职责**：封装对 Connector、Metadata、Storage、Transport 四个外部子系统的调用协议，提供统一的超时、重试、错误收敛、流量控制语义。
- **输入**：Orchestration Controller 的远程过程调用请求。
- **输出**：经过协议适配和错误收敛后的响应结果。
- **协作**：每个客户端只负责向对应子系统发起调用，不感知上层编排逻辑。例如 Transport Client 只负责返回 "逻辑节点 ID + 预估链路延迟"，不参与实际的数据搬运。

---

## 3. 核心概念与抽象

### 3.1 KV Session：跨子系统协调的原子上下文

KVCache Manager 引入 `KV Session` 作为跨子系统协调的基本工作单元。一个 session 从 Engine 发起 `session_start` 开始，到 `session_finalize` 结束，期间所有跨子系统操作共享同一个 session 上下文。

**session 的核心状态**：
- `INIT`：session 已创建，正在等待 Metadata 查询结果；
- `PLANNED`：已从 Metadata 获取 SegmentMap，正在与 Storage 协商分配/加载计划；
- `LOADING`：layer-wise 加载流水线已启动，部分层可能已完成；
- `COMPUTING`：请求已进入引擎计算阶段，session 处于被动等待保存请求的状态；
- `SAVING`：layer-wise 保存流水线正在异步执行；
- `COMMITTED`：所有保存完成，索引更新已通知 Metadata；
- `ABORTED`：因故障或引擎取消，session 被终止，已分配资源进入回收队列。

**session 状态与异步存储变更的交互**：
`PLANNED` 状态生成的 Coordination Plan 本质上是**执行时刻的快照**。KVCache Manager 的取舍原则是：首层加载数据（直接影响 TTFT）严格按快照执行，避免等待异步状态收敛；后续层的加载则在每次请求前**向 Storage 重新查询**最新位置，从而吸纳在 `LOADING`/`COMPUTING` 期间已完成的异步 promote。具体机制如下：
- 每个命中段（HIT segment）在 Plan 中携带 `storage_version` 标记（来自 Storage 预留响应时刻的版本戳）；
- 当 Orchestration Controller 为下一层发起 `load_layer` 时，主动向 Storage 查询该 segment 的当前最新位置；
- 若 Storage 报告 promote 已完成（版本戳更新），Controller 透明地将加载目标切换到新层级（如 L3 → L1），并同步更新 session 上下文中的命中位置信息；
- 若 Storage 报告 promote 尚未完成，Controller 仍按原快照层级加载，不阻塞等待。

这一设计的 trade-off 是：以首层快照保障 TTFT 可预测，以后续层的“版本戳重查”捕获异步迁移的收益，同时不引入额外阻塞。

session 不是传统事务意义上的 ACID 原子单元，KV Cache 是可重算的，因此允许以下松弛语义：
- **加载阶段失败**：允许降级为部分命中或完全 miss，引擎重算即可；
- **保存阶段失败**：允许部分层的 KV Cache 未被持久化，仅影响未来命中率，不影响当前请求正确性；
- **索引更新延迟**：Metadata 的索引更新在 Storage 落盘之后异步执行，允许最多 50ms 的窗口期。

### 3.2 Coordination Plan：协调计划抽象

当 Metadata 返回一个 SegmentMap 后，Orchestration Controller 将其翻译为一个 `Coordination Plan`。该计划描述：

- **命中段（HIT segments）**：哪些 token 范围可以直接复用缓存，位于哪个存储层级（L1/L2/L3/L4）；
- **缺失段（MISS segments）**：哪些 token 范围需要引擎重新计算，并在计算完成后保存到哪个层级；
- **晋升任务（PROMOTE tasks）**：哪些命中段当前位于 L3/L4，但因热度高或预取信号需要异步晋升到 L1/L2；
- **预留声明（RESERVE entries）**：Storage 为本次 session 的缺失段预留的 block 配额和层级上限。

Coordination Plan 的生成遵循以下优先级：
1. 优先满足 L1 命中（HBM 直接命中延迟最低）；
2. 次优先满足 L2 命中（DRAM 命中仍远快于计算重算）；
3. L3/L4 命中视为 "可用但需异步优化"；
4. 缺失段的预留层级由 Storage 的 SpaceManager 根据当前容量自治决定，KVCache Manager 只请求 "期望最低层级" 而不强制指定。

### 3.3 跨子系统一致性模型：顺序一致性 + 最终收敛

KVCache Manager 不追求分布式事务的强一致性，而是采用**以 session 为边界的顺序一致性**加上**以子系统为单位的最终收敛**。

**顺序一致性的保证边界**：
对于同一个 session 内部的操作序列，KVCache Manager 保证它们的执行顺序被所有参与的子系统按相同顺序观测到。例如：
- `Storage.save_layer(L0)` 必须在 `Storage.save_layer(L1)` 之前发起（如果引擎这样请求）；
- `Metadata.invalidate_local(old_block)` 必须在 `Metadata.register_remote(new_block)` 之后执行（如果 Storage 执行了 L1→L4 迁移）。

**最终收敛的保证边界**：
不同子系统之间对同一数据的状态视图允许短暂分歧，但分歧必须在有限时间内消解：
- Metadata 索引与 Storage 实际状态的分歧窗口 ≤ 50ms（由异步通知和周期性对账保证）；
- Connector 本地缓存与 Metadata 索引的分歧窗口 ≤ 100ms（由 KVCache Manager 主动推送的缓存失效事件保证）。

**为什么这个一致性级别足够**：
因为 KV Cache 是**可重算的中间结果**（derived data），不是用户提交的持久化状态。即使某次查询因为索引滞后而 miss，最坏结果也只是重新计算一次，不会导致输出错误。这个语义允许我们将一致性协议简化到 "保证不脏读、允许短暂 miss" 的级别。

---

## 4. 方案对比与推导过程

### 4.1 核心约束条件

在设计 KVCache Manager 时，以下约束是不可妥协的：

**约束 A：不重复实现子系统逻辑**
- Metadata、Storage、Connector、Transport 已经各自拥有专业的子系统设计和实现。KVCache Manager 若试图内嵌前缀树、数据搬运或网络协议，将造成严重的职责重叠和代码重复。

**约束 B：跨子系统请求必须可编排**
- 一次 KV Cache 的加载涉及 "查 Metadata → 请求 Storage 分配/加载 → 等待 Transport 就绪 → 通知 Connector 可用" 的复杂序列，必须有一个统一的协调者来推进状态机、处理超时和异常。

**约束 C：单点故障必须可控**
- 如果 KVCache Manager 本身就是一个单点，那么它的故障会导致整个 offloading 系统瘫痪。因此它必须是无状态的（或状态可快速重建的），并且存在清晰的降级路径。

**约束 D：延迟敏感**
- KVCache Manager 位于 TTFT 关键路径上，其自身的协调开销必须被压缩到 100μs 以内。

### 4.2 候选方案对比

#### 方案 X：纯去中心化（无 KVCache Manager）

- **原理**：Connector 直接与 Metadata、Storage、Transport 交互，各子系统通过事件总线互相通知。
- **在约束下的适配度**：
  - 约束 A：满足。无新增重复逻辑。
  - 约束 B：不满足。复杂的多步请求（如 promote）缺少统一的超时和回滚管理者，容易导致半完成状态堆积。
  - 约束 C：部分满足。消除了单点，但分布式调试和故障定位极其困难。
  - 约束 D：满足。少了中间一跳，理论上延迟最低。

#### 方案 Y：重量级协调服务（MoonCake Conductor 风格）

- **原理**：一个独立的集中式服务负责所有调度决策、全局状态维护和请求路由。
- **在约束下的适配度**：
  - 约束 A：不满足。Conductor 往往内嵌调度算法和状态机，容易与子系统职责重叠。
  - 约束 B：满足。统一编排能力强。
  - 约束 C：不满足。集中式服务本身就是单点和瓶颈，故障影响面大。
  - 约束 D：不满足。即使是 RDMA，额外一次网络往返也会引入 50-200μs 的延迟，超出 100μs 目标。

#### 方案 Z：嵌入式协调层（当前设计）

- **原理**：KVCache Manager 以库的形式嵌入在每个节点中（与 Connector 同进程或紧邻进程），负责本节点及跨节点请求的协调，无全局集中式实例。
- **在约束下的适配度**：
  - 约束 A：满足。严格的子系统客户端边界，不内嵌重复逻辑。
  - 约束 B：满足。通过 Orchestration Controller 和 Session Tracker 实现请求级编排。
  - 约束 C：满足。无单点，单节点故障只影响该节点上的活跃 session，其他节点的请求不受影响。
  - 约束 D：满足。嵌入式库的内部调用开销在 10-50μs 量级，满足目标。

### 4.3 推导结论

**选择：嵌入式协调层（方案 Z）**

推导逻辑：
1. 纯去中心化（方案 X）虽然延迟最低，但无法满足复杂请求的编排需求，在 promote/demote 等多步场景下会积累大量无主状态；
2. 重量级协调服务（方案 Y）虽然编排能力强，但引入了不可接受的单点风险和延迟 overhead；
3. **嵌入式协调层（方案 Z）找到了平衡点**：它提供请求级编排能力，但避免成为一个全局集中式瓶颈；
4. 该设计与 ADR-001 的 "分层存储架构为基础、预留分离式扩展能力" 的决策相兼容——MVP 阶段 KVCache Manager 嵌入在节点内部，未来若演进为分离式架构，可以平滑升级为每个节点上的独立 sidecar 进程，无需改变接口契约。

**牺牲的代价**：
- 跨节点 session 的协调需要节点间 RPC（通过 Metadata 和 Transport 子系统间接完成），这引入了额外的网络开销和故障面；
- 嵌入式部署意味着 KVCache Manager 与 Connector/引擎共享进程地址空间，必须实现严格的错误隔离边界，防止控制面 bug 导致推理引擎崩溃。

---

## 5. 动态行为描述

### 5.1 系统启动初始化序列

KVCache Manager 的启动遵循 "先注册自身、再发现他人、最后暴露服务" 的三阶段顺序：

```
Phase 1 (0-20ms):   本地子系统探测
  └─► 依次探测本地 Connector、Metadata、Storage、Transport 的健康端口
      └─► 若任一子系统未就绪，进入 DEGRADED 模式（仅服务本地重算请求）

Phase 2 (20-100ms): 控制面拓扑同步
  └─► 通过 gossip 协议向集群广播自身存在
  └─► 从邻居节点拉取最新的 Topology Registry 快照
      └─► 若 gossip 收敛失败（3 次重试后），使用本地配置文件的静态拓扑作为 fallback

Phase 3 (100-150ms): 策略加载与就绪声明
  └─► 从 Policy Engine 加载当前策略参数
  └─► 向本地 Connector 发送 "KVCache Manager READY" 事件
      └─► 若 Policy Engine 不可用，使用上一次持久化的策略快照作为 fallback
```

**故障恢复分支**：
- **子系统探测失败**：若 Storage 或 Metadata 在 20ms 内未响应，KVCache Manager 标记该子系统为 DOWN，并向 Connector 返回 `fully_degraded` 信号，此时所有请求走 "本地重算、不缓存" 的降级路径；
- **gossip 收敛失败**：若集群规模 < 20 节点，静态拓扑 fallback 的可用性风险可控；若集群规模 > 50 节点，gossip 失败将触发告警，但服务仍可继续（只是新加入节点的发现会延迟）。

### 5.2 Cache Hit 场景下的跨子系统协调时序图

以下时序图展示一个请求从 Connector 发起，命中 L3（SSD），并通过跳层直达晋升到 L1 的完整协调过程：

```
Connector        KVCache Manager       Metadata Client     Storage Client
    │                  │                     │                   │
    │  session_start   │                     │                   │
    │─────────────────►│                     │                   │
    │                  │                     │                   │
    │                  │── query_metadata ──►│                   │
    │                  │                     │                   │
    │                  │◄─ SegmentMap(L3 hit)│                   │
    │                  │                     │                   │
    │                  │──── reserve_blocks ────────────────────►│
    │                  │                     │                   │
    │                  │◄─ reserve_ok (L1预留)│                   │
    │                  │                     │                   │
    │  plan_ready      │                     │                   │
    │◄─────────────────│                     │                   │
    │  (HIT@L3, L1预留)│                     │                   │
    │                  │                     │                   │
    │  load_layer("L0")│                     │                   │
    │─────────────────►│                     │                   │
    │                  │──── load(L3→临时buffer)────────────────►│
    │                  │                     │                   │
    │                  │◄─ data_ready(L3)    │                   │
    │                  │                     │                   │
    │◄─ return_data ───│                     │                   │
    │                  │                     │                   │
    │                  │  [Async promotion starts below]         │
    │                  │                     │                   │
    │                  │──── promote(L3→L1) ─────────────────────►│
    │                  │                     │                   │
    │                  │◄─ promote_done      │                   │
    │                  │                     │                   │
    │                  │── notify_metadata_migration ──────────────►
    │                  │  (indirect, via Metadata update path)   │
```

**正常路径说明**：
1. Connector 的 `session_start` 触发 KVCache Manager 创建 session 并查询 Metadata；
2. Metadata 返回 L3 hit，KVCache Manager 立即向 Storage 请求在 L1 预留空间（为后续 promote 做准备）；
3. KVCache Manager 将 L3 数据返回给 Connector 用于 TTFT 计算；
4. 异步 promote 在后台执行，完成后由 Storage 直接通知 Metadata 更新索引（KVCache Manager 不介入数据搬运，只负责发起协调信号）。

**异常路径（L3 校验失败）**：
- 若 Storage 在 `load` 时发现 L3 数据已被覆盖，返回 `MISS`；
- KVCache Manager 将 plan 从 `"L3 HIT + promote"` 降级为 `"MISS + 本地重算 + 保存到 L1"`；
- Connector 收到 `plan_ready(MISS)` 后启动引擎重算。

### 5.3 并发控制模型

#### 选型对比

在设计并发模型时，有三个候选方向被评估：

| 候选模型 | 优点 | 缺点 | 结论 |
|----------|------|------|------|
| **Thread-per-session** | 实现简单，每个 session 独占线程，天然隔离 | 高并发时线程数膨胀（1K+ session → 1K+ 线程），上下文切换开销大，内存占用高 | **排除**。与延迟敏感目标冲突，且 C 语言线程栈成本不利于嵌入部署。 |
| **Actor model** | 状态隔离清晰，适合分布式消息传递 | 需要引入 actor 框架（如 libactors 或自研调度器），增加外部依赖和认知负担，actor 间消息复制引入额外延迟 | **排除**。团队无成熟 actor 框架积累，MVP 阶段应减少非必要依赖。 |
| **Event-loop + thread-pool** | 热路径单线程无锁，非热路径并行处理下游 RPC，资源可控，延迟可预测 | 需要仔细的 session 状态机设计和无锁队列实现 | **选择**。与嵌入式 C 库定位最契合，也是 Redis、Nginx 等高性能中间件验证过的模型。 |

#### 最终模型

KVCache Manager 内部采用**事件驱动 + 分片锁**的并发模型：

```
┌─────────────────────────────────────────────┐
│         外部请求事件循环 (1 per node)         │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐     │
│  │Connector│─►│Session  │─►│Orchest. │     │
│  │ Events  │  │ Registry│  │Controller│    │
│  │ (无锁队列)│  │(分片锁) │  │(状态机锁) │   │
│  └─────────┘  └─────────┘  └─────────┘     │
│         热路径：单线程事件循环               │
└─────────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────┐
│           异步协调工作线程池 (N=CPU cores/2)   │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐     │
│  │Metadata │  │ Storage │  │Transport│     │
│  │ Client  │  │ Client  │  │ Client  │     │
│  │(RPC调用) │  │(RPC调用) │  │(RPC调用) │    │
│  └─────────┘  └─────────┘  └─────────┘     │
│         非热路径：并行处理下游子系统调用       │
└─────────────────────────────────────────────┘
```

**锁粒度与策略**：
- **外部事件循环**：单线程，无锁处理 Connector 事件，通过 MPSC 无锁队列接收子系统异步回调；
- **Session Registry**：按 `session_id` 取模分片（默认 256 个 bucket），每个 bucket 独立 mutex。冲突概率极低（< 1/256），因为同一 session 的事件天然有序；
- **Topology Registry**：读写锁（read-heavy）。心跳查询走读锁，节点变更走写锁；写锁持有时间 < 10μs；
- **Policy Engine 参数表**：RCU（Read-Copy-Update）机制，更新时创建新快照并原子替换指针，读取方零阻塞。

### 5.4 故障隔离与降级流程

#### 场景 A：Storage 子系统超时无响应

```
[Storage Client 连续 2 次 RPC 超时]
        │
        ▼
[Orchestration Controller 标记 Storage 为 DEGRADED]
        │
        ▼
[通知 Topology Registry: Storage 不可用]
        │
        ▼
[当前 session 降级为 "MISS + 本地重算"]
  ├─► 返回 Connector: "offloading 不可用，请引擎重算"
  ├─► 已分配但未确认的 block 配额进入异步回收队列
  └─► 新 session 的策略切换为 "不查询 Storage，只查询 Metadata"
        │
        ▼
[后台线程每 500ms 重试探测 Storage]
  ├─► 恢复：标记 HEALTHY，策略回退到正常模式
  └─► 持续失败：触发全局告警，建议 ops 介入
```

**降级阈值推导**：
- **"连续 2 次 RPC 超时"**：单次 Storage Client RPC 超时阈值为 5ms（由 Subsystem Gateway Layer 配置）。选择 2 次而非 1 次，是为了过滤偶发网络抖动（目标误报率 < 1%）；选择不超过 3 次，是因为 3×5ms=15ms 已接近降级 SLA 的 20ms 上限，过长的确认会扩大故障影响窗口。
- **"每 500ms 重试探测"**：该间隔基于 Storage 子系统典型恢复时间（如 SSD 控制器短暂 busy 约 200-800ms）和探测开销的平衡。500ms 足够快以便在秒级内检测到恢复，又不会因高频探测给已受损的 Storage 进程增加额外负载。

**降级 SLA**：从 Storage 首次超时到完成降级标记传播的总时间 < 20ms（2×5ms 超时 + 10ms 状态机推进和拓扑广播）。此期间受影响的 session 会体验到一次额外 miss，但不影响引擎的正确性。

#### 场景 B：Metadata 索引与 Storage 实际状态不一致

```
[Storage 报告 load 命中，但 Metadata hint 指向错误位置]
        │
        ▼
[Orchestration Controller 检测到 segment 描述与实际数据不匹配]
        │
        ▼
[将本次 session 降级为 "保守模式"]
  ├─► 忽略 Metadata 的后续 hint，直接以 Storage 返回为准
  ├─► 向 Metadata Client 发送 inconsistencies_detected 信号
  └─► 记录 slow log 供后台对账程序消费
        │
        ▼
[Background Reconciler 扫描不一致日志]
  ├─► 向 Metadata 发起强制刷新请求
  └─► 向 Storage 发起状态同步请求
```

---

## 6. 与周边子系统的边界和交互

| 周边子系统 | 边界方向 | KVCache Manager 的职责 | 对方的职责 | 交互内容 | 一致性要求 |
|-----------|---------|----------------------|-----------|---------|-----------|
| **Connector** | 双向 | 接收 session 协调请求，返回计划或被降级通知 | 发起请求、执行引擎计算、反馈完成状态 | session 请求、Coordination Plan、异步完成事件 | 强一致（session 边界内） |
| **Metadata** | 客户端->服务端 | 查询 token 序列的 SegmentMap；通知索引刷新 | 维护前缀树和 chunk-hash；响应查询 | token 序列、SegmentMap、inconsistency 报告 | 最终一致（50ms 窗口） |
| **Storage** | 客户端->服务端 | 请求 block 分配/加载/保存/晋升；获取容量和热度信号 | 执行物理数据操作；自治 tiering 决策 | block 描述符、预留请求、迁移完成通知 | 强一致（单操作） |
| **Transport** | 客户端->服务端 | 获取跨节点路由信息（逻辑节点 ID + 延迟估计） | 维护网络连接和拓扑；提供路由查询 | 逻辑节点 ID、协议推荐、距离估计 | 弱一致（允许过期） |

**边界抽象层次说明**：
- **KVCache Manager ↔ Connector**：这是唯一的热路径双向交互。Connector 不直接调用 Metadata 或 Storage，所有跨子系统操作必须经过 KVCache Manager 的编排。
- **KVCache Manager ↔ Metadata**：纯查询 + 通知模式。KVCache Manager 不干预 Metadata 内部的 Radix Tree 结构或一致性哈希环拓扑。
- **KVCache Manager ↔ Storage**：操作请求模式。KVCache Manager 不感知 block 内部的物理布局、压缩方式或介质特性，只操作 "分配/加载/保存/晋升" 的语义。
- **KVCache Manager ↔ Transport**：纯咨询模式。Transport 返回的信息只是 Storage Client 在构造远程请求时的附加参数，KVCache Manager 不操作任何网络套接字或 RDMA 队列对。

### 6.1 防火墙规则：KVCache Manager 不得越界

为了防止协调层与子系统之间的语义泄漏，双方必须遵守以下防火墙规则：

**KVCache Manager 不得要求子系统提供**：
- 引擎特定的 Python 对象结构（如 vLLM 的 BlockTable）；
- Metadata 内部节点的内存布局（如 Radix Tree 的 node 指针结构）；
- Storage 内部的物理地址（如 SSD 的扇区号、HBM 的 GPU 显存虚拟地址）；
- Transport 的连接状态变化或重传计数。

**子系统不得要求 KVCache Manager 理解**：
- 推理引擎的调度算法或 batching 策略；
- 前缀树的压缩算法或 chunk 切分细节；
- SSD 的 wear-leveling 或 GC 策略；
- RDMA 的 QP/CQ 编号或内存注册生命周期。

---

## 7. 设计 Rationale

### 7.1 "为什么不是纯去中心化架构？"

纯去中心化架构的最大吸引力是消除了单点和中间延迟，但在 KV Cache offloading 场景中，它有三个致命缺陷：

1. **无主状态机**：当一个请求需要 "查 Metadata → 预留 Storage → 等待 Transport → 加载完成" 四步时，如果缺少一个统一的所有者，任何一步的失败都会导致半完成状态默默堆积。没有协调者来清理 "已预留但未加载" 的悬空 block；
2. **级联超时失控**：Connector 直接调用 Metadata（10μs）、再调用 Storage（10μs）、再等待 Transport（可能 1ms），每一步的超时和重试策略由各自子系统定义，叠加后总延迟的分布难以预测和控制；
3. **全局策略无法执行**：如果需要在集群层面统一关闭 PrefetchEngine 或切换为保守模式，去中心化架构只能通过广播事件实现，收敛时间不可控，节点间策略版本不一致的风险高。

KVCache Manager 的嵌入式设计保留了去中心化的 "无单点" 优点（每个节点独立实例），同时通过 Session Tracker 和 Orchestration Controller 解决了无主状态机和策略统一的问题。

### 7.2 "为什么不是重量级集中式协调服务？"

集中式协调服务（如 MoonCake Conductor）适合做 "全局调度决策"（如选择哪个 prefill 节点服务哪个请求），但不适合做 "每个请求的 KV Cache 编排"。原因如下：

1. **延迟 overhead 不可接受**：即使是 RDMA，一次往返也需要 50-200μs。而 KVCache Manager 的目标是 ≤100μs 的协调延迟，这意味着它必须与引擎同节点部署，不能跨越网络；
2. **故障放大**：集中式服务的故障会导致整个集群的 offloading 功能失效，与 ADR-001 中 "优先可用性" 的 trade-off 原则冲突；
3. **与引擎绑定过深**：集中式服务很难理解每个引擎特定的 session 语义和层计算顺序，最终仍然需要在每个节点上部署一个代理进程——这本质上就是 KVCache Manager 的嵌入式形态。

### 7.3 "这个选择的最优场景和最差场景是什么？"

**最优场景**：
- 单节点内子系统健康稳定，Metadata 查询命中率 > 80%，Storage 容量充裕；
- 工作负载具有明显的前缀复用模式，Coordination Plan 中 HIT 段占主导地位；
- 集群规模 10-50 节点，gossip 拓扑同步开销可忽略。

**最差场景**：
- 多个子系统频繁故障或超时（如 Storage SSD 不可读、Metadata gossip 分裂），导致 KVCache Manager 持续处于降级路径；
- 工作负载完全随机，几乎所有请求都是 MISS，KVCache Manager 的协调开销成为纯负担；
- 节点频繁加入/离开，Topology Registry 持续 stale，跨节点路由决策大量失败。

**量化失效边界**：

| 失效条件 | 触发阈值 | 止损动作 | 对齐 ADR |
|----------|----------|----------|----------|
| Metadata 查询失败率 > 5% | 连续 1 分钟 | 切换为 "跳过 Metadata，直接本地重算" 的降级模式 | ADR-002 |
| Storage 响应超时率 > 10% | 连续 1 分钟 | 标记 Storage DEGRADED，所有新请求走本地重算 | ADR-003 |
| 跨子系统协调延迟 P99 > 500μs | 连续 5 分钟 | 触发保守模式（关闭预取、关闭跳层直达、关闭异步晋升） | ADR-003 |
| gossip 拓扑分歧节点 > 10% | 单次检测 | 使用静态拓扑 fallback，暂停动态节点发现 | ADR-001 |

### 7.4 "如果未来需求变更，这个设计的脆弱点在哪里？"

**脆弱点 1：session 状态机的复杂度随功能增长而膨胀**
- 当前 session 状态机包含 7 个主要状态（INIT → PLANNED → LOADING → COMPUTING → SAVING → COMMITTED/ABORTED）。如果未来引入更复杂的功能（如 speculative decode 的多分支 session、跨引擎共享 session），状态机可能急剧膨胀，维护和验证成本上升。
- 缓解方向：将 session 拆分为 "读取子状态机" 和 "写入子状态机"，通过组合而非扁平化枚举来管理状态空间。

**脆弱点 2：Policy Engine 的全局一致性难以保证**
- Policy Engine 在每个节点上独立运行，通过 gossip 传播策略变更。在策略版本不一致的窗口期内，不同节点可能对 "同一 chunk 是否热" 做出不同判断，导致存储层出现冗余迁移或竞争。
- 缓解方向：为策略参数引入单调递增的版本号，Storage 拒绝执行版本号低于当前已应用版本号的策略指令。

**脆弱点 3：与 Connector 的进程内耦合**
- 当前设计假设 KVCache Manager 与 Connector 位于同一进程或紧邻进程。如果未来需要演进为完全分离的 sidecar 架构（如为了支持不同语言编写的引擎），嵌入式设计的进程内优化将变成束缚。
- 缓解方向：Subsystem Gateway Layer 的接口契约从设计之初就预留了 RPC 封装的可能性，Orchestration Controller 不假设任何调用方是本地函数调用。

---

## 8. 风险点和缓解策略

### 高风险：跨子系统状态不一致导致偶发 miss 或延迟抖动（高影响 / 中可能性）

**表现形态**：
- Metadata 索引已更新但 Connector 本地缓存未失效，导致引擎读取到错误的 block 引用；
- Storage 已完成 promote 但 Metadata 尚未收到通知，导致后续请求仍然从 L3 加载而非 L1 命中。

**缓解策略**：
1. **50ms 最终一致窗口监控**：建立 "索引-存储-连接器" 三角对账机制，每 10 秒抽样比对一次，差异率 > 0.01% 触发告警；
2. **保守回退校验**：Connector 在加载前向 Storage 发送一次轻量级的 `verify_existence` 校验（不读取数据，只检查句柄有效性），将脏读风险从 "可能错误加载" 降级为 "校验失败后的本地重算"；
3. **主动失效推送**：Storage 的 promote/demote 完成后，除异步通知 Metadata 外，同时通过 KVCache Manager 向本地 Connector 推送缓存失效事件，缩短 Connector 的滞后时间。

### 高风险：协调层自身性能衰减拖累 TTFT（高影响 / 中可能性）

**表现形态**：
- session 数量激增（如大 batch size 或高并发）导致外部事件循环处理延迟增加；
- Subsystem Gateway 的 RPC 线程池饱和，排队时间不可控。

**缓解策略**：
1. **事件循环时长监控**：每个事件循环周期超过 1ms 时触发告警，超过 2ms 时自动丢弃非关键后台任务（如统计上报）；
2. **Subsystem Gateway 背压机制**：当 Storage Client 队列深度超过阈值（如 1000）时，新 session 直接返回 `server_busy` 信号，由 Connector 降级为本地重算；
3. **session 合并优化**：对于同一引擎 batch 内的多个请求，Orchestration Controller 支持批量生成 Coordination Plan，减少重复查询 Metadata 的次数。

### 中风险：gossip 拓扑分裂导致跨节点路由异常（中影响 / 低可能性）

**缓解策略**：
- gossip 协议采用反熵（anti-entropy）机制，每 1 秒执行一次增量同步，每 30 秒执行一次全量校验；
- 当本地 Topology Registry 与收到的 gossip 消息版本号差异 > 3 时，暂停使用该拓扑信息进行跨节点路由决策，回退到静态配置文件中的 seed 节点列表。

### 中风险：Policy Engine 策略版本冲突（中影响 / 中可能性）

**缓解策略**：
- 所有策略参数附带 64 位单调递增版本号；
- Storage 执行策略指令前校验版本号，拒绝旧版本指令；
- 策略变更通过 "两阶段提交" 在 gossip 中传播：先广播新版本参数（只读），再广播激活信号（生效），确保大多数节点在同一时间窗口内切换。

---

## 9. 待验证假设与下一步行动

| 假设 | 验证方法 | 截止日期 | 失败回退策略 |
|------|---------|---------|-------------|
| 协调延迟 < 100μs 可达成 | 原型测试：单节点内 Metadata→Storage→Connector 往返 | 2026-04-25 | 若实测 > 200μs，将 KVCache Manager 部分功能下沉到 Connector 内部，减少一跳 |
| Session Tracker 内存开销可接受 | 模拟 10K 并发 session 的内存占用 | 2026-04-25 | 若内存 > 500MB，启用 session 压缩和更激进的异步回收 |
| gossip 拓扑在 50 节点下 5 秒内收敛 | 多进程仿真测试 | 2026-05-02 | 回退为静态拓扑配置中心模式 |
| 降级路径（本地重算）不影响引擎正确性 | 集成测试：随机注入子系统故障 | 2026-05-02 | 若引擎出现不一致输出，强化 verify_existence 校验逻辑 |

---

## 修正摘要

本次修正重点回应了 architect-reviewer 的 5 项质疑。第一，将 Policy Engine 的决策拆分为具有强制约束力的全局参数和自治建议性的局部策略，并补充了冲突仲裁规则。第二，为 Session 状态机引入 `storage_version` 机制，允许后续 layer 加载时捕获异步 promote 的完成状态而不阻塞首层 TTFT。第三，将 100μs 协调延迟目标拆解为 KVCache Manager 内部可控的 45-80μs 与引擎侧不可控开销，明确责任边界。第四，将 Metadata 路由完全委托给 Metadata 子系统，消除 Topology Registry 的职责重叠风险。第五，补充了并发模型（thread-per-session / actor / event-loop）的选型对比和降级阈值的量化推导依据。

*本文档依据 `docs/adr.md` 中的 ADR-001、ADR-003、ADR-006 产出，经系统分析后由 tech-leader 定稿。*
