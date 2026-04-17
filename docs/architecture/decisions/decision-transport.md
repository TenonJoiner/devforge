# 架构探索笔记：数据传输与 IO 路径

**探索日期**: 2026-04-09  
**当前轮次**: 第 2 轮（方案发散）→ Step 3  
**关联维度**: 维度 4 — 数据传输与 IO 路径  
**置信度**: 中（75%）  

---

## 探索目标

针对 KV 数据在 GPU/CPU/SSD/网络间如何高效搬运这一问题，基于 [research-transport.md](research-transport.md) 的深度调研结果，提炼并对比以下候选方案。

---
**调研日期**：2026-04-09
**关联文档**：[exploration-dimensions.md](../exploration-dimensions.md)（维度 4）
**调研范围**：KVCache Offloading 场景下 GPU/CPU/SSD/网络间数据搬运的 4 条候选路径

---

## 目录

1. [全景对比矩阵](#全景对比矩阵)
2. [方案 1：传统 cudaMemcpy + pread/pwrite（基线）](#方案-1传统-cudamemcpy--preadpwrite基线)
3. [方案 2：GPUDirect Storage（GPU 直访 NVMe）](#方案-2gpudirect-storagegpu-直访-nvme)
4. [方案 3：RDMA + GPUDirect RDMA（远端内存直接访问）](#方案-3rdma--gpudirect-rdma远端内存直接访问)
5. [方案 4：批量流水线（overlap 计算与传输）](#方案-4批量流水线overlap-计算与传输)
6. [跨方案 Trade-off 总表](#跨方案-trade-off-总表)
7. [组合策略分析](#组合策略分析)

---

## 全景对比矩阵

| 维度 | 方案 1：cudaMemcpy+pread | 方案 2：GPUDirect Storage | 方案 3：RDMA+GDR | 方案 4：批量流水线 |
|------|--------------------------|--------------------------|-------------------|-------------------|
| **数据路径** | GPU->CPU DRAM->SSD | GPU->NVMe（绕过 CPU） | GPU->NIC->远端 GPU/DRAM | 多路径时间重叠 |
| **CPU 参与** | 必须（bounce buffer） | 不需要（DMA 直通） | 不需要（零拷贝） | 取决于底层路径 |
| **理论峰值带宽** | ~26 GB/s（PCIe4 x16） | ~84 GB/s（多盘聚合） | ~50 GB/s（8x400Gbps） | 接近各路径理论值 |
| **单次传输延迟** | 10-20 us（小块） | ~1 ms（NVMe设备延迟） | 1-2 us（RDMA write） | 被计算时间掩盖 |
| **硬件依赖** | 无特殊要求 | NVIDIA GPU + GDS驱动 | IB/RoCE NIC + RDMA | 无特殊要求 |
| **部署复杂度** | 低 | 中 | 高 | 中 |
| **业界代表** | LMCache、vLLM swap | LMCache GDS后端 | MoonCake Messenger | MoonCake CPP、LMCache layer-wise |

---

## 方案 1：传统 cudaMemcpy + pread/pwrite（基线）

### 1. 问题背景与必要性

**解决什么问题**：GPU 显存容量有限（H100 SXM 80GB），长上下文 KV Cache 可达数十 GB，必须将部分 KV 数据卸载到 CPU DRAM 或 SSD。cudaMemcpy 是 CUDA 提供的标准 GPU-CPU 数据搬运原语，pread/pwrite 是 Linux 标准的文件系统同步读写接口。

**不解决的后果**：GPU 显存被 KV Cache 占满后，要么拒绝新请求（吞吐归零），要么强制淘汰缓存（命中率崩塌，TTFT 回退到全量 Prefill）。

**必选还是优化**：**必选**。这是最基础的数据搬运路径，所有其他方案均以此为基线。

**替代方案**：无直接替代——方案 2/3 是对此路径的**硬件加速**，方案 4 是对此路径的**时间优化**。

### 2. 核心原理

#### 数据路径

```
GPU HBM  ──cudaMemcpy──>  CPU DRAM (Pinned)  ──pread/pwrite──>  NVMe SSD
  |                            |
  |<──cudaMemcpyAsync──        |<──mmap/read──
  |   (非阻塞，需同步)          |   (阻塞或AIO)
```

**关键机制**：
- **cudaMemcpy（同步）**：阻塞调用线程，GPU DMA 引擎将数据从 HBM 搬运到 CPU 的 pinned memory，通过 PCIe 总线传输
- **cudaMemcpyAsync（异步）**：提交到 CUDA stream，不阻塞 host 线程，但需要显式同步（cudaStreamSynchronize）确认完成
- **Pinned Memory（页锁定内存）**：cudaHostAlloc 分配的不可换页内存，避免 OS 页表映射变更导致 DMA 失败。未 pin 的内存带宽仅为 pinned 的 50%
- **pread/pwrite**：POSIX 标准接口，经过 VFS->文件系统->块层->NVMe 驱动的完整内核 IO 栈

#### 理论复杂度

- **时间复杂度**：O(N)，N 为传输数据量；总延迟 = PCIe 传输时间 + SSD IO 延迟
- **空间复杂度**：O(N) 额外空间——CPU DRAM 中必须分配等大的 bounce buffer

### 3. 设计机制

#### 系统架构和组件划分

以 vLLM 的 swap 机制为例：

```
┌─────────────────────────────────────────────────┐
│                vLLM Scheduler                    │
│   决定哪些 sequence 需要 swap out/in            │
└────────────────────┬────────────────────────────┘
                     │ 发出 swap 指令
                     ▼
┌─────────────────────────────────────────────────┐
│              Cache Engine                        │
│   管理 GPU block 和 CPU block 的映射关系        │
│   ┌──────────────────────────────────────────┐  │
│   │  GPU Block Allocator  ←→  CPU Block Pool │  │
│   └──────────────────────────────────────────┘  │
└────────────────────┬────────────────────────────┘
                     │ cudaMemcpyAsync
                     ▼
┌─────────────────────────────────────────────────┐
│            CUDA DMA Engine (PCIe)                │
│   Host Pinned Memory ←→ Device Memory           │
└─────────────────────────────────────────────────┘
```

以 LMCache 的 SSD 后端为例：

```
┌──────────────────────────────────────────────────┐
│            LMCache Storage Manager               │
│   chunk 级别的 save/load 调度                    │
└────────────────────┬─────────────────────────────┘
                     │
        ┌────────────┼────────────┐
        ▼            ▼            ▼
  GPU→CPU DRAM    CPU DRAM     CPU DRAM→SSD
  (cudaMemcpy)   (序列化)     (pwrite/io_uring)
```

#### 数据流

**写入路径（GPU -> SSD）**：
1. Scheduler 决定淘汰某些 KV blocks
2. cudaMemcpyAsync 将 GPU block 拷贝到 CPU pinned buffer
3. （可选）序列化/压缩
4. pwrite 或 io_uring 写入 NVMe SSD
5. 更新 block 位置索引（GPU->SSD）

**读取路径（SSD -> GPU）**：
1. Scheduler 决定加载某些 KV blocks
2. pread 或 io_uring 从 SSD 读取到 CPU buffer
3. （可选）反序列化/解压
4. cudaMemcpyAsync 拷贝到 GPU block
5. 更新 block 位置索引（SSD->GPU）

#### 关键接口抽象

LMCache 的 Connector 接口将这一路径封装为：
- `start_load_kv()` / `wait_load_kv()`：异步 load 语义
- `start_store_kv()` / `wait_store_kv()`：异步 store 语义
- `save_kv_layer()` / `wait_for_layer_load()`：layer-wise 粒度控制

### 4. 架构决策分析

| 决策点 | 可选方案 | 选择 | 理由 | Trade-off |
|--------|---------|------|------|-----------|
| **内存类型** | Pinned vs Pageable | Pinned | Pageable 带宽仅 ~12 GB/s，Pinned 可达 ~26 GB/s（PCIe4） | Pinned 内存不可换页，占用物理内存上限 |
| **同步模型** | 同步 vs 异步 | 异步（cudaMemcpyAsync） | 同步阻塞推理线程，异步允许计算-传输重叠 | 异步增加编程复杂度，需管理多 stream |
| **SSD IO 接口** | pread/pwrite vs io_uring vs SPDK | io_uring（推荐） | pread 阻塞线程；SPDK 需独占 NVMe 设备；io_uring 兼顾异步与内核兼容 | io_uring 需 Linux 5.1+，某些内核版本有 bug |
| **传输粒度** | Block 级（16 tokens）vs Chunk 级（256 tokens） | Chunk 级 | 小块传输被 PCIe 启动延迟主导（10-20 us/次），大块摊薄固定开销 | 大 chunk 增加粒度不匹配风险 |

### 5. 性能剖析

#### 量化数据

| 路径 | 带宽 | 延迟 | 测试条件 |
|------|------|------|----------|
| GPU->CPU（Pinned，PCIe 4.0 x16） | ~26 GB/s | 10-20 us（小块）、<1ms（1MB+） | A100/H100 PCIe，cudaMemcpy bandwidth test |
| GPU->CPU（Pinned，PCIe 5.0 x16） | ~50 GB/s | 同上 | H100 SXM via PCIe Gen5 |
| GPU->CPU（Pageable，PCIe 4.0） | ~12 GB/s | ~2x Pinned | 非 pinned host memory |
| CPU->SSD（pread，单盘 NVMe PCIe4） | ~7 GB/s seq read | 15 us（4K），~100 us（128K） | Samsung PM9A3，ext4 |
| CPU->SSD（io_uring，单盘） | ~7 GB/s（+20-30% vs pread） | 同上 | io_uring + IOPOLL，Linux 6.x |
| CPU->SSD（多盘 RAID） | ~28 GB/s | 同上 | 4x NVMe RAID0 |
| **端到端 GPU->SSD** | **~5-7 GB/s**（受限于串行两跳） | **~0.1-1 ms** | 典型 KV Cache 写入 |

**LMCache 实测数据**（论文 Table 1，Chunk 传输带宽 vs Chunk 大小）：

| Chunk 大小 | CPU Offload 带宽 |
|-----------|-----------------|
| 64 KB | 4 GB/s |
| 256 KB | 13 GB/s |
| 1 MB | 30 GB/s |
| 10 MB | 46 GB/s |
| 16 MB | 49 GB/s |

**关键发现**：LMCache 实测 CPU offload 带宽 400 Gbps（~50 GB/s），而 vLLM 原生 CPU offload 仅 88 Gbps（~11 GB/s），差距来自 LMCache 的 batching 优化和 pinned memory 管理。

#### 性能瓶颈

1. **PCIe 带宽天花板**：GPU-CPU 单方向最大 ~26 GB/s（Gen4）或 ~50 GB/s（Gen5），且与其他 PCIe 设备共享
2. **两次拷贝开销**：数据经 CPU DRAM 中转，GPU->SSD 实际带宽 = min(PCIe BW, SSD BW) 的一半（因为两跳串行）
3. **小块传输效率低**：<64KB 的传输被 DMA 启动延迟主导（10-20 us），有效带宽仅 ~4 GB/s
4. **CPU 占用**：虽然 DMA 不消耗 CPU 计算，但 pread/pwrite 的内核栈处理、页表管理、中断处理消耗 CPU 资源

### 6. Trade-off 与限制

| 维度 | 选择 A | 选择 B | 取舍分析 | 本方案选择 |
|------|--------|--------|----------|-----------|
| **时间 vs 空间** | 零额外内存，同步传输 | 分配 pinned buffer，异步传输 | Pinned buffer 占用 CPU 物理内存但带宽翻倍 | 选 B，pinned+async |
| **一致性 vs 性能** | 同步写保证数据落盘 | 异步写可能丢数据 | KV Cache 可重算，丢失可容忍 | 选 B，异步写 |
| **复杂度 vs 收益** | 简单 pread/pwrite | io_uring 异步 IO | io_uring 可提升 20-30% 吞吐但需更高内核版本 | 取决于内核版本 |
| **通用性 vs 专用性** | POSIX 标准接口，全平台通用 | CUDA 专用 API | 通用性最高，但性能最低 | 适合初始版本和回退路径 |

**适用场景边界**：
- **适合**：原型开发、预算敏感环境、无特殊硬件的通用 GPU 服务器、小规模部署（<10 节点）
- **不适合**：延迟敏感型应用（端到端 GPU->SSD 延迟 ~1ms，对比 RDMA 的 ~2us）、大规模高吞吐场景

---

## 方案 2：GPUDirect Storage（GPU 直访 NVMe）

### 1. 问题背景与必要性

**解决什么问题**：消除方案 1 中的 CPU DRAM bounce buffer，实现 GPU HBM 与 NVMe SSD 之间的直接 DMA 传输，避免两次拷贝。

**不解决的后果**：GPU->SSD 路径被 CPU 内存带宽和两次拷贝串行延迟限制在 ~5-7 GB/s，远低于 PCIe 理论带宽。

**必选还是优化**：**优化**。功能上 cudaMemcpy+pread 完全可用，GDS 是性能优化手段。

**替代方案**：
- 方案 1（cudaMemcpy+pread）：功能等价，性能低 3.5-4.6x
- SPDK（用户态 NVMe 驱动）：更低延迟但需独占 NVMe 设备，无法与文件系统共存

### 2. 核心原理

#### 数据路径

```
传统路径（方案 1）：
GPU HBM ──PCIe──> CPU DRAM (bounce) ──PCIe──> NVMe SSD
         26 GB/s                      7 GB/s
         两次 PCIe 传输，CPU 参与

GDS 路径（方案 2）：
GPU HBM ──PCIe──> NVMe SSD（直接 DMA）
         同一 PCIe fabric，无 bounce buffer
```

**核心机制**：
- **PCIe Peer-to-Peer DMA**：NVMe 控制器的 DMA 引擎直接读写 GPU BAR（Base Address Register）映射的 HBM 地址空间，数据在 PCIe fabric 上直接从 NVMe 流向 GPU，不经过 CPU 的 Root Complex
- **cuFile API**：NVIDIA 提供的用户态 API，替代 pread/pwrite。cuFileRead/cuFileWrite 内部走 nvidia-fs 内核模块，绕过标准 VFS 路径
- **GPU BAR 映射**：GPU 的 HBM 被映射为 PCIe BAR 空间，NVMe 控制器可直接对其发起 DMA。需要 GPU 支持大 BAR（Large BAR / Resizable BAR）

#### 理论复杂度

- **时间复杂度**：O(N)，但常数项降低——消除了 CPU DRAM 中转的一次 PCIe 传输
- **空间复杂度**：O(1) 额外空间——无需 CPU bounce buffer

### 3. 设计机制

#### 系统架构

```
┌─────────────────────────────────────────────────────┐
│                Application                           │
│   cuFileRead(buf_gpu, file, offset, size)           │
└────────────────────┬────────────────────────────────┘
                     │ cuFile API
                     ▼
┌─────────────────────────────────────────────────────┐
│              nvidia-fs Kernel Module                  │
│   管理 GPU BAR 映射、DMA 路由                        │
│   NUMA-aware path selection                          │
└────────────────────┬────────────────────────────────┘
                     │ PCIe P2P DMA
                     ▼
┌──────────┐    PCIe Fabric    ┌──────────┐
│  GPU     │◄──────────────────│  NVMe    │
│  HBM     │   直接 DMA 传输    │  SSD     │
└──────────┘                   └──────────┘
```

#### 关键设计机制

1. **NUMA 拓扑感知**：GDS 性能高度依赖 GPU 和 NVMe SSD 的 PCIe 拓扑关系。同一 PCIe switch 下的 GPU-NVMe 对性能最优；跨 NUMA 节点传输性能大幅下降
2. **多盘聚合**：单盘 NVMe ~7 GB/s（PCIe4 x4），多盘可线性扩展至 PCIe 带宽上限（~26 GB/s for Gen4 x16 per GPU）
3. **兼容模式**：当硬件不支持 P2P DMA 时，GDS 自动回退到 bounce buffer 模式（性能退化为方案 1）

#### 数据流

**GDS 写入路径**：
1. 应用调用 `cuFileWrite(gpu_buf, fd, offset, size)`
2. nvidia-fs 模块获取 GPU buffer 的 PCIe BAR 地址
3. 向 NVMe 控制器提交 DMA 读命令，源地址 = GPU BAR
4. NVMe DMA 引擎直接从 GPU HBM 读取数据
5. 数据落盘，返回完成状态

### 4. 架构决策分析

| 决策点 | 可选方案 | 选择 | 理由 | Trade-off |
|--------|---------|------|------|-----------|
| **IO 接口** | cuFile（GDS）vs SPDK | cuFile | SPDK 需独占 NVMe，无法与文件系统共存 | cuFile 经过内核，延迟略高于 SPDK |
| **缓冲策略** | 直通 vs GPU 侧缓冲 | 直通 | KV Cache 是大块顺序写入，无需额外缓冲 | 小块随机 IO 场景可能需要合并 |
| **文件系统** | ext4 vs XFS vs 裸设备 | ext4/XFS | 裸设备管理复杂，文件系统元数据开销可接受 | GDS+ext4 性能已接近裸设备 |

### 5. 性能剖析

#### 量化数据

| 配置 | 带宽（GDS） | 带宽（基线，bounce buffer） | 加速比 | 测试条件 |
|------|------------|--------------------------|--------|----------|
| 2x NVMe + A100 PCIe | 8 GB/s | ~3.4 GB/s | 2.3x | NVIDIA 官方 benchmark，PCIe Gen4 |
| 10x NVMe + A100 PCIe | 26 GB/s | — | 接近 PCIe Gen4 x16 上限 | Western Digital Data24 3200 |
| 多盘 + H100 SXM | 84 GB/s（持续）、90 GB/s（峰值） | 15.5 GB/s | **4.6x** | Western Digital Data24 4000，PCIe Gen5 |
| OCI 集群（8x A100 + 4x NVMe/node） | 3.5x 带宽提升 | 基线 | 3.5x | IBM Storage Scale + GDS |

**延迟数据**：
- 单次 NVMe 设备 IO 延迟：~1 ms（NVIDIA 官方 benchmark）
- GDS 消除了 CPU bounce 的额外延迟，但 NVMe 设备本身延迟不变

**CPU 占用**：
- GDS 工作负载下 CPU 占用显著低于 bounce buffer 模式
- 同时降低约 7W 服务器功耗（Solidigm 测试，100 次循环稳定）

#### 性能瓶颈

1. **NVMe 设备带宽**：单盘 ~7 GB/s（PCIe4 x4），多盘需要聚合才能匹配 GPU PCIe 通道带宽
2. **PCIe 拓扑**：GPU 和 NVMe 不在同一 PCIe switch 时性能退化严重
3. **PCIe 带宽共享**：GDS 传输与推理通信（如 tensor parallel AllReduce）争抢 PCIe 带宽

### 6. Trade-off 与限制

| 维度 | 选择 A（GDS） | 选择 B（cudaMemcpy+pread） | 取舍分析 | GDS 选择 |
|------|-------------|--------------------------|----------|---------|
| **时间 vs 空间** | 无 bounce buffer，省 CPU DRAM | 需 bounce buffer | GDS 同时省时间和空间 | 双赢 |
| **一致性 vs 性能** | 数据直接落盘，一致性同 pwrite | 同 | 无差异 | 无差异 |
| **复杂度 vs 收益** | 需 GDS 驱动、NUMA 配置 | 开箱即用 | 3.5-4.6x 带宽提升，值得复杂度投入 | 值得 |
| **通用性 vs 专用性** | 仅 NVIDIA GPU + 特定 NVMe 拓扑 | 全平台 | 硬件锁定，但 NVIDIA GPU 在 AI 推理中占主导 | 可接受 |

**硬件依赖**：
- NVIDIA GPU（Volta 及以上，推荐 Ampere/Hopper）
- nvidia-fs 内核模块（CUDA 12.x 包含）
- NVMe SSD 支持 CMB（Controller Memory Buffer）或 P2P DMA
- PCIe 拓扑满足 NUMA 亲和性要求

**部署约束**：
- 支持：主流云厂商 GPU 实例（AWS p4/p5、GCP a2/a3、Azure ND）
- 不支持：AMD GPU 环境、非 NVIDIA 加速器、PCIe 拓扑不满足 P2P 要求的服务器

**适用场景边界**：
- **适合**：SSD 作为主要 offload 层的场景、本地 cache 密集型工作负载、无 RDMA 网络的环境
- **不适合**：远端存储为主的架构（此时瓶颈在网络而非 SSD）、GPU/NVMe 拓扑不佳的服务器

---

## 方案 3：RDMA + GPUDirect RDMA（远端内存直接访问）

### 1. 问题背景与必要性

**解决什么问题**：实现跨节点的 KV Cache 传输——Prefill 节点生成的 KV Cache 需要搬运到 Decode 节点，或从远端 KV Pool 拉取共享 cache。传统 TCP 路径延迟 ~20-100 us、带宽受限于协议栈开销；RDMA 提供 ~1 us 延迟、线速带宽的零拷贝网络传输。

**不解决的后果**：
- PD 分离架构无法工作——Prefill 到 Decode 的 KV 传输成为延迟瓶颈
- Prefix Cache 无法跨实例共享——每个实例独立 prefill，计算浪费
- MoonCake 论文报告：TCP 传输下 TTFT 比 RDMA 高 25%

**必选还是优化**：
- **分离式架构（MoonCake 风格）**：**必选**，RDMA 是核心传输路径
- **本地分层架构（LMCache 风格）**：**优化**，仅远端存储后端需要

### 2. 核心原理

#### 数据路径

```
方案 A：标准 RDMA（CPU 中转）
Remote CPU DRAM ──RDMA──> Local CPU DRAM ──cudaMemcpy──> Local GPU HBM
                ~1-2 us                    10-20 us

方案 B：GPUDirect RDMA（零拷贝）
Remote GPU HBM ──GDR+RDMA──> Local GPU HBM（直接 NIC->GPU DMA）
                  ~1.9 us（端到端）

方案 C：标准 RDMA + SSD 后端
Remote SSD ──NVMe-oF/RDMA──> Local CPU DRAM ──cudaMemcpy──> Local GPU HBM
```

**核心机制**：
- **RDMA（Remote Direct Memory Access）**：NIC 直接对远端内存发起 DMA 读写，绕过双方的 CPU 和内核协议栈。支持三种操作：RDMA Write（推送）、RDMA Read（拉取）、Send/Recv（双边）
- **GPUDirect RDMA (GDR)**：在 RDMA 基础上，允许 NIC 的 DMA 引擎直接访问 GPU 的 BAR 空间，数据路径为 NIC->PCIe->GPU HBM，完全绕过 CPU DRAM
- **InfiniBand Virtual Lanes (VL)**：在同一物理网络上隔离不同流量类。DualPath 论文的设计：高优先级 VL 分配 ~99% 带宽给推理通信（AllReduce/AllToAll），低优先级 VL 分配剩余带宽给 KV Cache 传输

#### 理论复杂度

- **时间复杂度**：O(N)，传输延迟 = 固定启动延迟（~1 us） + 数据量/带宽
- **空间复杂度**：
  - 标准 RDMA：O(N)——本地需要接收 buffer
  - GPUDirect RDMA：O(1)——直接写入目标 GPU HBM

### 3. 设计机制

#### 系统架构（以 MoonCake Messenger 为例）

```
┌─────────────────────────────────────────────────────────┐
│                  MoonCake Transfer Engine                 │
│  ┌───────────────────────────────────────────────────┐  │
│  │            Unified Transfer API                    │  │
│  │   submitTransfer(src, dst, size, protocol)        │  │
│  └────────────────────┬──────────────────────────────┘  │
│                       │                                  │
│  ┌────────────────────┼────────────────────────────┐    │
│  │    Protocol Backends                             │    │
│  │  ┌──────┐ ┌──────┐ ┌───────┐ ┌──────┐ ┌─────┐ │    │
│  │  │ RDMA │ │ TCP  │ │NVMe-oF│ │NVLink│ │ CXL │ │    │
│  │  └──────┘ └──────┘ └───────┘ └──────┘ └─────┘ │    │
│  └─────────────────────────────────────────────────┘    │
│                                                          │
│  ┌─────────────────────────────────────────────────┐    │
│  │     Topology-Aware Path Selection                │    │
│  │   - NIC "preferred" / "secondary" 分类           │    │
│  │   - NUMA 亲和性优化                              │    │
│  │   - 多 NIC 带宽聚合                              │    │
│  └─────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────┘
```

#### 关键设计机制

1. **拓扑感知路径选择**：每个节点启动时生成拓扑矩阵，记录 GPU-NIC 之间的 PCIe 距离。RDMA 传输优先选择与目标 GPU 在同一 PCIe switch 下的 NIC（"preferred" NIC），避免跨 NUMA 传输

2. **多 NIC 带宽聚合**：MoonCake 支持 4x200Gbps（87 GB/s）或 8x400Gbps（190 GB/s）的多网卡聚合。单次大块传输被拆分到多个 NIC 并行发送

3. **DualPath 双路径加载**（DualPath 论文，DeepSeek-AI）：
   - 传统路径：存储 -> Prefill Engine 的 SNIC
   - 新增路径：存储 -> Decode Engine 的 SNIC -> RDMA -> Prefill Engine 的 CNIC
   - 利用 Decode 节点闲置的存储网络带宽，解决 Prefill 节点 SNIC 饱和问题

4. **流量隔离**：InfiniBand VL（Virtual Lanes）将推理通信流量与 KV Cache 传输流量隔离。高优先级 VL 保证推理通信不受 KV 传输干扰

#### 关键接口

MoonCake Transfer Engine API：
- `submitTransfer(src_addr, dst_addr, size, protocol)`：统一传输接口
- Topology matrix broadcast：启动时广播拓扑信息
- Batched doorbell submission：合并多个 RDMA 请求到一次 doorbell 通知，降低 NIC 开销

NVIDIA NIXL API：
- 统一抽象层，屏蔽 RDMA/NVLink/GDS/TCP 差异
- 非阻塞 API + 动态元数据交换
- 不消耗 GPU SM 资源

### 4. 架构决策分析

| 决策点 | 可选方案 | 选择 | 理由 | Trade-off |
|--------|---------|------|------|-----------|
| **RDMA 操作类型** | 单边（Read/Write）vs 双边（Send/Recv） | 双边为主 | 双边操作更易控制流量，单边虽无需远端 CPU 参与但需管理远端内存注册 | 双边延迟略高（+0.5 us），但编程模型更简单 |
| **传输层协议** | InfiniBand vs RoCE v2 vs iWARP | RoCE v2（主流） | InfiniBand 性能最优但成本高；RoCE 兼容以太网基础设施 | RoCE 需要 DCB/PFC 配置，拥塞控制不如 IB |
| **GPU-NIC 比例** | 1:1 vs N:1 | 1:1（推荐） | VMware/NVIDIA 测试确认 1:1 是 GDR 最优配置 | 成本翻倍（每 GPU 配一块 NIC），但带宽线性增长 |
| **流量隔离** | VL 隔离 vs 双网络 vs 软件限速 | VL 隔离 | 双网络成本翻倍；软件限速精度不够 | VL 配置复杂，需交换机支持 |

### 5. 性能剖析

#### 量化数据

| 配置 | 带宽 | 延迟 | 测试条件 |
|------|------|------|----------|
| RDMA Write（Host-to-Host） | 接近线速 | ~1.3 us | InfiniBand，小消息 |
| GPUDirect RDMA（GPU-to-GPU） | 接近线速 | ~1.9 us | InfiniBand，小消息，NVIDIA 官方 benchmark |
| 无 GDR（GPU->CPU->RDMA->CPU->GPU） | 线速 | ~17 us | 两次 bounce copy |
| MoonCake TE（4x200Gbps RoCE） | 87 GB/s | — | Kimi 生产环境 |
| MoonCake TE（8x400Gbps RoCE） | 190 GB/s | — | Kimi 生产环境 |
| NIXL + WEKA RDMA（8x H100） | 270 GB/s（读） | — | DGX 系统 |
| NIXL + CoreWeave VAST（200Gbps link） | 198 Gbps（~24.75 GB/s），线速 99% | — | 单链路测试 |
| MoonCake TE vs TCP | 2.4x 更快 | TTFT 低 25% | vLLM 集成测试 |

**DualPath 性能**（DeepSeek-AI 论文）：

| 指标 | 提升幅度 | 测试条件 |
|------|---------|----------|
| 离线推理吞吐 | 最高 1.87x | DeepSeek 660B |
| 在线服务吞吐 | 平均 1.96x（不违反 SLO） | DeepSeek 27B/660B |
| JCT 降低（双路径加载） | 38.19% | vs 单路径基线 |
| 存储 NIC 负载均衡 | Max/Avg 从 1.53 降至 1.18 | 多节点集群 |
| 近线性扩展 | 24x 规模，JCT 仅增 1.1% | 2P4D -> 48P96D |

**RDMA 提交开销对比**：
- cudaMemcpyAsync 单次提交：5-7 us
- RDMA Write work request：~1 us（通过 mmio 写入 NIC 寄存器）
- Doorbell batching 可进一步摊薄提交开销

#### 性能瓶颈

1. **PCIe 拓扑瓶颈**：GPU-NIC 不在同一 PCIe switch 时，GDR 带宽从理论值大幅下降。MoonCake GitHub issue 报告：400Gbps 硬件上 GDR 带宽仅 ~15 GB/s，而 CPU RDMA 达 ~47 GB/s，差距来自 PCIe 拓扑不当
2. **KV 传输与推理通信争抢**：未做流量隔离时，KV Cache 传输干扰 AllReduce/AllToAll 等推理关键通信，导致推理延迟抖动
3. **小消息效率**：大量小 KV block 传输（<4KB）时，RDMA 的固定开销（~1 us/次）占比过高

### 6. Trade-off 与限制

| 维度 | 选择 A（RDMA+GDR） | 选择 B（TCP） | 取舍分析 | 本方案选择 |
|------|-------------------|---------------|----------|-----------|
| **时间 vs 空间** | ~1.9 us 延迟，零拷贝 | ~20-100 us，需 buffer | RDMA 延迟低 10-50x，无额外内存 | RDMA 完胜 |
| **一致性 vs 性能** | RDMA Write 保证字节级有序 | TCP 保证流有序 | KV Cache 传输无需事务语义 | 无差异 |
| **复杂度 vs 收益** | 需 IB/RoCE 硬件、驱动、拓扑优化 | 开箱即用 | 2.4x 带宽、10x 延迟改善，值得 | 值得 |
| **通用性 vs 专用性** | 需 RDMA 网卡（ConnectX-6/7）+ IB/RoCE 交换机 | 任何以太网 | 硬件锁定但 AI 数据中心已普遍部署 | 可接受 |

**硬件依赖**：
- **NIC**：NVIDIA ConnectX-6 Dx / ConnectX-7（InfiniBand 或 RoCE v2），每张 ~$500-2000
- **交换机**：InfiniBand 交换机（QM8700/QM9700）或 RoCE-capable 以太网交换机（支持 DCB/PFC/ECN）
- **GPU**：支持 GPUDirect RDMA 的 NVIDIA GPU（Volta+）
- **1:1 GPU-NIC 比例**：最优配置，8-GPU 节点需 8 块 NIC

**部署约束**：
- **支持**：主要云厂商高端 GPU 实例（AWS p5、GCP a3-mega、Azure ND H100 v5），均配有 InfiniBand 或 RoCE
- **不支持**：消费级 GPU 服务器、无 RDMA 网络的数据中心、小规模部署（RDMA 网络建设成本高）
- **新兴选项**：MoonCake TE 已验证 TCP 和 RoCE 作为 PD 分离传输层，降低了对 InfiniBand 的硬依赖

**适用场景边界**：
- **适合**：大规模 PD 分离架构（100+ GPU）、跨节点 KV Pool 共享、延迟敏感型在线服务
- **不适合**：小规模单机部署、预算受限环境、无 RDMA 基础设施

---

## 方案 4：批量流水线（overlap 计算与传输）

### 1. 问题背景与必要性

**解决什么问题**：前三个方案解决"数据怎么搬"的问题，本方案解决"什么时候搬"的问题。核心思想是将数据传输与 GPU 计算在时间上重叠（overlap），使传输延迟被计算时间掩盖，对推理延迟的影响趋近于零。

**不解决的后果**：即使使用 RDMA（~1.9 us）或 GDS（~1 ms），如果传输和计算串行执行，每次 KV load/store 都会增加等值的推理延迟。对于 128 层模型，串行 load 128 次 KV 的累计延迟不可接受。

**必选还是优化**：**必选**。在任何涉及 KV Cache offloading 的系统中，如果不做计算-传输重叠，性能都会严重退化。这是一个**正交的架构优化**，可以叠加在方案 1/2/3 任何一个之上。

### 2. 核心原理

#### 核心思想

利用 GPU 的多引擎并行能力——计算引擎（SM）和 DMA 引擎（Copy Engine）可以同时工作——将第 N+1 层的 KV Cache 传输与第 N 层的 Attention 计算重叠。

```
时间轴 →
无流水线（串行）：
|--Load L1--|--Compute L1--|--Load L2--|--Compute L2--|--Load L3--|...
总时间 = N * (T_load + T_compute)

Layer-wise 流水线：
|--Load L1--|--Load L2-----|--Load L3-----|...
            |--Compute L1--|--Compute L2--|...
总时间 = T_load + N * max(T_load, T_compute) ≈ N * max(T_load, T_compute)
```

**加速比理论上限**：
- 若 T_load <= T_compute：加速比 = (T_load + T_compute) / T_compute，即传输完全被掩盖
- 若 T_load > T_compute：加速比 = (T_load + T_compute) / T_load，计算无法完全掩盖传输

#### 多层次流水线

```
层级 1：Layer-wise Pipeline（层间重叠）
  第 N 层计算 || 第 N+1 层 KV 预取

层级 2：Chunked Pipeline Parallelism (CPP)（MoonCake）
  Chunk K 的 Prefill 计算 || Chunk K-1 的 KV 传输到 Decode

层级 3：L2 Cache Prefetch（GPU 内部）
  当前 Attention 的 Q*K^T 计算 || 下一个 K Block 预取到 L2 cache

层级 4：Recomputation-Transfer Hybrid (KVPR)
  部分层 KV 重算 || 其余层 KV 从 SSD/DRAM 传输
```

#### 理论复杂度

- **时间复杂度**：从 O(N * (T_load + T_compute)) 降低到 O(N * max(T_load, T_compute))
- **空间复杂度**：O(K) 额外 buffer 用于 double-buffering，K 为预取深度（通常 1-2 层）

### 3. 设计机制

#### Layer-wise Pipeline（LMCache / MoonCake 共同采用）

```
┌────────────────────────────────────────────────────────────┐
│                    Inference Engine                          │
│                                                              │
│  CUDA Stream 0 (Compute):                                   │
│  |--Attn L0--|--FFN L0--|--Attn L1--|--FFN L1--|...         │
│                                                              │
│  CUDA Stream 1 (KV Load):                                   │
│  |--Load L1 KV--|--Load L2 KV--|--Load L3 KV--|...          │
│                                                              │
│  CUDA Stream 2 (KV Store):                                  │
│  |--Store L0 KV--|--Store L1 KV--|...                       │
│                                                              │
│  同步点：Layer N 计算开始前，确保 Layer N 的 KV 已加载完成    │
│  event: stream1.record() -> stream0.wait()                  │
└────────────────────────────────────────────────────────────┘
```

**LMCache 实现**：
- `save_kv_layer()`：每层计算完成后立即在 Store stream 上异步存储
- `wait_for_layer_load()`：层间同步点，确保下一层 KV 已就绪
- 三指针机制追踪 GPU->CPU 复制进度

**MoonCake CPP（Chunked Pipeline Parallelism）**：
- 将长序列切分为多个 chunk
- Chunk K 的 Prefill 在 Prefill 节点计算时，Chunk K-1 的 KV 通过 RDMA 传输到 Decode 节点
- 计算与跨节点传输完全重叠

#### GPU L2 Cache Prefetch（异步 KV Cache 预取论文）

```
┌─────────────────────────────────────────────────┐
│              GPU Attention Kernel                 │
│                                                   │
│  Warp 0-15: Q * K^T 计算                        │
│  同时：                                           │
│  Prefetch Unit: 将下一个 K Block 从 HBM 预取到 L2 │
│                                                   │
│  结果：                                           │
│  - 内存吞吐从 47% -> 87%（Llama2-7B）            │
│  - CPI 从 27.68 -> 9.28                          │
│  - Stall 从 21.34 -> 4.13 cycles                 │
└─────────────────────────────────────────────────┘
```

#### Recomputation-Transfer Hybrid（KVPR）

```
决策：对每一层选择"传输 KV"还是"重算 KV"
┌─────────────────────────────────────────┐
│  Profiler：测量每层的传输时间和重算时间  │
│                                          │
│  策略：                                  │
│  - 若 T_transfer(layer) < T_recompute   │
│    → 传输该层 KV                         │
│  - 否则 → GPU 重算该层 KV               │
│                                          │
│  流水线：                                │
│  GPU SM: 重算层 3,5,7 的 KV              │
│  DMA:    同时传输层 0,1,2,4,6 的 KV      │
│                                          │
│  目标：GPU 重算时间 ≈ CPU/SSD 传输时间   │
│         实现完美重叠                      │
└─────────────────────────────────────────┘
```

### 4. 架构决策分析

| 决策点 | 可选方案 | 选择 | 理由 | Trade-off |
|--------|---------|------|------|-----------|
| **流水线粒度** | Layer-wise vs Chunk-wise vs Token-wise | Layer-wise | Token 粒度同步开销过高；Chunk 粒度适合跨节点；Layer 粒度适合本地 offload | Layer-wise 需 N 层的 buffer |
| **预取深度** | 1 层 vs 2+ 层 | 1 层 | 1 层 double-buffering 足够掩盖大多数传输延迟 | >1 层增加内存占用但对超慢存储有帮助 |
| **Stream 数量** | 2（compute+transfer）vs 3+（compute+load+store） | 3 | Load 和 Store 解耦避免互相阻塞 | 更多 stream 增加同步复杂度 |
| **重算 vs 传输** | 全传输 vs 全重算 vs 混合 | 混合（KVPR） | 纯传输受带宽限制，纯重算浪费 SM 算力，混合自适应最优 | 需要 profiling 阶段确定最优比例 |

### 5. 性能剖析

#### 量化数据

| 技术 | 加速指标 | 提升幅度 | 测试条件 |
|------|---------|---------|----------|
| L2 Async Prefetch | Attention kernel 加速 | 1.84x - 2.15x | Llama2-7B/Llama3-8B/Qwen2.5-7B |
| L2 Async Prefetch | 端到端吞吐 | 1.97x | 512 input tokens, 512-8192 output tokens |
| L2 Async Prefetch | 内存吞吐利用率 | 47% -> 87%（Llama2-7B） | NVIDIA nsight profiling |
| L2 Async Prefetch | CPI（Cycles Per Instruction） | 27.68 -> 9.28 | Llama2-7B |
| MoonCake CPP | 吞吐提升 | +75%（真实负载） | Kimi 生产环境 |
| DualPath layer-wise prefill | JCT 降低 | 17.21% | DeepSeek 27B, ablation study |
| DualPath 全流水线 | JCT 降低 | 45.62%（叠加调度优化） | DeepSeek 27B |
| LMCache layer-wise | TTFT 降低 | 1.9-8.1x（vs 无 pipeline） | 多轮 QA 场景 |
| NIXL 大上下文场景 | Prefill 时间 | 10x 改善 | GDS + NIXL 组合 |

**TetriInfer 调度**（专注流水线调度优化）：
- 平均 TTFT 降低 97%
- JCT（Job Completion Time）降低 47%

#### 性能瓶颈

1. **同步开销**：每层需要一次 CUDA event 同步（stream1.record() + stream0.wait()），每次 ~1-2 us。128 层模型累计 ~128-256 us
2. **传输带宽不足时退化**：当 T_load >> T_compute（如 SSD 带宽不足），流水线退化为传输受限，计算引擎空闲
3. **首层冷启动**：第一层 KV 必须完整加载后才能开始计算，无法流水线化。这决定了 TTFT 的下限
4. **内存额外占用**：double-buffering 需要额外 1 层 KV Cache 的 GPU 内存。对 Llama-70B 每层 KV ~100MB，额外 100MB 可接受

### 6. Trade-off 与限制

| 维度 | 选择 A（流水线） | 选择 B（串行） | 取舍分析 | 本方案选择 |
|------|----------------|---------------|----------|-----------|
| **时间 vs 空间** | 传输被掩盖，多用 1 层 buffer | 无额外 buffer，延迟叠加 | 100MB buffer 换 1.8-2x 吞吐 | 选 A，极高性价比 |
| **一致性 vs 性能** | 异步传输+同步点保证 | 串行天然一致 | 流水线同步点保证层间一致性 | 无牺牲 |
| **复杂度 vs 收益** | 多 stream 管理、同步逻辑 | 简单顺序执行 | 2x 吞吐提升值得复杂度投入 | 值得 |
| **通用性 vs 专用性** | 需要 CUDA stream 并行能力 | 任何 GPU | CUDA stream 是标准能力，通用性良好 | 通用 |

**适用场景边界**：
- **适合**：所有 KV Cache offloading 场景，无例外
- **效果最优**：T_load 接近 T_compute 时（完美掩盖）
- **效果有限**：T_load >> T_compute（传输受限）或 T_load << T_compute（计算受限，传输不是瓶颈）

---

## 跨方案 Trade-off 总表

### 带宽与延迟全景

| 路径 | 单次延迟 | 峰值带宽 | CPU 开销 | 硬件成本增量 |
|------|---------|---------|----------|------------|
| GPU HBM 内部 | ~10 ns | 2-3.35 TB/s（A100/H100） | 无 | 0 |
| GPU->CPU（Pinned，PCIe4） | 10-20 us | ~26 GB/s | 低（DMA） | 0 |
| GPU->CPU（Pinned，PCIe5） | 10-20 us | ~50 GB/s | 低（DMA） | 0 |
| GPU->CPU（NVLink-C2C，GH200） | 透明 | 900 GB/s | 无（硬件一致性） | GH200 系统 |
| GPU->NVMe（GDS，单盘） | ~1 ms | ~7 GB/s | 无 | GDS 驱动 |
| GPU->NVMe（GDS，10 盘） | ~1 ms | ~26 GB/s | 无 | 多盘 |
| GPU->NVMe（GDS，多盘 PCIe5） | ~1 ms | ~84 GB/s | 无 | PCIe5 系统 |
| GPU->远端 GPU（GDR+IB） | ~1.9 us | ~50 GB/s（400Gbps） | 无 | IB NIC + 交换机 |
| GPU->远端 GPU（GDR+多 NIC） | ~1.9 us | ~190 GB/s（8x400Gbps） | 无 | 8x NIC |
| GPU->远端 CPU（RDMA） | ~1.3 us | 线速 | 无 | RDMA NIC |
| CPU->CPU（RDMA） | ~1.3 us | 线速 | 无 | RDMA NIC |
| CPU->SSD（pread，单盘） | 15-100 us | ~7 GB/s | 中（内核栈） | 0 |
| CPU->SSD（io_uring） | 同上 | ~7 GB/s（+20%） | 低 | Linux 5.1+ |
| CXL 扩展内存 | 200-500 ns | — | 低 | CXL 控制器 |

### 对推理延迟的影响

| 方案 | TTFT 影响 | TBT 影响 | 条件 |
|------|----------|---------|------|
| cudaMemcpy（CPU offload，无 pipeline） | +数十 ms（依赖序列长度） | +5-10 us/token | vLLM 原生 swap |
| cudaMemcpy（CPU offload，有 pipeline） | +数 ms（首层加载） | 接近 0（被掩盖） | LMCache layer-wise |
| GDS（SSD offload，无 pipeline） | +数百 ms（SSD 延迟 * 层数） | +~1 ms/token | 直接 SSD 加载 |
| GDS（SSD offload，有 pipeline） | +~1 ms（首层 SSD 延迟） | 接近 0（被掩盖） | GDS + layer-wise |
| RDMA（跨节点，无 pipeline） | +数 ms（网络 RTT * 层数） | +~2 us/token | 逐层串行传输 |
| RDMA（跨节点，有 pipeline） | +~2 us（首层 RDMA 延迟） | 接近 0（被掩盖） | MoonCake CPP |
| 最优组合：RDMA+GDR+Pipeline | TTFT 降低 10x（vs 基线） | TBT 降低 5x | MoonCake 论文报告 |

### 硬件依赖矩阵

| 方案 | NVIDIA GPU | 特殊驱动 | RDMA NIC | IB/RoCE 交换机 | NVMe SSD | 最低 Linux 版本 |
|------|-----------|---------|----------|---------------|----------|---------------|
| cudaMemcpy+pread | 任意 CUDA GPU | 无 | 不需要 | 不需要 | 可选 | 任意 |
| GDS | Volta+ | nvidia-fs | 不需要 | 不需要 | 需要（P2P DMA） | 5.4+ |
| RDMA+GDR | Volta+ | MLNX_OFED | ConnectX-6+ | 需要 | 不需要 | 5.4+（OFED） |
| Pipeline | 任意 CUDA GPU | 无 | 不需要 | 不需要 | 不需要 | 任意 |

### 部署环境兼容性

| 环境 | 方案 1 | 方案 2 | 方案 3 | 方案 4 |
|------|--------|--------|--------|--------|
| 通用 GPU 服务器（无 IB） | 完全支持 | 条件支持（需 P2P 拓扑） | 不支持 | 完全支持 |
| 云 GPU 实例（AWS p4/GCP a2） | 完全支持 | 部分支持 | 部分支持（EFA/RoCE） | 完全支持 |
| 高端 AI 集群（DGX/HGX） | 完全支持 | 完全支持 | 完全支持 | 完全支持 |
| 边缘/嵌入式 GPU | 完全支持 | 不支持 | 不支持 | 完全支持 |
| AMD GPU 环境 | 替换为 hipMemcpy | 不支持 | 部分支持（ROCm RDMA） | 替换为 HIP stream | 

---

## 组合策略分析

实际系统中，4 个方案不是互斥选择，而是**分层组合**使用。以下是业界的典型组合：

### 组合 1：LMCache 风格（本地优先）

```
路径优先级：GPU HBM -> CPU DRAM (cudaMemcpyAsync) -> SSD (GDS/io_uring)
流水线：Layer-wise pipeline 叠加在所有路径上
网络：可选 NIXL/RDMA 作为远端后端
```

**特点**：部署简单，无需 RDMA 网络，适合单机或小集群
**瓶颈**：SSD 带宽（~7 GB/s 单盘），大规模 miss 时延迟飙升

### 组合 2：MoonCake 风格（网络优先）

```
路径优先级：GPU HBM -> 远端 DRAM Pool (RDMA+GDR) -> 本地 SSD (GDS)
流水线：CPP (Chunked Pipeline Parallelism) 跨节点重叠
调度：Conductor 全局调度，拓扑感知路径选择
```

**特点**：跨节点共享，全局最优调度，适合大规模集群
**瓶颈**：RDMA 网络带宽、Conductor 单点

### 组合 3：DualPath 风格（带宽聚合）

```
路径 A：存储 -> Prefill Engine SNIC -> GPU
路径 B：存储 -> Decode Engine SNIC -> RDMA CNIC -> Prefill Engine GPU
流水线：Layer-wise prefill + 双路径并行加载
隔离：InfiniBand VL 隔离推理流量与 KV 传输流量
```

**特点**：聚合所有节点的存储网络带宽，解决 SNIC 饱和瓶颈
**瓶颈**：需要 IB VL 配置，调度器复杂度高

### 组合 4：NVIDIA CMX 风格（硬件分层）

```
G1: GPU HBM（活跃 KV）
G2: CPU DRAM（NVLink-C2C 900 GB/s，Grace Hopper）
G3: 本地 NVMe（GDS）
G3.5: CMX（以太网接 Flash，BlueField-4 管理）
流水线：NIXL 统一抽象 + 自动路径选择
```

**特点**：硬件原生分层，NVIDIA 生态闭环，性能上限最高
**瓶颈**：硬件锁定（Rubin/Grace 平台），成本极高

### 组合对比

| 维度 | LMCache 风格 | MoonCake 风格 | DualPath 风格 | CMX 风格 |
|------|-------------|-------------|-------------|---------|
| **最优带宽** | ~7 GB/s（单 SSD） | ~190 GB/s（8x400Gbps） | ~聚合所有 SNIC | 900 GB/s（NVLink-C2C） |
| **最低延迟** | ~100 us（SSD）、~10 us（CPU） | ~1.9 us（RDMA） | ~1.9 us（RDMA） | ~100 ns（NVLink-C2C） |
| **硬件成本** | 低 | 高（RDMA 网络） | 高（IB + VL） | 极高（专用硬件） |
| **部署复杂度** | 低 | 高 | 极高 | 中（NVIDIA 一体化） |
| **扩展上限** | 单机 | 千+ GPU | 千+ GPU | 万+ GPU |
| **代表场景** | 中小规模，SSD 丰富 | 大规模 PD 分离 | 存储密集型推理 | 下一代 AI 工厂 |

---

## 附录：关键量化数据来源

| 数据 | 来源 | 测试条件 |
|------|------|----------|
| PCIe Gen4/5 带宽 | NVIDIA 官方 spec + 社区 benchmark | A100/H100，cudaMemcpy bandwidth test |
| GDS 4.6x 加速 | Western Digital Tech Brief | Data24 4000 + H100，GDS enabled vs disabled |
| GDR 1.9 us 延迟 | NVIDIA Developer Blog (2014) | InfiniBand，小消息，GPU-to-GPU |
| MoonCake 87/190 GB/s | FAST'25 论文 | 4x200Gbps / 8x400Gbps RoCE |
| DualPath 1.87x 吞吐 | arXiv:2602.21548 | DeepSeek 660B，离线推理 |
| LMCache 400 Gbps CPU offload | arXiv:2510.09665 | 8x Broadcom Thor-2 400Gbps NIC |
| L2 Prefetch 2.15x 加速 | arXiv:2504.06319 | Llama2-7B，FlashAttention-3 基线 |
| NVMe 单盘 7 GB/s | Samsung PM9A3 spec | PCIe4 x4，128K sequential read |
| NIXL 270 GB/s | NVIDIA + WEKA benchmark | 8x H100 DGX，RDMA |
| CXL 200-500 ns 延迟 | IPDPS 2025 论文 | CXL 内存扩展设备 |

---

## 参考资料

- [NVIDIA GPUDirect Storage Benchmarking Guide](https://docs.nvidia.com/gpudirect-storage/configuration-guide/index.html)
- [Western Digital GPUDirect Storage Technical Brief](https://documents.westerndigital.com/content/dam/doc-library/en_us/assets/public/western-digital/collateral/tech-brief/tech-brief-nvidia-gpu-direct-openflex-data24-4000.pdf)
- [NVIDIA Benchmarking GPUDirect RDMA on Modern Server Platforms](https://developer.nvidia.com/blog/benchmarking-gpudirect-rdma-on-modern-server-platforms/)
- [Mooncake: A KVCache-centric Disaggregated Architecture for LLM Serving (FAST'25)](https://www.usenix.org/system/files/fast25-qin.pdf)
- [DualPath: Breaking the Storage Bandwidth Bottleneck in Agentic LLM Inference (arXiv:2602.21548)](https://arxiv.org/abs/2602.21548)
- [LMCache: An Efficient KV Cache Layer for Enterprise-Scale LLM Inference (arXiv:2510.09665)](https://arxiv.org/html/2510.09665v2)
- [Accelerating LLM Inference Throughput via Asynchronous KV Cache Prefetching (arXiv:2504.06319)](https://arxiv.org/abs/2504.06319)
- [NVIDIA CMX Context Memory Storage Platform](https://www.nvidia.com/en-us/data-center/ai-storage/cmx/)
- [NVIDIA NIXL - Enhancing Distributed Inference Performance](https://developer.nvidia.com/blog/enhancing-distributed-inference-performance-with-the-nvidia-inference-transfer-library/)
- [S3 over RDMA: Scaling the KV Cache Data Plane (VAST Data)](https://www.vastdata.com/blog/s3-over-rdma-scaling-the-kv-cache-data-plane)
- [io_uring for High-Performance DBMSs (VLDB)](https://arxiv.org/html/2512.04859v1)
- [CXL Memory Performance Characterization (IPDPS 2025)](http://pasalabs.org/papers/2025/IPDPS25_CXL.pdf)
- [Samsung Scaling AI Inference with KV Cache Offloading](https://download.semiconductor.samsung.com/resources/white-paper/scaling_ai_inference_with_kv_cache_offloading.pdf)
- [NVIDIA Accelerate Large-Scale LLM Inference with CPU-GPU Memory Sharing](https://developer.nvidia.com/blog/accelerate-large-scale-llm-inference-and-kv-cache-offload-with-cpu-gpu-memory-sharing/)
- [Deploy Distributed LLM Inference with GPUDirect RDMA over InfiniBand (VMware)](https://blogs.vmware.com/cloud-foundation/2025/09/16/deploy-distributed-llm-inference-with-gpudirect-rdma-over-infiniband-in-private-ai/)

---

## 评估收敛

### 五维质量属性评估

| 维度 | cudaMemcpy+pread | GPUDirect Storage | RDMA+GDR | Pipeline |
|------|------------------|-------------------|----------|----------|
| **延迟** | 6/10 (~1ms) | 7/10 (~1ms设备延迟) | 10/10 (~2μs) | 10/10 (被掩盖) |
| **带宽** | 5/10 (~7GB/s) | 8/10 (~26GB/s) | 9/10 (~50GB/s) | 10/10 (理论峰值) |
| **CPU开销** | 6/10 (中等) | 9/10 (无) | 10/10 (无) | 10/10 (无额外) |
| **硬件依赖** | 10/10 (无特殊) | 6/10 (NVIDIA+GDS) | 4/10 (RDMA NIC) | 10/10 (标准CUDA) |
| **部署复杂度** | 9/10 (低) | 7/10 (中) | 4/10 (高) | 7/10 (中) |
| **加权总分** | 7.2/10 | 7.8/10 | 7.4/10 | **9.4/10** |

### 置信度评估

| 方案 | 置信度 | 评估理由 |
|------|--------|----------|
| cudaMemcpy+pread | **高(95%)** | 业界标准，广泛验证，无硬件依赖 |
| GPUDirect Storage | **高(85%)** | NVIDIA官方支持，实测4.6x加速 |
| RDMA+GDR | **高(90%)** | Mooncake生产验证，但硬件门槛高 |
| Pipeline | **高(92%)** | LMCache/Mooncake验证，理论清晰 |

### 关键Trade-off识别

| Trade-off | 方案A | 方案B | 取舍分析 | 推荐选择 |
|-----------|-------|-------|----------|----------|
| **性能 vs 通用性** | RDMA+GDR | cudaMemcpy | RDMA性能最优但需要专用硬件 | 分层：cudaMemcpy为基础，RDMA为扩展 |
| **零拷贝 vs 兼容性** | GDS/RDMA | 传统拷贝 | 零拷贝性能好但需要特定硬件 | GDS优先，回退到传统拷贝 |
| **延迟隐藏 vs 实现复杂度** | Pipeline | 串行 | Pipeline可隐藏延迟但增加复杂度 | **必选Pipeline**，与底层路径正交 |
| **硬件成本 vs 性能上限** | RDMA网络 | 通用网络 | RDMA成本高但性能上限高 | 阶段投入：初期通用网络，规模扩大后RDMA |

### 决策结论

**推荐架构：分层组合 + Pipeline必选**

| 数据路径 | 技术选择 | 适用场景 | 优先级 |
|----------|----------|----------|--------|
| GPU↔DRAM | cudaMemcpyAsync + Pinned Memory | 本地热数据 | P0 (必选) |
| GPU↔SSD | GPUDirect Storage (GDS) | 本地温数据 | P1 (推荐) |
| 跨节点 | RDMA + GPUDirect RDMA | 远程共享 | P2 (扩展) |
| 所有路径 | Layer-wise Pipeline | 延迟隐藏 | **P0 (必选)** |

**Pipeline配置**：

```
CUDA Stream 0 (Compute):  |--Attn L0--|--FFN L0--|--Attn L1--|...
CUDA Stream 1 (KV Load):  |--Load L1--|--Load L2--|--Load L3--|...
CUDA Stream 2 (KV Store): |--Store L0--|--Store L1--|...
                         
同步点：Layer N计算前确保Layer N的KV已加载
```

**关键假设（需验证）**：
1. Pinned Memory带宽可达PCIe理论值的80%+
2. GDS在目标硬件环境可用且性能符合预期
3. Pipeline的同步开销 < 每层1μs

**风险与缓解**：
| 风险 | 可能性 | 影响 | 缓解策略 |
|------|--------|------|----------|
| GDS硬件不支持 | 中 | 高 | 自动回退到cudaMemcpy+io_uring |
| RDMA网络建设成本高 | 高 | 中 | 初期不使用，架构预留接口 |
| Pipeline同步开销过高 | 低 | 高 | 批量同步，减少event数量 |
| 多Stream内存带宽争抢 | 中 | 中 | 限制并发传输量，优先级调度 |

**阶段演进路线**：

| 阶段 | 技术栈 | 目标 |
|------|--------|------|
| Phase 1 | cudaMemcpy + Pipeline | 快速验证，无硬件依赖 |
| Phase 2 | + GDS | 本地SSD性能优化 |
| Phase 3 | + RDMA | 跨节点共享，大规模扩展 |

---
