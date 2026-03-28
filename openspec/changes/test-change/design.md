## Context

当前存储系统采用传统的数据节点架构：计算节点将 I/O 请求通过 RPC 发送到数据节点，数据节点在用户态完成对象→块的映射后访问本地 NVMe 盘。随着 NVMe 介质延迟降至 10-15μs 级别，用户态存储栈的软件开销（~100μs）成为性能瓶颈。

VAST Data 的 DNode 架构已验证了 NVMe-oF 直通模式的可行性：数据节点仅负责 NVMe-oF Target 管理和空间分配，数据面 I/O 由计算节点通过 NVMe-oF 直接访问远端 NVMe 命名空间。

**约束**：
- 内核 NVMe-oF 子系统成熟度高，优先使用内核态 nvmet 而非用户态实现（如 SPDK）
- 传输层需支持 RDMA（高性能场景）和 TCP（通用场景）
- DNode 管理面使用 C 语言实现，与现有系统风格一致

**利益相关方**：存储团队（DNode 开发）、计算节点团队（Initiator 集成）、元数据团队（extent 分配协议）

## Goals / Non-Goals

**Goals:**
- 实现 DNode 服务进程，管理本地 NVMe 盘的 NVMe-oF Target 暴露
- 实现计算节点侧 NVMe-oF Initiator 连接管理（discovery/connect/disconnect/reconnect）
- 实现元数据服务与 DNode 之间的 extent 粒度容量分配协议
- 4K 随机读延迟降至 30μs 以内

**Non-Goals:**
- 不实现用户态 NVMe-oF Target（如基于 SPDK 的实现），本阶段使用内核 nvmet
- 不改变元数据服务的元数据存储方式
- 不实现多路径（multipath）I/O，留待后续迭代
- 不实现数据加密和压缩卸载，本阶段聚焦基础数据通路

## Decisions

### Decision 1: NVMe-oF Target 实现方式

**备选方案**：

| 维度 | 方案 A：内核 nvmet | 方案 B：SPDK nvmf_tgt |
|------|-------------------|----------------------|
| 复杂度 | 低，通过 configfs 配置 | 高，需管理 hugepage、CPU 绑核、用户态驱动 |
| 性能影响 | 良好，内核零拷贝路径成熟 | 极致，绕过内核，延迟更低 ~5μs |
| 可维护性 | 高，随内核升级自动获得修复 | 低，需跟踪 SPDK 版本，API 变更频繁 |
| 与现有代码一致性 | 一致，现有系统基于内核态 I/O 栈 | 不一致，需引入全新的用户态 I/O 框架 |

**结论**：选择方案 A（内核 nvmet），因为复杂度低、可维护性好、与现有系统一致。nvmet 在主流内核版本（5.x+）中已稳定，满足 30μs 延迟目标。SPDK 方案的额外 ~5μs 优势不足以弥补其维护成本。

### Decision 2: 传输层协议选择

**备选方案**：

| 维度 | 方案 A：仅 RDMA | 方案 B：RDMA + TCP 双栈 |
|------|----------------|------------------------|
| 复杂度 | 低，单一传输路径 | 中等，需抽象传输层接口 |
| 性能影响 | 最优，RDMA 延迟 ~5μs | RDMA 路径同等，TCP 路径延迟 ~30-50μs |
| 可维护性 | 简单 | 需维护两套配置 |
| 与现有代码一致性 | 部分一致，现有 RPC 有 RDMA 支持 | 更灵活，兼容无 RDMA 网卡的测试环境 |

**结论**：选择方案 B（RDMA + TCP 双栈），因为 TCP 传输可在开发/测试环境中使用（无需 RDMA 网卡），降低开发门槛。nvmet 内核模块原生支持两种传输，无需额外开发。

### Decision 3: 空间分配粒度

**备选方案**：

| 维度 | 方案 A：固定大小 extent（如 64MB） | 方案 B：可变大小 extent |
|------|----------------------------------|----------------------|
| 复杂度 | 低，分配/回收逻辑简单，位图即可管理 | 高，需 B+ 树或类似结构管理碎片 |
| 性能影响 | 可能有内部碎片，但分配速度快 | 空间利用率高，但分配延迟不确定 |
| 可维护性 | 高，状态简单易调试 | 低，碎片整理逻辑复杂 |
| 与现有代码一致性 | 一致，现有块分配器使用固定粒度 | 不一致 |

**结论**：选择方案 A（固定 64MB extent），因为与现有块分配器一致、实现简单、分配延迟可预测。64MB 粒度下，单块 4TB NVMe 盘仅需 ~64K 个 extent，位图管理开销极小。

## Risks / Trade-offs

- **[内核 nvmet 功能限制]** → 通过内核版本基线要求（≥5.15）确保所需特性可用，CI 中加入内核版本检查 → 残余风险：特定发行版内核可能回移不完整
- **[NVMe-oF 连接中断导致 I/O 挂起]** → Initiator 侧实现超时检测 + 自动重连，DNode 侧维护连接状态心跳 → 残余风险：重连期间的 I/O 需上层重试或缓存
- **[extent 分配与回收的一致性]** → 使用两阶段提交：元数据服务先预留 → DNode 确认 → 元数据服务提交。回收时先标记删除 → DNode 确认无活跃 I/O → 元数据服务物理回收 → 残余风险：崩溃恢复时需扫描未完成事务
- **[64MB extent 内部碎片]** → 对于小文件场景（<1MB），多个小文件共享同一 extent 内的子区域，由元数据服务管理子分配 → 残余风险：子分配增加元数据复杂度

## Migration Plan

1. **阶段一（并行部署）**：DNode 与现有数据节点并行运行，新创建的数据卷可选择 NVMe-oF 直通模式或传统模式
2. **阶段二（灰度切换）**：按集群维度将部分数据卷迁移到 NVMe-oF 直通模式，监控性能和稳定性
3. **阶段三（全量切换）**：所有新卷默认使用 NVMe-oF 直通模式
4. **回滚策略**：每个阶段保留回退到传统模式的能力——DNode 停止 NVMe-oF Target 暴露后，数据节点可重新接管本地 NVMe 盘

## Open Questions

- NVMe namespace 的动态创建/销毁是否需要内核热插拔支持，还是通过 configfs 接口即可完成？
- 多租户场景下，是否需要 NVMe namespace 级别的 QoS 隔离（如 IO 带宽限制）？
- extent 分配的两阶段提交在 DNode 崩溃恢复时的具体日志格式？

## 架构追溯

- 关联架构文档：不适用：DNode 是全新子系统，当前无对应架构文档。后续应在 docs/architecture/ 下新建 dnode-architecture.md

## 接口变更

### 接口: DNode extent 分配 RPC

- 变更类型：新增
- 函数签名：
  ```c
  /* 元数据服务 → DNode：分配 extent */
  int dnode_extent_alloc(uint64_t dnode_id, uint32_t namespace_id,
                         uint64_t extent_offset, uint64_t extent_size,
                         struct extent_handle *out_handle);

  /* 元数据服务 → DNode：回收 extent */
  int dnode_extent_free(uint64_t dnode_id, struct extent_handle *handle);
  ```
- 数据结构：
  ```c
  struct extent_handle {
      uint64_t dnode_id;
      uint32_t namespace_id;
      uint64_t offset;      /* namespace 内偏移 */
      uint64_t size;         /* extent 大小，固定 64MB */
      uint64_t generation;   /* 分配代次，用于崩溃恢复 */
  };
  ```
- 兼容性：新增接口，不影响已有系统。破坏性变更风险：无

### 接口: DNode 状态上报 RPC

- 变更类型：新增
- 函数签名：
  ```c
  /* DNode → 元数据服务：定期上报容量和健康状态 */
  int dnode_heartbeat(uint64_t dnode_id, struct dnode_status *status);
  ```
- 数据结构：
  ```c
  struct dnode_status {
      uint32_t num_namespaces;
      uint64_t total_capacity;
      uint64_t free_capacity;
      uint32_t active_connections;  /* 当前活跃的 NVMe-oF 连接数 */
      uint8_t  health;             /* 0=healthy, 1=degraded, 2=failed */
  };
  ```
- 兼容性：新增接口，不影响已有系统
