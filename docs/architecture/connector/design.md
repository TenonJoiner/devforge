# Connector 子系统架构设计

**文档版本**: v1.2-reviewed  
**日期**: 2026-04-12  
**Owner**: tech-leader  
**关联 ADR**: ADR-006（Library模式为主，vLLM Plugin为辅）  
**置信度**: 高（87%）

---

## 1. 设计目标

Connector 子系统是推理引擎与 KVCache Offloading 内部子系统之间的**唯一网关**。它的核心使命是：以一种对引擎透明、对内部子系统友好的方式，将 KV Cache 的生命周期管理从推理流程中解耦出来。

如果没有 Connector，推理引擎将不得不直接面对以下复杂度：
- **版本碎片化**：vLLM 在 v0.4.x 到 v0.6.x 之间的 BlockTable 管理、KV Cache 分配策略持续演进，任何直接耦合都会导致适配成本随版本线性增长
- **多后端协调**：推理引擎需要同时与元数据索引子系统（查询 token 命中）、存储子系统（分配/加载/回写）、传输子系统（PD 分离场景路由）交互，这会严重污染引擎的核心调度逻辑
- **运行时模式切换**：当 Library 需要升级或发生故障时，没有统一抽象层来将流量无缝切换至 Sidecar 模式

Connector 子系统的设计目标可以概括为四点：

1. **引擎无关抽象**：通过 `KVStoreInterface` 屏蔽引擎特定的内存管理 API，使得除适配器外的所有代码都不感知 vLLM 的存在
2. **双模式运行时切换**：Library 模式作为默认低延迟路径，Sidecar 模式作为热升级和故障兜底路径，两种模式在运行时可秒级切换
3. **流水线级延迟隐藏**：利用 layer-wise 异步加载/保存机制，将 KV Cache 的 I/O 开销与 Attention 计算尽可能地重叠
4. **版本兼容自治**：建立版本适配器工厂，单个 minor 版本的适配工作量控制在约 1 人周以内，并通过 CI 矩阵确保回归可控

**关于"1人周"适配成本的量化拆解**：
该估算基于以下具体工作项累加（总计约 5.5 个工作日，即 1 人周）：
- API 差异分析与影响评估：0.5 天
- Adapter 代码修改与本地验证：1 天
- 单元测试补充与 mock 回归：1 天
- 集成测试回归（含 staging 环境 smoke test）：1.5 天
- 文档更新与 release note：0.5 天
- 缓冲余量（处理不可预见差异）：1 天
**超支熔断机制**：前两个版本的实际耗时将作为修正预算基线的输入；若单个 minor 版本实际耗费 > 2 人周，或连续 2 个版本均 > 1 人周，触发"切换为更稳定集成模式"的强制评审。

---

## 2. 总体架构与模块设计

### 2.1 模块静态结构

Connector 子系统内部划分为七个核心模块，各模块的职责和依赖关系如下：

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        Connector 子系统内部架构                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌───────────────┐     ┌───────────────┐     ┌───────────────┐            │
│  │ Engine Adapter│────►│ KVStoreInterface│───►│ Storage Client │            │
│  │   层 (3个)     │     │   抽象层         │     │   存储客户端     │            │
│  └───────┬───────┘     └───────┬───────┘     └───────┬───────┘            │
│          │                     │                     │                      │
│          │              ┌──────┴──────┐              │                      │
│          │              │             │              │                      │
│          │              ▼             ▼              ▼                      │
│          │        ┌───────────┐ ┌───────────┐ ┌───────────┐               │
│          │        │ Mode     │ │ Pipeline  │ │ Metadata  │               │
│          └───────►│ Switch   │ │ Engine    │ │ Client    │               │
│                   │ 模式切换器 │ │ 流水线引擎 │ │ 元数据客户端  │               │
│                   └─────┬─────┘ └─────┬─────┘ └─────┬─────┘               │
│                         │             │             │                      │
│                         └─────────────┴─────────────┘                      │
│                                       │                                    │
│                                       ▼                                    │
│                                ┌───────────┐                               │
│                                │ Transport │                               │
│                                │ Router    │                               │
│                                │ 传输路由器 │                               │
│                                └───────────┘                               │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 2.2 模块职责定义

#### Module 1: Engine Adapter 层

**职责一句话定义**：负责将推理引擎的调用约定转换为本子系统内部的 `KVStoreInterface` 调用。

- **输入**：来自 vLLM Scheduler 的 token 序列、来自 vLLM Worker 的 layer-wise KV 加载/保存请求
- **输出**：标准化的 block allocation 请求、block table 快照、异步 I/O 句柄
- **协作方式**：
  - 向上对接 vLLM（当前仅 vLLM，未来可扩展），实现 vLLM KV Connector V1 API 的双角色接口
  - 向下对接 `KVStoreInterface`，将所有引擎特定的数据结构（如 vLLM 的 `BlockTable`）在 Adapter 内部完成转换，严禁向上层泄漏

**版本管理策略**：每个支持的 vLLM minor 版本对应一个独立的 Adapter 实现（如 `VLLMv04xAdapter`、`VLLMv05xAdapter`、`VLLMv06xAdapter`）。运行时通过检测 vLLM 版本字符串，从工厂函数中获取匹配实例。若运行时发现未适配版本，触发 fallback 至 Sidecar 模式。

#### Module 2: KVStoreInterface 抽象层

**职责一句话定义**：定义引擎无关的 KV Cache 存储操作契约，是连接引擎适配与后端能力的唯一桥梁。

- **输入**：来自 Engine Adapter 的 block 生命周期操作请求、来自 Pipeline Engine 的异步传输请求
- **输出**：抽象的 block handle、操作状态码、引擎无关的 block table 视图
- **协作方式**：
  - 向上屏蔽所有引擎差异，向下统一调用 Storage Client、Metadata Client、Mode Switch
  - 所有内部子系统（Scheduler、Storage、Metadata）只认识 `KVStoreInterface`，不认识 vLLM

**设计原则**：`KVStoreInterface` 不暴露任何具体内存布局（如是否分页、页大小、数据类型），只描述逻辑语义（"分配一个承载 N 个 token 的 block"、"将某 block 的加载请求加入流水线"）。这确保了即使 vLLM 的内存布局在未来大改，也只需要修改 Adapter 而非重构全系统。

#### Module 3: Mode Switch（模式切换器）

**职责一句话定义**：管理 Library 模式与 Sidecar 模式的运行态切换，保证切换过程中已确认提交的请求不丢失，对未 finalize 的 inflight 请求在 draining 超时后执行丢弃并由引擎/Sidecar 重试。

- **输入**：配置中心的切换信号（信号类）、Library 初始化失败事件（自动类）、未适配版本检测事件（自动类）、连续调用失败告警（自动类）
- **输出**：模式切换状态通知、inflight 请求 draining 完成信号
- **协作方式**：
  - 被 `KVStoreInterface` 在初始化阶段调用，决定当前工作模式
  - 在切换发生时，向 Pipeline Engine 发送"暂停接收新请求、排空 inflight"的指令
  - 切换完成后，Engine Adapter 的调用被路由至新的模式实现（Library 本地函数调用 / Sidecar IPC 句柄）

**双模式下的 `KVStoreInterface` 语义一致性**：无论处于 Library 还是 Sidecar 模式，`KVStoreInterface` 的调用语义和返回值格式完全一致。Mode Switch 只在实现层做路由选择，不改变接口契约。这是"运行时切换"能够成立的关键前提。

#### Module 4: Pipeline Engine（流水线引擎）

**职责一句话定义**：将 KV Cache 的加载和保存操作组织为 layer-wise 异步流水线，最大化计算-I/O 重叠；同时作为**batch 聚合的单一负责人**，将多个 request/layer 级别的 I/O 请求聚合成 batch 后下发给 Storage Client。

- **输入**：来自 `KVStoreInterface` 的 `start_load`、`save_layer`、`wait_for_layer` 请求
- **输出**：异步完成通知、层就绪信号、错误回滚状态
- **协作方式**：
  - 与 Engine Adapter 的 `wait_for_layer_load` 同步点对接，确保在 Attention 层计算前所需 KV 已就绪
  - 与 Storage Client 对接，以 `batch_allocate` / `batch_load` / `batch_store` 为单位下发聚合后的请求
  - 与 Metadata Client 对接，在加载前获取命中分段结果，在保存后更新索引元数据

**流水线结构**：Pipeline Engine 内部维护每个请求的数据流状态机，包括 `PREFETCH -> LAYER_N_LOAD -> LAYER_N_COMPUTE -> LAYER_N_SAVE -> COMMIT` 几个阶段。阶段之间的推进由事件驱动，不阻塞调用方线程。

**Batching 职责边界（明确单一负责人）**：
- **Pipeline Engine 拥有 batching 策略的唯一决策权**：它根据请求状态机的全局视图，决定将 N 个层级别的 save/load 请求聚合成一个 batch；
- **Storage Client 的职责是透传**：它只负责将 Pipeline Engine 已经聚合好的 batch 请求转发给 Storage 子系统，不做二次聚合；
- 这样可避免双重聚合或聚合策略冲突。若 Storage 子系统的 API 不支持 batch 语义，此问题标记为**阻塞性依赖**，需在 Storage 接口设计中优先解决。

#### Module 5: Storage Client（存储客户端）

**职责一句话定义**：向 Storage 子系统发起 block 级别的 allocate/load/store 请求，并处理本地缓冲与远端存储的路由。

- **输入**：来自 Pipeline Engine 的**已聚合批量** I/O 请求（batch 分配、加载、回写）
- **输出**：block 在存储子系统内的位置句柄、I/O 完成状态
- **协作方式**：
  - 通过专用控制通道与 Storage 子系统的 Allocator 模块通信
  - 对热数据优先尝试本地缓冲命中，未命中时再走远端加载
  - 不负责 batching、数据格式转换或压缩，这些分别属于 Pipeline Engine 和 Storage 子系统的职责

#### Module 6: Metadata Client（元数据客户端）

**职责一句话定义**：向 Metadata 子系统提交 token 序列，获取命中分段结果；在 KV 写入完成后通知 Metadata 更新索引。

- **输入**：来自 Engine Adapter 的 token 序列、来自 Pipeline Engine 的写完成通知
- **输出**：命中分段列表（match segments，即哪些 token 可直接复用缓存）、新分配 block 的元数据标签
- **协作方式**：
  - 在请求到达时（Scheduler 路径）向 Metadata 发起前缀匹配查询
  - 查询结果以"分段列表"形式返回，每个分段标注：起始 token 偏移、长度、所在的存储层级
  - Pipeline Engine 根据分段结果决定加载策略（哪些层需要加载、哪些层可直接跳过）

#### Module 7: Transport Router（传输路由器）

**职责一句话定义**：在 PD 分离场景下，为 Storage Client 的远端请求提供目标节点路由信息（逻辑节点 ID + 协议推荐），不直接参与数据搬运。

- **输入**：来自 Pipeline Engine 的远端加载/回写请求（携带目标 block 的存储层级信息）
- **输出**：目标逻辑节点 ID、推荐的传输协议（RDMA / TCP）、预估的链路延迟
- **协作方式**：
  - 不直接操作网络套接字或 RDMA QP，这些信息由 Transport 子系统管理
  - 仅作为"路由顾问"，将逻辑节点 ID 和协议推荐填充到 Storage Client 的请求中
  - 若 Transport 子系统提供了拓扑感知接口，Transport Router 会缓存节点间距离矩阵以加速路由决策

### 2.3 模块间调用关系

为避免模块职责边界暧昧，以下表格明确各跨模块交互的调用方向：

| 调用者 | 被调用者 | API / 交互名称 | 触发场景 |
|--------|----------|----------------|----------|
| Engine Adapter | KVStoreInterface | `initialize`、`allocate_block`、`start_load_pipeline` 等 | Engine 将引擎调用转换为子系统内部调用 |
| KVStoreInterface | Mode Switch | `get_current_mode`、`request_mode_switch` | 初始化及运行中发生模式切换时 |
| KVStoreInterface | Pipeline Engine | `submit_load_request`、`submit_save_request`、`wait_layer_ready` | 需要启动或推进 layer-wise 流水线时 |
| Pipeline Engine | Storage Client | `batch_allocate`、`batch_load`、`batch_store` | Pipeline 将 I/O 请求聚合后批量下发时 |
| Pipeline Engine | Metadata Client | `get_match_segments_for_request` | Pipeline 启动加载前获取命中结果时 |
| Pipeline Engine | Transport Router | `resolve_remote_route` | 请求需要访问远端节点时 |
| Engine Adapter | Metadata Client | `query_metadata_sync` | Scheduler 路径中同步查询 token 前缀命中 |
| Engine Adapter | KVStoreInterface | `notify_write_complete` | Worker 路径中请求完成后异步通知 Metadata |

---

## 3. 核心概念与抽象

### 3.1 KVStoreInterface 的职责分层

`KVStoreInterface` 是 Connector 子系统与 Engine 之间的唯一契约层。为便于理解其设计意图，以下用文字描述其承担的四大类职责（非代码接口定义，正式接口定义参见 `docs/interfaces/vllm-compatibility.md`）：

1. **Block 生命周期管理**
   - 按需分配、释放、拷贝承载特定数量 token 的抽象 block
   - 所有 block 对 Engine 完全不透明，Engine 只能传递句柄，不能解引用或假设其内存布局

2. **流水线异步控制**
   - 启动基于 match segments 的异步加载流水线，获得流水线凭证（ticket）
   - 按 Attention 层等待就绪信号，提交每层计算完成后的异步保存请求
   - 在请求结束时最终化流水线，确保所有异步操作收敛

3. **元数据查询与通知**
   - 同步查询 token 序列的前缀命中情况（发生于调度决策路径）
   - 异步通知 Metadata 子系统更新索引（发生于 KV 写入完成后）

4. **模式切换控制**
   - 查询当前工作模式（Library / Sidecar）
   - 请求模式切换（仅在配置变更或故障恢复场景下由运维信号触发）

### 3.2 关键设计约束

- **Block 句柄不透明性**：`BlockHandle` 对引擎是完全不透明的。引擎 Adapter 只能传递它，不能解引用、不能做大小运算、不能假设它的布局。这强制了引擎与内部的解耦。
- **流水线调用边界**：加载流水线的启动发生在请求开始推理之前（Scheduler 决策后），而层就绪等待和层保存提交是在每个 Attention 层的计算边界被调用的。这是 layer-wise 流水线的语义基础。
- **元数据查询同步性**：`query_metadata` 不走 Pipeline Engine，而是同步返回（或极短延迟返回），因为它发生在调度决策路径上，不能引入异步不确定性。

---

## 4. 方案对比与推导过程

### 4.1 候选方案回顾

ADR-006 在决策阶段研究了四种集成形态：

| 方案 | 形态 | 代表实现 |
|------|------|----------|
| 方案1 | 引擎内嵌 Plugin | vLLM KV Connector V1 API |
| 方案2 | 独立进程 + IPC | LMCache 架构 |
| 方案3 | Sidecar + 标准协议 | 独立部署，gRPC/HTTP 通信 |
| 方案4 | Library 模式（.so） | NVIDIA NIXL, Mooncake Transfer Engine |

本节的任务是说明：为什么 Connector 子系统最终选择"方案4为主、方案1为辅、方案2/3作为兜底"的组合策略，而非单一方案。

### 4.2 场景约束条件的明确定义

在评估任何方案之前，必须先明确本场景的硬性约束：

**约束 A：TTFT 敏感**
- KV Cache 加载发生在请求首 token 生成之前，任何额外的毫秒级开销都会直接加到 TTFT 上
- 目标：cache hit 场景下，集成层引入的附加延迟 < 1ms（占整体 TTFT 的 < 5%）

**约束 B：版本波动大**
- vLLM 的 minor 版本发布周期约为 4-6 周，Connector API 在 v0.4 到 v0.6 期间仍在收敛
- 目标：单个 minor 版本的适配成本 <= 1 人周（拆解见第1节）

**约束 C：热升级需求**
- 生产环境不允许因 Connector 升级而重启推理引擎进程
- 目标：升级过程对在线流量的中断时间 < 100ms

**约束 D：引擎锁定与扩展性权衡**
- MVP 阶段必须深度支持 vLLM，但中长期需预留 SGLang / TensorRT-LLM 的扩展空间
- 目标：90% 的代码与引擎无关，只有 Adapter 层需要重写

### 4.3 单一方案的约束适配度评估

#### 如果纯用方案1（Plugin）

Plugin 形态的延迟最低（~1us 函数调用），天然满足约束 A。但它在约束 B、C、D 上的表现堪忧：
- **约束 B**：Plugin 直接与 vLLM 内部数据结构（如 Python 层的 `BlockTable`、worker 进程状态）耦合。vLLM 的 Python API 变更频繁（如 v0.5 到 v0.6 中 `KVCacheManager` 的初始化参数已发生变化），这意味着每个 minor 版本都可能需要修改 Plugin 源码并重新发布 Python wheel，适配成本很容易超过 1 人周
- **约束 C**：Plugin 以 Python 模块形式加载到 vLLM 进程内部，升级时必须重启 vLLM worker 进程，无法满足热升级需求
- **约束 D**：Plugin 的接口是 vLLM 定义的，其他引擎（如 SGLang）没有等价接口，跨引擎复用率为零

因此，纯 Plugin 不可作为唯一方案。但它可以作为一个**优化路径**：在 vLLM 深度集成的场景下，Engine Adapter 可以以 Plugin 形式实现，从而将函数调用开销降到最低。这就是为什么我们选择"方案1为辅"。

#### 如果纯用方案2（独立进程）或方案3（Sidecar）

独立进程和 Sidecar 在约束 B、C、D 上表现优秀：
- **约束 B**：只要与引擎的 IPC 接口稳定，内部实现变更不影响引擎
- **约束 C**：独立进程可以滚动升级，引擎不感知
- **约束 D**：新的引擎只需要实现同一个 IPC 协议即可接入

但它们在约束 A 上存在根本缺陷：
- 独立进程的 IPC 开销（共享内存 / Unix Domain Socket）约为 10-100us，如果涉及数据序列化则更高
- Sidecar 的标准协议（gRPC / HTTP）开销约为 1-10ms，这在 cache hit 场景下是完全不可接受的——cache hit 的核心价值就是将 TTFT 从数百毫秒降到数十毫秒，而 Sidecar 可能吃掉一半的优化收益

因此，纯独立进程 / Sidecar 不能作为默认运行态。但它们非常适合作为**兜底和升级态**：当 Library 需要升级或检测到未适配版本时，临时切换至 Sidecar 模式，牺牲一部分性能换取可用性。

#### 为什么方案4（Library）是主路径

Library 模式在约束 A、B、D 上找到了最佳平衡点：
- **约束 A**：函数调用开销 ~1us，与 Plugin 同级，满足 TTFT 敏感需求
- **约束 B**：Library 以 C/C++ 接口封装 vLLM 的内部机制，将 vLLM Python API 的不稳定性限制在 Adapter 层。Adapter 层虽小，但由于接口语义清晰（allocate / get_block_table / transfer），变更范围可控
- **约束 D**：Library 的核心代码（Pipeline Engine、Storage Client、Metadata Client）完全引擎无关，只需要为不同引擎编写不同的 Adapter 和工厂函数

**关于热升级（约束 C）的诚实评估**：
- Library 模式与宿主进程绑定，"dlopen 动态卸载并重载 so"在 Linux 实践中存在未解决的技术风险：dlclose 不保证释放所有资源、旧 so 的全局状态残留、符号解析的不可预期行为。ADR-006 Tech Leader 修正回应中已将 Library 热升级可行性从"可以实现"修正为"理论上可行，但存在未经验证的实现风险"。
- 因此，**约束 C 的实际满足路径不是 Library 原地热重载，而是通过 Mode Switch 在升级窗口期间将流量无损切至 Sidecar**。这是经过修正后的真实热升级方案，而非理想中的 dlopen 重载。
- 也就是说：Library 提供默认低延迟，Sidecar 提供真实的升级通道。组合策略的 C 约束满足度来自"Sidecar 切换"而非"Library 原地升级"。

### 4.4 组合策略的最终推导

综合以上分析，Connector 子系统的形态选择是一个**分层决策**：

| 层次 | 选择 | 理由 |
|------|------|------|
| 默认运行态 | Library | 满足 TTFT 约束，代码可跨引擎复用 |
| vLLM 深度集成优化 | vLLM Plugin 形式的 Engine Adapter | 将 Library 接口以最低开销接入 vLLM 的 KV Connector V1 API |
| 热升级/故障兜底态 | Sidecar（通过 IPC 代理 Library 调用） | 在升级窗口期间切至 Sidecar，保证 Library 升级不中断服务；未适配版本可快速 fallback |
| 长期演进预留 | 标准协议接口（gRPC over UDS 或共享内存） | 若未来多引擎统一协议成熟，Sidecar 接口可直接复用 |

这个组合策略的代价是：**实现复杂度高于任何单一方案**。我们需要同时维护三套调用路径（Library 本地调用、Plugin 适配层、Sidecar IPC 代理），并且确保 `KVStoreInterface` 在三套路径上的语义完全一致。这个代价是被明确接受的，因为没有任何单一方案能同时满足所有四项约束——尤其是约束 C，其实际满足路径依赖于 Sidecar 而非 Library 本身。

---

## 5. 动态行为描述

### 5.1 请求生命周期时序图（Cache Hit 场景）

以下时序图展示一个请求在 Connector 子系统内部的完整生命周期，以及它与 Engine（vLLM）、Metadata、Storage 三个外部子系统的交互关系。

```
Engine (vLLM)          Connector                    Metadata           Storage
     │                      │                          │                  │
     │  1. request_arrive   │                          │                  │
     │─────────────────────►│                          │                  │
     │                      │                          │                  │
     │  2. get_num_matched_tokens                    │                  │
     │─────────────────────►│                          │                  │
     │                      │  3. query_metadata(tokens)                │
     │                      │─────────────────────────►│                  │
     │                      │                          │                  │
     │                      │  4. match_segments       │                  │
     │                      │◄─────────────────────────│                  │
     │                      │                          │                  │
     │  5. (num_tokens, has_match)                   │                  │
     │◄─────────────────────│                          │                  │
     │                      │                          │                  │
     │  6. build_connector_meta                      │                  │
     │─────────────────────►│                          │                  │
     │                      │  7. start_load_pipeline(request, segments)│
     │                      ├────────────────────────────────────────────►│
     │                      │ (内部发起异步加载)                           │
     │                      │                          │                  │
     │                      │◄────────────────────────────────────────────┤
     │                      │  8. pipeline_ticket      │                  │
     │                      │                          │                  │
     │  9. bind_metadata    │                          │                  │
     │◄─────────────────────│                          │                  │
     │                      │                          │                  │
     │  10. start_load_kv   │                          │                  │
     │─────────────────────►│                          │                  │
     │                      │                          │                  │
     ├──────────────────────┼──────────────────────────┼──────────────────┤
     │                      │  11. Attention Layer 0   │                  │
     │  wait_layer_load("L0")│                          │                  │
     │─────────────────────►│  (若已加载完成则立即返回)                    │
     │◄─────────────────────│                          │                  │
     │                      │                          │                  │
     │  compute(layer_0)    │                          │                  │
     │  (推理计算)           │                          │                  │
     │                      │                          │                  │
     │  save_kv_layer("L0") │  12. submit_layer_save(ticket, "L0")       │
     │─────────────────────►├────────────────────────────────────────────►│
     │◄─────────────────────│ (异步保存，不阻塞)                           │
     ├──────────────────────┼──────────────────────────┼──────────────────┤
     │                      │  重复 Layer 1..N        │                  │
     ├──────────────────────┼──────────────────────────┼──────────────────┤
     │                      │                          │                  │
     │  request_finished    │  13. finalize_pipeline(ticket)             │
     │─────────────────────►├────────────────────────────────────────────►│
     │◄─────────────────────│  (确保所有异步保存完成)                      │
     │                      │  14. notify_write_complete(request, info)  │
     │                      │─────────────────────────►│                  │
     │                      │                          │                  │
```

### 5.2 时序图解读

**关键设计点 1：Metadata 查询在 Scheduler 路径同步完成**
- 步骤 2-5 发生在 vLLM Scheduler 进程中，此时请求尚未被派发至 Worker。
- Engine Adapter 调用 Metadata Client 向 Metadata 子系统发送 token 序列，获取 match segments。这个过程必须快速返回（目标 < 1ms），否则会影响调度延迟。

**关键设计点 2：加载流水线在请求派发前即已启动**
- 步骤 7：在 vLLM Worker 还未收到请求时，KVStoreInterface 调用 Pipeline Engine 已经根据 match segments 发起了异步加载。
- 这意味着当 Worker 开始执行 `start_load_kv` 时，底层 I/O 可能已经完成了一部分，从而最大限度地隐藏加载延迟。

**关键设计点 3：计算与保存的重叠**
- 步骤 11-12：在一个 Attention 层计算完成后，`save_kv_layer` 将该层的 KV 回写请求提交给 Pipeline Engine，但不需要等待保存完成即可进入下一层计算。
- layer-wise 的保存操作是异步的，只有在 `finalize_pipeline` 时（步骤 13）才会强制等待所有未完成的保存操作结束。

### 5.3 并发与线程模型

在 C 语言 + Linux 分布式存储场景下，并发模型是架构设计不可或缺的一部分。本节明确各模块的线程归属和关键共享状态的同步机制。

#### 5.3.1 线程分层模型

Connector 子系统内部不存在独立的"Connector 进程"，而是以库的形式嵌入在 vLLM 的 Python 进程中。因此，其线程模型与 vLLM 的运行时线程模型紧密相关：

| 模块 | 运行线程 | 说明 |
|------|----------|------|
| Engine Adapter | Python GIL 线程（Scheduler / Worker） | 直接被 Python 解释器调用，持有 GIL |
| KVStoreInterface | 调用方线程（Python GIL 线程或 C 扩展释放 GIL 后的工作线程） | 轻量路由层，尽量不做阻塞操作 |
| Mode Switch | 独立的控制线程（1个） | 监听配置中心和心跳信号，远离热路径 |
| Pipeline Engine | 内部 I/O 线程池（N 个） | 处理所有异步加载/保存的聚合与下发 |
| Storage Client | Pipeline Engine 的 I/O 线程池同线程 | 同步发送请求给 Storage 子系统，异步回调由 Storage 子系统的事件机制触发 |
| Metadata Client | 调用方线程（Scheduler 路径同步查询）或 Pipeline Engine I/O 线程（异步写通知） | 同步查询必须快速返回；异步通知可延迟 |
| Transport Router | Pipeline Engine 的 I/O 线程池同线程 | 路由查询有缓存时直接返回，缓存 miss 时异步更新 |

**关于线程池规模 N 的推导依据**：
Pipeline Engine I/O 线程池规模 `N = min(CPU核心数 / 2, SSD队列数 × 2)`。
- **推导逻辑**：在存储 I/O 密集型场景下，线程池的瓶颈通常是底层 NVMe SSD 的硬件队列数（通常每块 SSD 支持 32-128 个队列，但有效并行度约为 4-8）。若节点配置 2-4 块 SSD，则 `SSD队列数 × 2 ≈ 4-16`；同时为了避免与 Python GIL 工作线程过度竞争 CPU，上限设为 `CPU核心数 / 2`。
- **调整策略**：该数值为初始默认值，后续需根据实际 perf benchmark（吞吐量-延迟曲线拐点）调整。

#### 5.3.2 关键共享状态的同步机制

| 共享状态 | 访问者 | 同步机制 | rationale |
|----------|--------|----------|-----------|
| 当前模式标志（Library / Sidecar / TRANSITIONING） | Mode Switch 控制线程 + 所有热路径调用 | 读写锁（rwlock）或顺序锁（seqlock） | 热路径只读、切换时写；seqlock 在读多写极少场景下 overhead 最低 |
| Inflight 请求集合 | Pipeline Engine + Mode Switch | 互斥锁（mutex）+ 条件变量 | 切换时需要枚举并等待；操作频率中等 |
| Mode Switch 新请求拒绝标记 | Mode Switch 控制线程 + Engine Adapter | 原子变量（atomic bool） | 热路径检查，必须无锁 |
| Pipeline Engine 请求状态机表 | Pipeline Engine I/O 线程池内部 | 分片锁（per-bucket mutex）按 request_id 取模 | 高并发场景避免全局锁；bucket 数初始 1024，根据并发峰值和锁竞争测试结果调整 |
| Transport Router 拓扑缓存 | Pipeline Engine I/O 线程 + 后台更新线程 | RCU 或版本号机制 | 读远多于写；RCU 保证读取无停顿 |

**关于 bucket 数 1024 的推导依据**：
- **推导逻辑**：在预期并发请求峰值约为 1000-5000 的场景下，1024 个 bucket 可将锁竞争概率降低到约 1-5 个请求共享一个 bucket 的水平；若峰值超过 10000，则调整到 2048 或 4096。
- **调整策略**：初始值 1024，在集成测试阶段通过 `perf lock stat` 或类似工具检测 spin time，若单个 bucket 的锁等待时间 > 10μs，则翻倍扩容。

#### 5.3.3 跨模块消息传递路径

- **Engine Adapter -> KVStoreInterface**：直接函数调用（同线程）
- **KVStoreInterface -> Pipeline Engine**：函数调用，在热路径中尽量只提交轻量任务到无锁队列（如 Michael-Scott 队列）
- **Pipeline Engine -> Storage/Metadata/Transport**：由 I/O 线程从队列中取出任务后发起下游 RPC/本地调用
- **Mode Switch -> Pipeline Engine / Engine Adapter**：通过原子标志和无锁队列发布控制命令，不直接加锁阻塞热路径

### 5.4 异常路径：Library 到 Sidecar 的模式切换

```
          Normal Operation
                 │
                 ▼
     ┌───────────────────────┐
     │   Library Mode        │
     │  (local function call)│
     └───────────┬───────────┘
                 │
    ┌────────────┼────────────┐
    │            │            │
    ▼            ▼            ▼
 unadapted    lib crash   upgrade signal
 version                     │
    │            │            │
    └────────────┴────────────┘
                 │
                 ▼
     ┌───────────────────────┐
     │  Draining Phase       │
     │ (stop new requests,   │
     │  wait for inflight)   │
     └───────────┬───────────┘
                 │
     ┌────────────┴────────────┐
     │                         │
     ▼                         ▼
  draining success         draining timeout
     │                         │
     ▼                         ▼
     ┌─────────────────┐   ┌───────────────────────┐
     │  Sidecar Mode   │   │  Sidecar Mode         │
     │ (inflight完成)   │   │ (强制丢弃未完成请求)   │
     └────────┬────────┘   │ + 引擎重试            │
              │            └───────────┬───────────┘
              │                        │
              ▼                        ▼
     ┌─────────────────┐   ┌───────────────────────┐
     │  Recovery /     │   │  Recovery / Upgrade   │
     │  Upgrade        │   │  Complete             │
     │  Complete       │   │                       │
     └────────┬────────┘   └───────────┬───────────┘
              │                        │
              └──────────┬─────────────┘
                         │
                         ▼
              ┌───────────────────────┐
              │   Switch Back to      │
              │   Library Mode        │
              └───────────────────────┘
```

**inflight 请求的精确定义**：
inflight 请求是指在 Mode Switch 收到切换信号时，已经通过 `start_load_pipeline` 且尚未完成 `finalize_pipeline` 的请求集合。处于 `wait_layer_ready` 同步等待中的请求也被视为 inflight，因为它对应的 Pipeline 状态机尚未到达 COMMIT 阶段。

**切换触发条件分类**（已量化为自动类与信号类）：

| 类别 | 触发条件 | 检测机制 | 量化参数 |
|------|----------|----------|----------|
| **自动类** | Library 初始化失败 | 工厂函数返回值检查 | 首次初始化即失败，立即触发 |
| **自动类** | 未适配 vLLM 版本被检测到 | 版本字符串匹配失败 | 匹配失败时立即触发 |
| **自动类** | Library 内部不可恢复错误 | signal handler / try-catch 边界捕获 segment fault、assert 失败 | 连续 3 次调用返回 `LIBRARY_FAULT` 且在 5 秒内无恢复迹象时触发；单次 panic 立即触发 |
| **信号类** | 配置中心主动下发切换信号 | 监听配置中心 topic / 本地配置文件变更 | 收到信号后启动切换，Draining 超时 5 秒 |
| **信号类** | 运维手动触发升级窗口 | 通过 MCP / CLI 发送 `MODE_SWITCH_SIDEcar` 指令 | 收到指令后启动切换，Draining 超时 5 秒 |

**抖动防护机制（Hysteresis）**：
- **冷却时间**：任何一次自动触发切换后，60 秒内不允许再次因同一原因触发切换（避免错误恢复后的立即回切）；
- **连续失败阈值**：仅当 Library 接口连续 3 次调用失败（每次调用间隔 < 1 秒）时才判定为"需要切换"，单次网络超时或 GC 导致的偶发失败不触发；
- **回切触发条件**：Sidecar 持续运行且 Library 恢复健康的判定标准为——Sidecar 连续服务 > 30 秒且 Library 新版本进程健康检查通过（或原故障已清除）+ inflight 集合为空持续 > 10 秒。

**Draining Phase 设计**：
1. Mode Switch 原子设置"新请求拒绝标记"，Engine Adapter 在接收到新请求时立即返回 `MODE_SWITCHING` 错误码
2. 已接收的 inflight 请求继续由 Library 处理直到 `finalize_pipeline` 完成
3. Pipeline Engine 内部的 inflight 集合由 mutex 保护，Mode Switch 控制线程每 100ms 查询集合大小
4. Draining 超时阈值设为 5 秒，超时后 Library 句柄被强制关闭
   - **超时后未完成请求的处理**：这些请求不会被"接管并重续"，而是被**安全丢弃**。Sidecar 在收到引擎的重试请求时，会**重新执行**完整的 `start_load_pipeline`。
   - 这意味着：对于已部分完成的 layer 加载/保存，Sidecar 不知道 Library 中的中间状态，必须从请求起点重新开始。引擎层通过感知 `MODE_SWITCHING` 错误码，在切换完成后重新提交请求。
   - 这是"已确认提交的请求不丢失"与"5秒超时后强制切断存在未处理请求"之间**诚实的语义**：我们保证的是**已 finalize 的请求数据持久化**，而不是在切换过程中无限期阻塞所有请求。对于未 finalize 的请求，允许在超时后丢弃并由 Sidecar/引擎重试。
   - **引擎语义兼容性说明**：vLLM KV Connector V1 API 的 `start_load_pipeline` 调用**本身不保证幂等性**，但 vLLM 在接收到 `MODE_SWITCHING` 错误码后会将该请求重新放入调度队列，视为一次新的推理请求调度（即从 Scheduler 起点重放）。这意味着引擎层可以容忍"中间状态被丢弃后从起点重试"的语义。如果未来集成的引擎不支持这种重试语义，则必须将 Draining 超时设为无限长（不允许强制丢弃），或通过引擎 Adapter 实现请求状态的 snapshot/restore 机制。

**Sidecar 重试时序图**：

```
Engine (vLLM)     Mode Switch    Pipeline Engine    Sidecar
     │                  │                │              │
     │  request_1       │                │              │
     ├─────────────────►│                │              │
     │  (accepted)      │                │              │
     │                  │  upgrade signal│              │
     │                  │◄───────────────│              │
     │                  │                │              │
     │  request_2       │                │              │
     ├─────────────────►│                │              │
     │◄─────────────────│  MODE_SWITCHING│              │
     │  (rejected)      │                │              │
     │                  │                │              │
     │                  │  wait inflight │              │
     │                  │ (5 sec timeout)│              │
     │                  │                │              │
     │                  │  force cutover │              │
     │                  ├──────────────────────────────►│
     │                  │                │              │
     │  request_1 retry │                │              │
     ├─────────────────►│                │              │
     │  (routed to      │                │              │
     │   Sidecar)       │                │              │
     │                  ├──────────────────────────────►│
     │                  │                │              │
     │◄─────────────────┼───────────────────────────────│
     │  new pipeline    │                │              │
     │  (request_1)     │                │              │
```

### 5.5 Sidecar 回切 Library 的恢复路径

**为什么回切路径必须被显式设计**：
Sidecar 只是临时兜底态，升级或故障恢复完成后必须切回 Library，否则系统将持续运行在性能劣化路径上。回切路径包含触发条件、Draining 机制、失败回退三个要素。

**回切触发条件**（必须同时满足）：
1. Library 新版本已部署完成且健康检查通过（或原故障已清除）；
2. Sidecar 中 inflight 请求集合为空，且持续为空的时间 > 10 秒；
3. 过去 30 秒内 Sidecar 未再收到自动类切换信号（避免回切到仍有问题的 Library）。

**回切时序图**：

```
Sidecar               Mode Switch         Pipeline Engine      Library
  │                        │                     │                │
  │  (正常运行)             │                     │                │
  │                        │  health_check_pass  │                │
  │                        │◄────────────────────│                │
  │                        │  + inflight_empty   │                │
  │                        │  for 10s            │                │
  │                        │                     │                │
  │                        │  set REJECT_NEW     │                │
  │◄───────────────────────│                     │                │
  │  (stop new requests)   │                     │                │
  │                        │  wait inflight      │                │
  │                        │  (5 sec draining)   │                │
  │                        │                     │                │
  │                        │  switch to Library  │                │
  ├────────────────────────┼─────────────────────┼───────────────►│
  │  (any remaining        │                     │                │
  │   requests routed)     │                     │                │
  │                        │  clear REJECT_NEW   │                │
  │◄───────────────────────│                     │                │
  │  (resume normal)       │                     │                │
```

**回切失败回退**：
- 若回切过程中 Library 再次触发自动类切换条件（如 health check 再次失败），立即终止回切并重新切回 Sidecar；
- 若回切后 60 秒内 Library 再次触发自动类切换，则将"自动回切"功能暂时禁用，转为"手动审批回切"模式，需运维手动确认后方可再次尝试。

---

## 6. 与周边子系统的边界和交互

| 周边子系统 | 交互方向 | Connector 的职责边界 | 传递的数据/控制流 | 一致性要求 |
|-----------|---------|---------------------|------------------|-----------|
| **Engine（推理引擎）** | 双向 | Connector 是引擎与内部子系统的唯一网关。只暴露必要的 token 匹配、KV 加载/保存钩子点，禁止引擎直接访问 Storage/Metadata | 输入：token 序列、请求元数据；输出：命中 token 数、block table 引用、异步完成通知 | 强一致：block table 的变更必须被引擎和 Connector 双方精确同步 |
| **Metadata（元数据）** | 客户端->服务端 | Connector 只作为查询客户端，不拥有元数据索引。它提交 token 序列并接收命中分段结果，不负责索引的维护和持久化 | 输入：token 序列列表、写完成通知；输出：match segments（起始偏移、长度、存储层级） | 最终一致：允许 Metadata 索引暂时落后实际存储状态，不一致时以 Storage 为准 |
| **Storage（存储）** | 客户端->服务端 | Connector 通过 Storage Client 发起 block 级别的 allocate/load/store 请求，但不过问数据在 Storage 内部如何组织、压缩或 tiering | 输入：block 分配/加载/回写请求；输出：block handle、I/O 完成状态、存储层级信息 | 强一致：单个 block 的 allocate-free 和 load-store 操作必须以原子语义完成 |
| **Transport（传输）** | 客户端->服务端 | Connector 不直接操作网络连接。在 PD 分离或远端加载场景下，Transport Router 向 Transport 子系统查询逻辑节点的路由信息，将返回的**逻辑节点 ID**和协议推荐附在 Storage 请求中，由 Storage 子系统负责解析为实际网络地址 | 输入：目标 block 的远端定位需求；输出：**逻辑节点 ID**、协议推荐、链路延迟估计 | 弱一致：路由信息允许短暂过期，Storage 在传输失败时可重试或降级 |

### 边界设计 rationale

**Engine 边界：最小暴露原则**
- vLLM 是一个非常活跃演进的代码库。如果我们允许 Engine 直接调用 Storage 或 Metadata 的接口，那么 vLLM 的任何版本变更都可能波及到多个子系统。`KVStoreInterface` 的存在就是为了将所有版本适配的复杂度压缩到 Engine Adapter 这一个狭窄区域。

**Metadata 边界：只读查询为主，写通知为辅**
- Connector 不负责元数据索引的构建和维护（这是 Metadata 子系统的核心职责）。Connector 只是在 KV 写入完成后异步通知 Metadata，让后者有机会更新索引。这种设计的优点是：即使 Metadata 临时不可用，Connector 仍然可以通过 Storage Client 的本地缓存或降级策略继续服务请求。

**Storage 边界：block 语义，不问组织**
- Connector 认为 Storage 是一个黑盒的 block 存储服务。Connector 不知道 block 内部是否分 chunk、是否压缩、是否做 RAID。这种抽象确保了 Storage 子系统可以独立演进其 tiering 策略和介质组织，而不影响 Connector 的接口契约。

**Transport 边界：路由顾问，不握数据面**
- Transport 子系统涉及复杂的 RDMA QP 管理、网络拓扑感知、故障恢复协议。Connector 不直接参与这些高级网络操作，而仅作为"路由顾问"提供**逻辑节点 ID**。Storage 子系统收到逻辑节点 ID 后，再通过 Transport 子系统解析为实际的网络地址（IP、RDMA GID、QP 等）。这样 Connector 不涉及数据面状态，也不会将网络编程的复杂度引入引擎集成层。

---

## 7. 热升级部署拓扑与运维流程

### 7.1 部署拓扑视图

```
┌─────────────────────────────────────────────────────────────┐
│                    推理节点（单 GPU 节点示例）                  │
│  ┌───────────────────────────────────────────────────────┐  │
│  │           vLLM Worker 进程                            │  │
│  │  ┌─────────────────────────────────────────────────┐  │  │
│  │  │  Engine Adapter (Python / C++)                  │  │  │
│  │  │  ├─ 正常运行时：直接调用 Library (.so)          │  │  │
│  │  │  └─ 切换时：通过 UDS / 共享内存调用 Sidecar    │  │  │
│  │  └─────────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────┘  │
│                              │                              │
│              ┌───────────────┴───────────────┐              │
│              │         Mode Switch           │              │
│              │    (同进程内的控制线程)        │              │
│              └───────────────┬───────────────┘              │
│                              │                              │
│              ┌───────────────┴───────────────┐              │
│              ▼                               ▼              │
│  ┌───────────────────────┐      ┌───────────────────────┐  │
│  │   Library (.so)       │      │   Sidecar 进程        │  │
│  │   (同进程内加载)      │      │   (同机独立进程)      │  │
│  │   默认路径            │      │   升级/故障兜底路径   │  │
│  └───────────────────────┘      └───────────────────────┘  │
│                                          │                  │
│                                          ▼                  │
│                              ┌───────────────────────┐     │
│                              │  Sidecar IPC Agent    │     │
│                              │  (预先部署，常驻待命)  │     │
│                              └───────────────────────┘     │
└─────────────────────────────────────────────────────────────┘
```

**部署说明**：
- **Library**：以 `.so` 形式被 `dlopen` 加载到 vLLM Worker 进程内部，与 Engine Adapter 在同一地址空间；
- **Sidecar**：以独立进程部署在**同一物理节点**（同机双进程），通过 Unix Domain Socket (UDS) 或共享内存与 vLLM Worker 通信；
- **Sidecar 预热要求**：Sidecar 进程在节点启动时即预先部署并常驻（类似 DaemonSet 的副本），确保切换时无需临时拉启，切换延迟 < 100ms；
- **实例比例**：每个 vLLM Worker 节点对应 **1 个 Sidecar 实例**（若同一节点运行多个 vLLM Worker，则每个 Worker 对应 1 个 Sidecar，避免 IPC 路由冲突）。

### 7.2 热升级标准操作流程

**升级前准备**：
1. 运维通过配置中心或 MCP 向目标节点发送 `UPGRADE_PREPARE` 信号；
2. Mode Switch 收到信号后，开始记录新请求但不再接受新的长请求（超过 3 层的 pipeline）；
3. Sidecar 进程预加载新版本的 Library 代理逻辑（若需要）。

**切换执行**：
1. 运维发送 `MODE_SWITCH_SIDECAR` 指令；
2. Mode Switch 启动 Draining Phase（5 秒超时）；
3. inflight 请求完成后，流量切至 Sidecar；
4. vLLM Worker 进程内的旧 Library `.so` 被安全卸载（若 dlclose 有风险，则仅做逻辑禁用，重启 Worker 时释放）。

**升级操作**：
1. 在 Sidecar 运行期间，部署新版本的 Library `.so` 到节点文件系统；
2. 执行新 Library 的单元测试和健康检查；
3. 新 Library 通过验证后，触发 `SWITCH_BACK_LIBRARY`；
4. 回切成功后，Sidecar 继续待命。

**可用性量化保证**：
- **请求中断时间**：从 `MODE_SWITCH_SIDECAR` 到 Sidecar 接受首个重试请求，目标 < 100ms（不含引擎重试调度延迟）；
- **升级期间性能劣化**：Sidecar 模式下 TTFT 可能增加 5-20%，在可接受范围内；
- **失败回退**：若升级后 Library 出现异常，60 秒内自动回退至 Sidecar，无需人工介入。

---

## 8. 设计 rationale

### 8.1 "为什么不是纯 Plugin？"

纯 Plugin 最大的诱惑是延迟最低（函数调用级别），但它的致命缺陷是**版本锁定和热升级不可行**。

- vLLM 的 KV Connector V1 API 在 v0.4 到 v0.6 期间已经历了多次非兼容变更（如 `get_num_new_matched_tokens` 的参数列表调整、`KVConnectorMetadata` 的序列化方式变化）。如果我们将整个 KVCache Offloading 系统的逻辑都写成 vLLM Plugin，那么每次 vLLM 升级都意味着整个系统需要重新适配、重新测试、重新发布。
- 更重要的是，Plugin 加载在 vLLM 进程内部，升级 Plugin 必须重启 vLLM worker。对于在线服务而言，重启 worker 意味着中断正在处理的请求，这在生产环境中是不可接受的。

因此，纯 Plugin 被降级为"优化路径"而非"架构主体"。

### 8.2 "为什么不是纯 Sidecar？"

纯 Sidecar 的独立性和可升级性最好，但它的延迟开销（gRPC/HTTP 约 1-10ms）直接破坏了 TTFT 优化场景的核心价值。

KV Cache offloading 的收益主要来自 cache hit 时避免重复计算前缀。以一个 2K token 的 prompt 为例，如果不走 offloading，首 token 生成可能需要 500ms；如果走 offloading 成功，TTFT 可能降至 50ms。这个 10 倍的性能提升是产品的核心卖点。但如果 Sidecar 的序列化和 IPC 开销吞噬了 5ms，这对 50ms 的基线来说是不可忽略的（+10%）。更关键的是，在 layer-wise 的密集同步点（每个 Attention 层的 `wait_layer_ready`），任何可叠加的延迟都会被放大。

因此，纯 Sidecar 只能作为兜底态，不能作为默认态。

### 8.3 "这个选择的最优场景和最差场景是什么？"

**最优场景**：
- 部署环境以 vLLM 为主，且版本稳定在 v0.4.x-v0.6.x 范围内
- 工作负载具有较高的前缀复用率（cache hit 概率 > 50%），TTFT 优化收益显著
- 团队具备维护 C/C++ Library 和 Python Plugin 适配层的全栈能力
- 拥有 RDMA 或 NVMe SSD 等高速存储/传输基础设施，能够发挥异步流水线的延迟隐藏能力

**最差场景与量化失效边界**：

| 失效条件 | 触发阈值 | 止损动作 | 对齐 ADR |
|----------|----------|----------|----------|
| Cache hit 率过低，I/O 开销超过重计算收益 | < 20% | 通过 Mode Switch 触发全量 fallback 至本地重算（即关闭 offloading） | ADR-003 |
| Offloading 导致 TTFT 增量过大 | > 20ms | 触发降级：关闭远端加载，仅使用本地 HBM/DRAM 缓存 | ADR-003 |
| P99 TTFT 因缓存未命中持续恶化 | > 100ms 且持续 1 周 | 启动架构演进评审，评估是否引入更快存储介质或调整 tiering 策略 | ADR-003 |
| vLLM 发布破坏性大版本（如 v0.7.x），适配成本超出预算 | > 1 人周（累计 > 2 人周触发熔断） | 自动 fallback 至 Sidecar 模式，直到 Adapter 适配完成；同时启动强制评审 | ADR-006 |

补充说明：
- 当 cache hit 率 < 20% 时，绝大多数 token 都需要从远端加载或重新计算。考虑到 LMCache/SSD 场景下加载延迟约为 10-50ms/层，而重计算的 GPU 计算延迟约为 1-5ms/层，此时 I/O 路径的开销已经明显超过重计算收益。
- 当 offloading 导致的 TTFT 增量 > 20ms 时，相对于 50ms 的基线已经增加了 40%，产品收益被严重稀释。此时应当触发降级，优先保证推理延迟稳定性。
- P99 TTFT > 100ms 且持续 1 周的阈值直接引用自 ADR-003 阶段切换 SLI/SLO："阶段 1→2 触发条件：P99 TTFT 因缓存未命中 > 100ms 且持续 1 周"。

### 8.4 "如果未来需求变更，这个设计的脆弱点在哪里？"

**脆弱点 1：`KVStoreInterface` 的抽象粒度可能过粗或过细**
- 如果未来某个引擎（如 TensorRT-LLM）的 KV Cache 管理语义与 vLLM 差异极大（例如不使用 block table 而是使用连续缓冲区），那么当前 `KVStoreInterface` 中围绕 "block" 和 "block table" 的抽象就可能成为负担，需要在接口层引入新的原语。
- 缓解方向：`KVStoreInterface` 的设计已预留扩展空间（如 `AllocationHint`、`SegmentInfo` 等扩展字段），但未来若需要根本性重构， mitigation 是逐步替换接口而不是一次性打破。

**脆弱点 2：双模式切换的测试矩阵复杂**
- Library 正常路径、Library 异常路径、Sidecar 正常路径、Sidecar 回切路径、混合模式下的并发场景，构成了一个 2^N 的测试空间。任何一个路径的回归都可能在生产环境中触发不可预期的降级。
- 缓解方向：在 Connector 内部实现统一的"模式无关测试桩"，用同一套测试用例对 Library 和 Sidecar 两种实现做接口级回归。

**脆弱点 3：vLLM 社区彻底弃用 KV Connector V1 API**
- 这是最高影响、中可能性的风险。如果 vLLM 在 v0.7 或更高版本中完全移除 V1 API（例如改为更强的编译时静态绑定），我们的 vLLM Plugin 适配层将面临推倒重来。
- 缓解方向：主动参与 vLLM 社区讨论，订阅其设计变更；同时保留一个非 Plugin 的 fallback 路径（例如直接通过 pybind/Cython 与 vLLM 内部模块交互），作为 API 弃用时的逃生通道。

---

## 9. 风险点和缓解策略

### 高影响风险

| 风险 | 可能性 | 影响 | 缓解策略 |
|------|--------|------|----------|
| **vLLM API 变更导致适配成本激增** | 高 | 高 | 1) 设计 `KVStoreInterface` 隔离层，将 vLLM 特定调用压缩在 Adapter 内部；2) 订阅 vLLM release note 和 Discord #announcements，建立 24h 变更响应机制；3) 设定维护预算熔断线：单个 minor 版本适配 > 1 人周或连续 2 个版本超出预算时，触发"切换为更稳定集成模式"的强制评审 |
| **Library 崩溃导致推理引擎整体崩溃** | 中 | 高 | 1) 在 Engine Adapter 与 Library 核心代码之间设置错误隔离边界（try-catch / signal handler），捕获 segment fault 等致命错误后自动触发 Sidecar fallback；2) Library 内部使用独立的内存池，避免污染引擎的堆内存；3) 对 Library 做严格的 fuzz 测试和 valgrind 检测，崩溃率目标 < 0.001% |
| **双模式切换状态不一致导致缓存脏读或请求失败** | 中 | 高 | 1) `KVStoreInterface` 的接口契约必须通过单元测试和接口兼容测试在两种模式下做 100% 回归验证；2) 模式切换的 Draining Phase 设置 5 秒超时，超时后安全丢弃 inflight 请求并触发引擎重试；3) 引入 per-request 的版本标记，Sidecar 发现状态不匹配时通知引擎回退到请求起点重算 |
| **Sidecar fallback 的性能滑坡未被及时发现** | 中 | 高 | 1) 在 Sidecar 模式下对 TTFT、TPOT 增加实时告警阈值（TTFT 增加 > 20% 触发告警）；2) 定期（每月）执行 Library/Sidecar 两种模式下的 A/B 性能测试，监控性能退化趋势 |

### 中影响风险

| 风险 | 可能性 | 影响 | 缓解策略 |
|------|--------|------|----------|
| 多引擎抽象层导致性能损失 | 中 | 中 | 在 `KVStoreInterface` 的热路径（如 `wait_layer_ready`）做 overhead profiling，若发现抽象层开销 > 5%，提供"绕过模式"供特定引擎直接优化 |
| Pipeline 死锁或资源竞争 | 中 | 中 | Pipeline Engine 内部实现全局资源配额和超时机制（单阶段超时 5 秒），并定期运行死锁检测扫描 |
| Engine Adapter 中引擎特定数据结构的转换开销过高 | 低 | 中 | 在 Adapter 层引入 block table 缓存池，避免每次请求都重新分配和拷贝引擎无关视图 |

---

## 10. 预选方案收敛（扩展讨论）

### 10.1 Sidecar IPC 协议：倾向性预选方案

经过延迟与复杂度的权衡，**倾向性选择候选 B：共享内存环形队列 + 自定义二进制协议**，作为 Sidecar 与 Engine Adapter 之间的 IPC 机制。

| 候选方案 | 延迟量级 | 复杂度 | 倾向性评估 |
|----------|----------|--------|------------|
| A: UDS + protobuf | ~100μs | 低 | 备选（仅在共享内存实现延迟无法达标时回退） |
| **B: 共享内存环形队列 + 自定义二进制协议** | **~10μs** | **中** | **主选**：延迟最低，接近 Library 函数调用开销；实现复杂度可控（Linux shm + 无锁环形队列） |
| C: gRPC over UDS | ~1ms | 低 | 排除：1ms 延迟在 layer-wise 同步点下不可接受 |

**决策前提**：若共享内存方案在 POC 中无法稳定运行在 < 50μs P99 延迟，则回退至候选 A（UDS + protobuf）。

### 10.2 Batching 语义：职责已收敛

Batching 策略的归属已在 **Module 4: Pipeline Engine** 中明确：**Pipeline Engine 是 batch 聚合的单一负责人**，Storage Client 只负责透传。此决策不再作为开放性问题，而是作为架构约束写入设计。

### 10.3 Transport Router 拓扑缓存策略

| 策略 | 适用场景 | 倾向性 |
|------|----------|--------|
| TTL 缓存（5 秒） | 节点扩缩容频繁、网络拓扑变化快 | 默认策略 |
| 事件驱动更新 | Transport 子系统已提供拓扑变更推送接口 | 增强策略（如有推送接口则优先采用） |

**量化约束**：缓存过期导致的路由错误率目标 < 0.1%；若错误率超过 0.5%，将 TTL 从 5 秒缩短至 1 秒或启用事件驱动更新。

---

*文档正文结束*

---

## 修正摘要
接受 reviewer 质疑并修正定稿：
1. 补充 Sidecar → Library 回切时序图与部署拓扑视图，明确热升级执行方式；
2. 标注 inflight 丢弃的引擎语义兼容性（vLLM 支持从 Scheduler 起点重试），并补充回切失败回退策略；
3. 量化 Mode Switch 触发条件（自动类/信号类）、抖动防护机制（冷却时间、连续失败阈值、Hysteresis）；
4. 明确 batching 单一负责人为 Pipeline Engine，消除与 Storage Client 的职责重叠；
5. 拆解"1人周"适配成本为 5.5 个工作日明细，并设定超支熔断机制；
6. 清洗魔法数字（线程池 N、bucket 数 1024），补充推导依据与调整策略；
7. 收敛扩展讨论中的待决问题到倾向性预选方案（共享内存 IPC、TTL/事件驱动缓存）。
置信度由中（68%）提升至**高（87%）**。
