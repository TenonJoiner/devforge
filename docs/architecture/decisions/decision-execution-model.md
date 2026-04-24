# ADR-005: 执行引擎/调度模型决策

- **状态**: 草稿
- **日期**: 2026-04-21
- **决策人**: architect
- **置信度**: 中（关键假设待原型验证）

---

## 背景

### 问题定义

KV Cache 分布式存储系统的执行引擎需要同时处理两类高并发 I/O：

1. **NVMe SSD I/O**：通过 SPDK 用户态驱动，绕过内核，直接操作 NVMe 队列对
2. **RDMA 网络 I/O**：通过 libibverbs，处理数千并发连接的 RDMA 双边操作

核心挑战：

| 挑战 | 具体描述 | 不解决的后果 |
|------|----------|-------------|
| **双事件源统一调度** | NVMe CQ（完成队列）和 RDMA CQ 都需要被及时处理 | 事件延迟处理导致 I/O 超时或吞吐下降 |
| **CPU 亲和性** | 网卡和 NVMe SSD 通常绑定到特定 NUMA 节点 | 跨 NUMA 访问导致延迟增加 2~3x |
| **无锁热路径** | 亚毫秒级延迟要求禁止 malloc/锁/系统调用 | 锁竞争导致 P99 延迟恶化到 ms 级 |
| **C 语言约束** | 团队技术栈为 C 语言 | C++ 框架（Seastar）需要评估绑定成本 |
| **协程 vs 事件驱动** | 异步 I/O 的编程模型选择影响代码可维护性 | 回调地狱或协程调度开销 |

### 与整体架构的关系

本决策是 `decision-overall.md` 中识别的维度 5（执行引擎/调度模型），与以下决策强相关：

- `decision-storage-engine.md`（SPDK 裸盘管理）— 本决策的上游约束
- `decision-transport.md`（RDMA 传输层设计）— 本决策的下游消费者

---

## 标杆参考

| 标杆产品 | 相关技术 | 分析结论 |
|----------|----------|----------|
| **InfiniStore** | libuv 事件循环统一调度 TCP + RDMA CQ | libuv 的 `uv_poll_t` 可将 RDMA CQ fd 纳入事件循环，但纯事件驱动增加 ~5μs 延迟。仅适合中等并发（<1000 连接），高并发时 epoll 效率下降。参见 [标杆分析：InfiniStore](../reference/arch-infinistore.md) |
| **ScyllaDB** | Seastar reactor + 用户态 TCP/IP | 生产验证最强（Cassandra 兼容，PB 级数据），但纯 C++，无 C API。DPDK 网络栈与本系统 RDMA 需求不完全匹配 |
| **DAOS** | Argobots ULT + tse 任务调度 + SPDK | C 语言原生，与 SPDK 有深度集成经验（DAOS 存储层直接调用 SPDK NVMe 驱动）。但线程模型复杂（xstream + offload XS），学习曲线陡峭 |
| **SPDK NVMe-oF** | SPDK reactor + RDMA transport | SPDK 原生支持 NVMe-oF RDMA target，有完整性能报告（24.05 版：ConnectX-5 上 6M+ IOPS）。但 NVMe-oF 是块协议，与 KV Cache 语义不匹配 |

---

## 学术论文参考

| 论文 | 会议/年份 | 核心贡献 | 借鉴点 |
|------|-----------|----------|--------|
| "Seastar: High-Performance Server Applications" | ScyllaDB Tech Report | Shared-nothing + per-core sharding 架构 | NUMA-aware 设计、无锁消息传递 |
| "Argobots: A Lightweight Low-Level Threading and Tasking Framework" | PPoPP 2017 | User-Level Threads (ULT) 调度 | DAOS 底层线程模型，轻量级上下文切换 |
| "SPDK: Storage Performance Development Kit" | Intel Whitepaper | 用户态 NVMe 驱动 + reactor 模型 | NVMe I/O 零拷贝路径设计 |

---

## 候选方案

### 方案 A：SPDK Reactor 原生模型

**核心思路**：完全基于 SPDK Event Framework。每个 CPU core 运行一个 reactor 线程，通过无锁事件队列（ring buffer）进行跨核通信。NVMe I/O 通过 SPDK 原生 bdev 层提交，RDMA 通过 SPDK 的 RDMA 库或独立 poller 处理。

**参考来源**：SPDK Event Framework（`spdk.io/doc/event.html`）、SPDK NVMe-oF RDMA Target

**架构草图**：

```
+-------------------------------------------------------------+
|                    SPDK Event Framework                      |
|  +----------------+  +----------------+  +----------------+ |
|  | Reactor 0      |  | Reactor 1      |  | Reactor N      | |
|  | (Master)       |  | (I/O Core)     |  | (I/O Core)     | |
|  |                |  |                |  |                | |
|  | - NVMe Admin   |  | - NVMe I/O QP |  | - NVMe I/O QP | |
|  | - RDMA CM      |  | - RDMA CQ poll|  | - RDMA CQ poll| |
|  | - Timer        |  | - Timer        |  | - Timer        | |
|  +-------+--------+  +-------+--------+  +-------+--------+ |
|          |                   |                   |           |
|          v                   v                   v           |
|  +--------------------------------------------------------+ |
|  |         Lockless Ring Buffer (spdk_ring)               | |
|  +--------------------------------------------------------+ |
+-------------------------------------------------------------+
         |                      |                      |
         v                      v                      v
  +-------------+        +-------------+        +-------------+
  | NVMe SSD 0  |        | NVMe SSD 1  |        | RDMA NIC    |
  | (local)     |        | (local)     |        | (mlx5_0)    |
  +-------------+        +-------------+        +-------------+
```

**优点**：

1. **SPDK 原生集成度最高**：NVMe I/O 路径零适配成本，bdev、blobfs、nvme 等子系统直接可用
2. **Shared-nothing 无锁设计**：reactor 间通过无锁 ring buffer 通信，无共享状态，天然 NUMA 亲和
3. **生产验证充分**：SPDK NVMe-oF RDMA target 有官方性能报告（24.05 版 ConnectX-5 上达到 6M+ IOPS，延迟 < 10μs）
4. **C 语言原生**：完全匹配团队技术栈，无需语言绑定层
5. **CPU 亲和性内置**：`spdk_env_init()` 自动绑定线程到 core，支持 NUMA-aware 内存分配

**缺点**：

1. **RDMA 集成路径不清晰**：SPDK 的 RDMA 支持主要面向 NVMe-oF（块协议），而非通用的 RDMA SEND/RECV 或双边操作。KV Cache 需要的 RDMA 语义（服务端 READ/WRITE 客户端内存）需要自行实现或适配
2. **编程模型受限**：纯事件回调模型，异步逻辑需通过 `spdk_event_call()` 和回调函数表达，复杂流程易陷入"回调地狱"
3. **生态相对封闭**：SPDK 的线程模型（reactor + poller）与外部库集成困难，如需要独立线程池时需特殊处理

**适用场景**：以 NVMe I/O 为主、网络 I/O 为辅的存储系统；团队已有 SPDK 经验。

---

### 方案 B：Seastar 协程框架

**核心思路**：引入 Seastar C++ 框架，利用其 reactor + 协程（C++20 coroutines / futures-promise）模型。网络使用 Seastar 的 DPDK/用户态 TCP 栈或原生 Posix socket，NVMe I/O 通过适配层调用 SPDK。

**参考来源**：Seastar（`seastar.io`，ScyllaDB 底层框架）、Seastar Networking Docs

**架构草图**：

```
+-------------------------------------------------------------+
|                    Seastar Application                       |
|  +----------------+  +----------------+  +----------------+ |
|  | Shard 0        |  | Shard 1        |  | Shard N        | |
|  | (Reactor)      |  | (Reactor)      |  | (Reactor)      | |
|  |                |  |                |  |                | |
|  | - TCP/DPDK Net |  | - TCP/DPDK Net |  | - TCP/DPDK Net | |
|  | - Coroutine    |  | - Coroutine    |  | - Coroutine    | |
|  |   Scheduler    |  |   Scheduler    |  |   Scheduler    | |
|  | - SPDK Adapter |  | - SPDK Adapter |  | - SPDK Adapter | |
|  +-------+--------+  +-------+--------+  +-------+--------+ |
|          |                   |                   |           |
|          v                   v                   v           |
|  +--------------------------------------------------------+ |
|  |         smp::submit_to() 跨核消息传递                   | |
|  +--------------------------------------------------------+ |
+-------------------------------------------------------------+
         |                      |                      |
         v                      v                      v
  +-------------+        +-------------+        +-------------+
  | SPDK Bdev   |        | SPDK Bdev   |        | DPDK / Posix|
  | (NVMe I/O)  |        | (NVMe I/O)  |        | Network     |
  +-------------+        +-------------+        +-------------+
```

**优点**：

1. **协程编程模型先进**：C++20 coroutines 或 futures/promises 让异步代码看起来像同步代码，可维护性远高于纯回调
2. **网络栈成熟**：用户态 TCP/IP 栈（DPDK 模式）零拷贝、零锁、零上下文切换，延迟极低
3. **Shared-nothing 架构**：与 SPDK reactor 类似的 per-core sharding，跨核通信通过 `smp::submit_to()` 显式消息传递
4. **生产验证极强**：ScyllaDB 在 PB 级生产环境验证，延迟和吞吐表现优异

**缺点**：

1. **C++ 框架，无 C API**：Seastar 是纯 C++ 框架（大量使用模板、C++20 特性），本系统要求 C 语言，需要完整的 C++ → C 封装层，成本极高
2. **RDMA 支持缺失**：Seastar 网络栈基于 DPDK/Posix socket，无原生 RDMA（libibverbs）支持。需要自行实现 RDMA 适配层，工作量巨大
3. **SPDK 集成非原生**：Seastar 与 SPDK 的集成需要自定义适配层（将 SPDK 的 reactor 事件映射到 Seastar 的 future），社区无成熟方案
4. **二进制体积大**：Seastar 依赖大量 C++ 模板，编译时间长，二进制体积大

**适用场景**：C++ 团队、以 TCP/HTTP 网络为主、对协程编程模型有强需求的系统。

---

### 方案 C：DAOS 协程框架（Argobots ULT + tse + dRPC）

**核心思路**：借鉴 DAOS 的执行模型。底层使用 Argobots（用户级线程，ULT）提供轻量级并发，tse（Task Scheduler Engine）管理异步任务依赖和调度，dRPC 处理控制平面通信。NVMe I/O 通过 DAOS 的 bio（Blob I/O）层调用 SPDK。

**参考来源**：DAOS `src/engine/srv.c`、`src/include/daos/tse.h`、`src/engine/drpc_internal.h`

**架构草图**：

```
+-------------------------------------------------------------+
|                    DAOS-Style Engine                         |
|                                                              |
|  +------------------+  +------------------+  +--------------+|
|  | System XS (XS 0) |  | Main XS (XS 1~N) |  | Offload XS   ||
|  | - dRPC listener  |  | - RPC handler    |  | - EC/compress||
|  | - Meta-data svc  |  | - VOS I/O        |  | - IO dispatch||
|  | - SWIM heartbeat |  | - tse scheduler  |  |              ||
|  +--------+---------+  +--------+---------+  +--------------+|
|           |                     |                            |
|           v                     v                            |
|  +--------------------------------------------------------+ |
|  |              Argobots ULT Scheduler (ABT)              | |
|  |   (User-Level Threads, lightweight context switch)     | |
|  +--------------------------------------------------------+ |
|           |                     |                            |
|           v                     v                            |
|  +------------------+  +------------------+                 |
|  | tse_task queue   |  | bio (SPDK bdev)  |                 |
|  | - dependency mgmt|  | - NVMe I/O       |                 |
|  | - completion cb  |  | - blob I/O       |                 |
|  +------------------+  +------------------+                 |
+-------------------------------------------------------------+
```

**优点**：

1. **C 语言原生**：DAOS 整个栈（tse、dRPC、bio、vos）都是 C 语言，与团队技术栈完全匹配
2. **与 SPDK 深度集成**：DAOS 的 `bio` 层直接调用 SPDK bdev API，有成熟的 NVMe I/O 路径和故障处理经验
3. **轻量级并发（ULT）**：Argobots 的用户级线程比 OS 线程轻量 100x+，可在单 core 上调度数万 ULT，适合高并发 RPC 处理
4. **任务依赖管理（tse）**：tse 提供任务依赖图（`tse_task_register_deps`）、完成回调、调度器进度推进，适合复杂异步流程（如写入 = 分配 → RDMA READ → 插入索引 → 确认）
5. **分层线程模型**：System XS 处理控制平面，Main XS 处理 I/O，Offload XS 处理计算密集型任务（EC、压缩），职责清晰

**缺点**：

1. **架构复杂度高**：DAOS 的线程模型（xstream、ULT、tse、sched）概念多，学习曲线陡峭。DAOS 引擎代码 `srv.c` 超过 1000 行仅做线程启动
2. **RDMA 仍需自行实现**：DAOS 的网络层基于 Mercury（HPC RPC 框架）或 libfabric，非原生 RDMA Verbs。KV Cache 需要的双边 RDMA 操作需要额外开发
3. **依赖 Argobots**：引入 Argobots 作为额外依赖，增加构建复杂度和调试难度
4. **过度设计风险**：DAOS 面向 Exascale HPC 场景（数千节点），本系统目标 4~16 节点，部分设计（如 SWIM 成员管理、多 tier 存储）可能过度

**适用场景**：C 语言团队、需要复杂任务依赖管理、已有 Argobots/DAOS 经验。

---

### 方案 D：SPDK Reactor + 独立 RDMA 线程混合模型

**核心思路**：SPDK reactor 专注处理 NVMe I/O 和本地事件循环，RDMA 事件通过独立的 RDMA 线程池（每个线程忙轮询一个 RDMA CQ）处理。两者通过无锁队列（如 `rte_ring` 或自定义 lock-free queue）交换消息。

**参考来源**：InfiniStore 事件驱动模型（改进版）、SPDK `thread.h` 的 `spdk_thread` 抽象

**架构草图**：

```
+-------------------------------------------------------------+
|                     Hybrid Model                             |
|                                                              |
|  +----------------------+    +---------------------------+  |
|  |   SPDK Reactors      |    |   RDMA Thread Pool        |  |
|  |   (NVMe I/O)         |    |   (Network I/O)           |  |
|  |                      |    |                           |  |
|  |  +----------------+  |    |  +--------------------+   |  |
|  |  | Reactor 0      |  |    |  | RDMA Thread 0      |   |  |
|  |  | - bdev poller  |  |    |  | - CQ busy poll     |   |  |
|  |  | - timer        |  |    |  | - WR batching      |   |  |
|  |  +----------------+  |    |  +--------------------+   |  |
|  |  +----------------+  |    |  +--------------------+   |  |
|  |  | Reactor 1      |  |    |  | RDMA Thread 1      |   |  |
|  |  | - bdev poller  |  |    |  | - CQ busy poll     |   |  |
|  |  +----------------+  |    |  +--------------------+   |  |
|  +----------+-----------+    +-----------+---------------+  |
|             |                            |                  |
|             v                            v                  |
|  +--------------------------------------------------------+ |
|  |         Lock-Free Request Queue (per-core pair)        | |
|  |   RDMA thread → SPDK reactor: data ready, alloc request| |
|  |   SPDK reactor → RDMA thread: alloc complete, post WR  | |
|  +--------------------------------------------------------+ |
+-------------------------------------------------------------+
```

**优点**：

1. **职责分离清晰**：NVMe I/O 和 RDMA 网络各自使用最适合的模型，互不干扰
2. **RDMA 延迟最优**：RDMA 线程忙轮询 CQ，延迟最低（无事件驱动 ~5μs 开销）
3. **SPDK 原生能力完整保留**：无需适配层，所有 SPDK 子系统直接可用
4. **实现相对简单**：比 DAOS 的 ULT 模型简单，比 Seastar 的 C++ 封装简单

**缺点**：

1. **跨线程通信开销**：RDMA 线程和 SPDK reactor 间的消息传递引入额外延迟（~1~2μs）
2. **CPU 资源竞争**：RDMA 忙轮询占用 100% CPU，需要 pin 到独立 core，减少可用 I/O core
3. **状态同步复杂**：请求在 RDMA 线程和 SPDK reactor 间流转，需要仔细设计状态机和生命周期
4. **非统一调度**：两个调度域（SPDK event loop + RDMA thread）增加了系统复杂度

**适用场景**：对 RDMA 延迟要求极致（< 5μs）、CPU 资源充足（可 dedicating cores 给 RDMA 轮询）。

---

## 候选方案总览

| 方案 | 参考来源 | 核心模型 | 优点 | 缺点 | 置信度 |
|------|----------|----------|------|------|--------|
| A: SPDK Reactor 原生 | SPDK Event Framework | 每 core 一个 reactor 线程，事件驱动 | SPDK 原生集成、无锁、C 语言、生产验证 | RDMA 通用语义支持弱、回调模型 | 高 |
| B: Seastar 协程 | Seastar / ScyllaDB | Reactor + C++20 coroutines | 协程模型先进、网络栈成熟 | C++ 无 C API、无 RDMA 支持、SPDK 集成困难 | 低 |
| C: DAOS ULT+tse | DAOS / Argobots | ULT + 任务依赖调度 | C 语言、SPDK 深度集成、ULT 轻量并发 | 架构复杂、学习曲线陡、可能过度设计 | 中 |
| D: SPDK + RDMA 线程混合 | InfiniStore 改进 | Reactor + 独立忙轮询线程 | 职责分离、RDMA 延迟最优、实现简单 | 跨线程开销、CPU 竞争、双调度域 | 中 |

---

## 方案量化对比矩阵

| 维度 | 方案 A: SPDK Reactor | 方案 B: Seastar | 方案 C: DAOS ULT+tse | 方案 D: 混合模型 |
|------|---------------------|-----------------|---------------------|-----------------|
| **参考来源** | SPDK Event Framework | Seastar / ScyllaDB | DAOS / Argobots | InfiniStore 改进 |
| **并发能力** | 高（每 core 一个 reactor）| 极高（协程调度）| 极高（ULT 数万/core）| 高（线程池规模受限）|
| **P99 延迟（NVMe）** | ~5μs | ~5μs + 适配层 | ~5μs | ~5μs |
| **P99 延迟（RDMA）** | ~10μs（事件驱动）| N/A（无 RDMA）| ~10μs | ~3μs（忙轮询）|
| **CPU 利用率** | 高（事件驱动，无空转）| 高 | 高（ULT 调度高效）| 中（RDMA 轮询占 100% CPU）|
| **SPDK 集成度** | 原生 | 需适配层 | 深度集成（bio 层）| 原生 |
| **RDMA 集成度** | 中（NVMe-oF 为主）| 无 | 中（需自行实现）| 高（原生 Verbs）|
| **实现复杂度** | 中 | 高（C++ 封装 + RDMA 适配）| 高（ULT + tse 学习曲线）| 中 |
| **NUMA 亲和性** | 内置（`spdk_env_init`）| 内置（per-core sharding）| 内置（hwloc 绑定）| 需手动绑定 |
| **C 语言适配成本** | 0 | 极高（需完整 C++ → C 层）| 0 | 0 |
| **团队学习成本** | 中（SPDK 事件模型）| 高（C++ + 协程）| 高（Argobots + tse）| 中 |
| **生产验证** | 强（SPDK NVMe-oF）| 强（ScyllaDB）| 强（DAOS 超算环境）| 弱（需自研）|
| **二进制体积** | 小 | 大（C++ 模板膨胀）| 中 | 小 |
| **编译时间** | 快 | 慢 | 中 | 快 |

---

## 关键 Trade-off

### 1. 编程模型：回调 vs 协程 vs ULT

- **回调（方案 A/D）**：SPDK 的事件回调模型在 C 语言中自然，但复杂异步流程（如"写入 = 检查存在性 → 分配内存 → RDMA READ → 插入索引 → 更新 LRU → 发送 ACK"）需要拆分为 6+ 个回调函数，代码可读性差
- **协程（方案 B）**：C++20 coroutines 让异步代码看起来像同步，但本系统要求 C 语言，无法直接使用
- **ULT（方案 C）**：Argobots 的 ULT 在 C 语言中提供类似协程的体验（`ABT_thread_yield`），但引入额外依赖和概念

**权衡结论**：本系统约束为 C 语言，协程不可用。在回调和 ULT 之间，回调模型虽然代码冗长，但概念简单、调试直接。可通过**状态机封装**（将复杂流程封装为状态机结构体）缓解回调地狱。

### 2. RDMA 延迟：事件驱动 vs 忙轮询

- **事件驱动（方案 A）**：通过 `ibv_get_cq_event` + epoll/uv_poll，有事件才唤醒。CPU 友好，但延迟增加 ~5μs（内核唤醒 + 事件分发）
- **忙轮询（方案 D）**：RDMA 线程 100% CPU 轮询 CQ，延迟最低（~1μs），但消耗 dedicating CPU core

**权衡结论**：4~16 节点规模下，每个节点有 32~64 core， dedicating 2~4 core 给 RDMA 轮询是可接受的。方案 D 的忙轮询在延迟上更优，但需要评估 CPU 资源是否充足。

### 3. 框架依赖：原生 vs 引入外部框架

- **方案 A/D**：依赖 SPDK（已确定使用），无额外框架依赖
- **方案 B**：引入 Seastar（C++ 框架）+ 需自行实现 RDMA 适配
- **方案 C**：引入 Argobots + tse + dRPC 全套 DAOS 基础设施

**权衡结论**：每引入一个外部框架，增加构建复杂度、调试难度、版本依赖风险。SPDK 已确定使用，方案 A/D 不引入新框架，风险最低。

### 4. 一致性 vs 性能：统一调度域 vs 分离调度域

- **统一调度（方案 A）**：所有事件在一个 reactor 循环中处理，无跨域同步，但 RDMA 和 NVMe 事件互相影响（一个慢事件阻塞其他事件）
- **分离调度（方案 D）**：RDMA 和 NVMe 各自独立，互不阻塞，但跨域通信引入延迟

**权衡结论**：KV Cache 场景中，RDMA 和 NVMe I/O 通常是 pipeline 关系（RDMA 接收数据 → NVMe 持久化），而非竞争关系。统一调度域不会成为瓶颈，除非单 core 上事件处理时间 > 10μs。

---

## 决策

选择 **方案 D（SPDK Reactor + 独立 RDMA 线程混合模型）作为目标架构，但第一阶段以方案 A（纯 SPDK Reactor）为 MVP 快速验证**。

### 决策理由

1. **RDMA 延迟是关键差异化指标**：本系统面向 KV Cache 场景，P/D 分离下 RDMA 传输延迟直接叠加到 TTFT。InfiniStore 的测试表明，事件驱动增加 ~5μs 延迟在高压下会累积成显著劣势。方案 D 的忙轮询可将 RDMA 延迟控制在 ~3μs。

2. **C 语言约束排除方案 B**：Seastar 无 C API，引入完整的 C++ → C 封装层成本极高（估计 3~6 人月），且 Seastar 无原生 RDMA 支持，需要额外开发 RDMA 适配层。

3. **DAOS 复杂度与目标规模不匹配**：DAOS 面向 Exascale（数千节点），其 ULT + tse + xstream 模型在 4~16 节点场景下是过度设计。学习 Argobots 和 tse 的曲线陡峭，收益有限。

4. **分阶段演进降低风险**：第一阶段用方案 A（纯 SPDK Reactor）快速验证核心功能（NVMe I/O + RDMA 基本通信），2~3 周内可运行。第二阶段在性能测试数据指导下，决定是否引入独立 RDMA 线程（方案 D）。

5. **SPDK 原生集成保障 NVMe 路径**：无论方案 A 还是 D，SPDK 的 NVMe I/O 路径都是原生调用，无适配层风险。

### 演进路线

```
Phase 1 (MVP): 方案 A — 纯 SPDK Reactor
  - 单 reactor 处理 NVMe + RDMA CQ（通过 poller）
  - 验证基本读写路径
  - 目标：2~3 周可运行

Phase 2 (优化): 方案 D — 混合模型
  - 若 Phase 1 性能测试显示 RDMA 延迟不满足 < 5μs 要求
  - 引入独立 RDMA 线程（每 NUMA 节点 1~2 个）
  - 通过 lock-free queue 与 SPDK reactor 通信
  - 目标：1~2 周增量开发

Phase 3 (扩展): 多 reactor 扩展
  - 每 NUMA 节点一个 reactor + RDMA 线程对
  - 支持多 NVMe SSD 和多 RDMA CQ 的并行处理
```

---

## 风险与缓解

| 风险 | 可能性 | 影响 | 缓解策略 |
|------|--------|------|----------|
| SPDK Reactor 与 RDMA CQ 轮询冲突，导致事件饥饿 | 中 | 高 | Phase 1 原型中测量 reactor 循环单次迭代时间，若 > 10μs 则触发 Phase 2 |
| 独立 RDMA 线程的忙轮询导致 CPU 资源不足 | 中 | 中 | 4~16 节点场景下每节点 dedicating 2 core（占总 core 的 3~6%）是可接受的；预留动态降级到事件驱动的能力 |
| 跨线程（RDMA → SPDK）消息队列成为瓶颈 | 低 | 高 | 使用 `rte_ring`（无锁、批量出队），单队列可达 10M+ ops/s；每 core pair 一个队列避免竞争 |
| 回调模型导致复杂流程代码难以维护 | 中 | 中 | 定义统一的状态机框架（`struct async_op { state; callback; ctx; }`），将复杂流程封装为状态转换表 |
| Argobots/ULT 团队经验不足（若后期转向方案 C）| 低 | 中 | 决策已排除方案 C，但若后期需要 ULT，提前安排 1 人学习 Argobots（1~2 周） |
| SPDK RDMA 库仅支持 NVMe-oF，不支持通用 RDMA | 高 | 高 | 本决策假设使用原生 libibverbs 处理 RDMA，而非 SPDK RDMA 库。需在 Phase 1 验证 libibverbs + SPDK reactor 的兼容性 |

---

## 待验证假设

| # | 假设 | 验证方法 | 不成立的后果 |
|---|------|---------|------------|
| H1 | SPDK reactor 的 poller 模型可以高效处理 RDMA CQ 事件（延迟 < 10μs）| Phase 1 原型：测量 `ibv_poll_cq` 在 poller 中的平均处理时间 | 退化为方案 D（独立 RDMA 线程） |
| H2 | libibverbs 的 `comp_channel` fd 可以安全地注册到 SPDK 的 poller 中 | Phase 1 原型：验证 `spdk_poller_register` + `ibv_get_cq_event` 的兼容性 | 需要改用忙轮询或独立线程 |
| H3 | 单 reactor 在 1000+ 并发 RDMA 连接下不会成为瓶颈 | Phase 1 压测：模拟 1000 连接，测量 reactor 循环迭代时间和事件队列深度 | 需要多 reactor 分片 |
| H4 | 跨线程 lock-free queue（RDMA thread → SPDK reactor）延迟 < 2μs | Phase 2 原型：使用 `rte_ring` 测量端到端延迟 | 需要优化队列设计或改用共享内存 |
| H5 | 忙轮询 RDMA CQ 的 CPU 开销在可接受范围内（< 5% 总 CPU）| Phase 2 压测：测量 RDMA 线程的 CPU 利用率 vs 吞吐 | 需要动态切换（低负载时事件驱动，高负载时忙轮询） |

---

## 替代方案排除理由

- **方案 B（Seastar）**：
  - 排除理由 1：纯 C++ 框架，无 C API。本系统约束为 C 语言，需要完整的 C++ → C 封装层，估计 3~6 人月
  - 排除理由 2：Seastar 网络栈基于 DPDK/Posix socket，无原生 RDMA（libibverbs）支持。自行实现 RDMA 适配层工作量巨大
  - 排除理由 3：SPDK 与 Seastar 的集成无社区成熟方案，需要自定义适配层（将 SPDK 事件映射到 Seastar future）

- **方案 C（DAOS ULT+tse）**：
  - 排除理由 1：架构复杂度过高。DAOS 的线程模型（xstream、ULT、tse、sched）概念多，`srv.c` 超过 1000 行仅做线程启动
  - 排除理由 2：目标规模不匹配。DAOS 面向 Exascale（数千节点），本系统 4~16 节点，部分设计（SWIM、多 tier）是过度设计
  - 排除理由 3：引入 Argobots 作为额外依赖，增加构建复杂度和调试难度

---

## Reviewer 质疑与回应

> 待 architect-reviewer 质疑后补充

---

## 架构师自检清单

- [x] 至少对比了 3 个候选方案，每个都有明确的参考来源和优缺点分析
- [x] 关键 Trade-off 已识别并量化分析（编程模型、RDMA 延迟、框架依赖、调度域）
- [x] 决策有明确的数据或逻辑支撑，非主观偏好
- [x] 风险矩阵完整，至少包含 1 个高影响风险和缓解策略
- [x] 替代方案排除理由充分（量化理由优先）
- [x] 待验证假设已明确列出（5 个），含验证方法和不成立的后果
- [x] 提供了分阶段演进路线，降低实施风险
