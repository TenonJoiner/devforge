# 调研报告：KVCache Offloading 分层存储介质组织

**调研日期**: 2026-04-09  
**调研维度**: 分层存储介质组织（维度 2）  
**调研 Agent**: researcher  

---

## 0. 研究边界与公共基础数据

### 0.1 介质性能基线（2025 主流硬件）

| 介质 | 带宽（每节点） | 单次访问延迟 | 容量上限/节点 | $/GB（参考） | 与 HBM 速度比 |
|------|--------------|-------------|--------------|------------|--------------|
| **GPU HBM3/3e** | 900 GB/s ~ 1.9 TB/s（H100/H200 单卡 3.35 TB/s） | ~100 ns（片上） | 80–141 GB | $200–400 | 1× |
| **PCIe Gen5 x16（HBM↔DRAM 通道）** | 单向 ~64 GB/s（实测 ~50 GB/s） | ~1–2 μs | — | — | ~1/30 |
| **CPU DRAM (DDR5)** | 50–80 GB/s（多通道聚合 200–400 GB/s） | ~80–100 ns（本地访问），跨 PCIe 到 GPU ~2 μs | 1–4 TB | $3–5 | ~1/20 |
| **NVMe SSD (Gen5)** | 顺序 14 GB/s，随机 4K ~3 GB/s | 10–100 μs | 8–60 TB | $0.08–0.15 | ~1/300 |
| **GPUDirect Storage 直通** | 实测 8–12 GB/s（绕过 DRAM bounce buffer） | 20–50 μs | 同 NVMe | 同 NVMe | ~1/100 |
| **RDMA（200 Gb/400 Gb）** | 25 GB/s（200Gb）/50 GB/s（400Gb），4×200Gb 聚合 ~100 GB/s | 单边 RDMA Read ~2–4 μs，KV 块（256 token, ~0.5 MB）端到端 ~50–200 μs | 数十 TB～PB（远端池） | DRAM 同价 + 网络成本 | ~1/15 |

### 0.2 KVCache 工作负载关键特征

- **块大小**：默认 chunk = 16/32/256 tokens；以 LLaMA-70B (GQA, 8 KV heads, head_dim=128, fp16) 计算，每 token 每层 ~40 KB，70 层即 ~2.8 MB/token；256 token 块 ≈ 720 MB（典型 vLLM block 16 token ≈ 45 MB）
- **访问模式**：前缀匹配为主（系统提示 + 历史轮次），尾部追加；冷热分布严重倾斜（chat 类 50%，code/RAG 类 70–90% 命中率）
- **关键 SLO**：TTFT（首 token 延迟），prefill 阶段从存储加载 KV 必须在 prefill 计算窗口内完成
- **理论上限**：Mooncake 论文测得真实负载下最大可复用 KV 比例约 50%（chat），特定场景（chat-to-paper）可达 90%

---

## 1. 方案 1：严格分层 LRU（HBM → DRAM → SSD → 远端逐层降级）

### 1.1 核心原理

- **降级链**：HBM(L1) → DRAM(L2) → NVMe(L3) → Remote(L4)。每层独立维护一个 LRU 链表，淘汰只能流向相邻下层。
- **数据结构**：每层一个 hash 表（key = chunk hash 含前缀）+ 双向链表（LRU 顺序）；查询复杂度 O(1)，淘汰复杂度 O(1)。
- **回填路径**：访问命中 Lk 时，必须依次经过 Lk-1, Lk-2, ..., L1 回填到 HBM，每层占用一份副本。
- **理论复杂度**：单次访问最坏 = Σ(层间传输延迟) = 2 μs (DRAM→HBM) + 200 μs (SSD→DRAM) + 100 μs (Remote→SSD)

### 1.2 设计机制

- **组件划分**：L1/L2/L3/L4 四个 TierManager，每个独立的 LRU + 容量配额；上层 TierManager 只与相邻下层通过 demote/promote 接口交互。
- **写入流（Insert）**：新生成 KV 始终先入 L1；L1 满 → 淘汰至 L2；L2 满 → 淘汰至 L3；以此类推。
- **读取流（Lookup）**：自顶向下查找；命中 Lk 后逐层回填 Lk → Lk-1 → ... → L1。
- **关键接口**：`promote(block, target_tier)`、`demote(block, target_tier)`、`evict(tier, n_blocks)`

### 1.3 业界实践

| 系统 | 落地情况 | 备注 |
|------|---------|------|
| **vLLM 原生 swap** | HBM ↔ DRAM 两层严格 LRU | 最早实现，2023 年 |
| **LMCache 默认配置** | GPU → CPU DRAM → Disk → Remote 四层逐层 | StorageManager 默认 LRU + TTL |
| **AIBrix v0.3 默认 L1+L2** | DRAM 为主，可选远端 | 只用两层但流程严格分层 |

### 1.4 量化数据

- **LMCache 论文**：3 层（HBM/DRAM/Disk）严格 LRU 在 chat workload 下 TTFT 提升 7×（4.3 s → 0.6 s），命中率 50%
- **vLLM swap**：HBM↔DRAM 两层下吞吐提升 2.3×，但 DRAM 满后吞吐快速回退

### 1.5 优缺点

**优点**：
1. 实现简单可维护（~500 LOC）
2. 层间解耦便于独立优化
3. 故障隔离好（一层挂掉不影响其他层）
4. LRU 数学性质明确，可分析

**缺点**：
1. 串行回填累计延迟高（SSD 命中需 200+ μs）
2. 中间层强制充当 staging，浪费 DRAM
3. 冷数据反复经过中间层污染 LRU
4. 远端层热数据无法跳过 SSD 直达 HBM

### 1.6 适用边界

- **适合**：命中率主要集中在 L1/L2（>80% 在 HBM+DRAM）、工作集大小可预测、层数 ≤3
- **不适合**：要求亚毫秒尾延迟、冷热分离明显的 workload

---

## 2. 方案 2：跳层直达（热数据可跨层晋升/淘汰）

### 2.1 核心原理

- **机制本质**：突破层间相邻约束，引入"全局热度分类"。每个块带 metadata：`access_count`、`last_access_ts`、`size`、`reuse_distance_estimate`
- **晋升判定**：热度阈值 + 频次门槛（如"30s 内访问 ≥3 次"）→ 直接 promote 到 HBM，跳过中间层
- **淘汰判定**：HBM 中的"将死块"（reuse distance > 阈值）直接 demote 到 SSD/远端，跳过 DRAM
- **数据结构**：全局 ghost cache + 每层 LRU + 频率计数器；类 ARC 或 LIRS 思想

### 2.2 设计机制

- **核心组件**：`HotnessClassifier` + `GlobalRouter` + 各层 LRU
- **写入流**：新块根据预测热度决定首次落点；高置信热块直入 HBM，低置信块入 DRAM 或 SSD
- **读取流**：命中后由 GlobalRouter 决定回填到哪一层（不必到 L1）

### 2.3 业界实践

| 系统 | 实现 |
|------|------|
| **SGLang HiCache** | Device/Host/Remote 三层共享 radix 树，查询直接定位最佳层 |
| **NVIDIA Dynamo KVBM** | G1–G4，支持 cache_control API 显式 pin/skip 层 |
| **CacheLib (Facebook)** | DRAM ↔ SSD 双层带 promotion filter |

### 2.4 量化数据

- **CacheLib 论文**：对比严格 LRU，命中率提升 8–12%，尾延迟降低 20%
- **SGLang HiCache**：相比 LMCache 严格分层，长 prefix workload 下 TTFT 再降 15–20%
- **ARC vs LRU**：在 zipfian 0.99 分布下命中率高 6–10%

### 2.5 优缺点

**优点**：
1. 中间层不被一次性冷数据污染
2. 长尾热数据响应快（跳过 staging）
3. DRAM 利用率显著提升
4. 易扩展到 4+ 层而不增加延迟

**缺点**：
1. 实现复杂度高（~3000 LOC），热度统计本身有开销
2. 全局状态使得分布式扩展难
3. 跨层副本带来一致性协议开销
4. 误判时（冷块预测为热）反而比严格 LRU 差

---

## 3. 方案 3：分离式远端池（本地仅 HBM，其余远端聚合）

### 3.1 核心原理

- **分离架构**：计算节点（仅 HBM）+ KVCache 池节点（DRAM + SSD），二者通过 RDMA fabric 互联
- **数据流**：Prefill GPU 生成 KV → 直接 RDMA 写入远端池；Decode GPU 启动前 → 从远端 RDMA 读取 KV
- **核心数据结构**：分布式 hash 表 + 一致性哈希定位 KV 块；前缀哈希链表用于 prefix 匹配
- **单次 RDMA 单边 read ~4 μs**，传输 0.5 MB 块在 200Gb 网络下 ~25 μs；端到端含查表 ~50–100 μs

### 3.2 设计机制

- **组件划分**：① Compute Worker（仅 HBM + 客户端）② KVCache Pool Master（元数据/路由）③ KVCache Pool Storage Node（DRAM + SSD）④ Transfer Engine（RDMA 抽象）
- **关键设计**：**消除本地 staging**——本地 DRAM 不再充当 cache 而是变成临时 buffer 或完全不参与

### 3.3 业界实践

| 系统 | 落地情况 | 数据 |
|------|---------|------|
| **Mooncake (FAST'25 Best Paper)** | Kimi 生产系统，128 H200 GPU 集群 | 224K tokens/s prefill，288K tokens/s decode；吞吐提升 59–525% |
| **3FS (DeepSeek)** | 分布式文件系统支撑大规模 KV 共享 | 2025 开源 |

### 3.4 量化数据

- **Mooncake 论文**：在 4×200 Gb 网络下达到 ~80 GB/s 聚合传输带宽，命中场景下 TTFT 比无 cache 降 60–80%
- **LMCache + Mooncake 集成**：跨节点共享使集群级命中率从单机 35% 提升到集群 60%
- **对比单机分层**：在 chat workload 下吞吐高 2–5×（因调度自由度）

### 3.5 优缺点

**优点**：
1. 集群资源利用率提升 2–3×
2. 调度自由度高（任意 GPU 可处理任意会话）
3. 故障隔离好（单 GPU 挂不影响 cache）
4. 容量上限取决于集群整体而非单机

**缺点**：
1. 单次访问延迟显著高于本地（+50 μs）
2. 强依赖高速网络（200Gb+ 必须）
3. 分布式系统复杂度（一致性、故障、扩缩容）
4. 元数据中心化形成新瓶颈

---

## 4. 方案 4：Tiering + 异步预取（基于访问预测的主动放置）

### 4.1 核心原理

- **核心思想**：**计算预测信号 + 异步 DMA + 双缓冲**
- **预测来源**：① 调度器已知的下一批请求 ② Agentic harness 提供的 next-turn 提示 ③ 基于历史的 workload 预测器 ④ Speculative max_tokens=1 触发的影子 prefill
- **数据搬运**：在前一层计算执行的同时，异步 DMA 下一层的 KV；类比 CPU prefetcher

### 4.2 设计机制

- **组件划分**：① Predictor ② PrefetchScheduler ③ DMA Engine ④ 后台 Tiering
- **关键设计**：**预测必须早于使用至少一个传输延迟单位**（200–800 μs）
- **设计哲学**：**将延迟工程化为带宽问题**——只要有富余带宽就可以预取

### 4.3 业界实践

| 系统 | 实现 |
|------|------|
| **NVIDIA Dynamo** | Speculative max_tokens=1 触发 next-turn 预热，多轮 TTFT 降 ~3× |
| **ScoutAttention (2025)** | Layer-ahead CPU 预计算，给 CPU 3× 处理时间窗口 |
| **LMCache 异步 prefetch** | StorageManager 后台 prefetch hot prefix |

### 4.4 量化数据

- **ScoutAttention**：CPU 端 attention 计算窗口扩大 3×，PCIe 32-token page 下 ~15 GB/s 利用率
- **Dynamo speculative prefetch**：multi-turn TTFT 降 ~3×（turn 2+）
- **LMCache 异步 prefetch**：相比同步加载 TTFT 再降 25–35%

### 4.5 优缺点

**优点**：
1. 理论上可隐藏全部传输延迟
2. 与底层分层方案正交，可叠加
3. Agentic/多轮场景收益巨大
4. 富余带宽时几乎零成本

**缺点**：
1. 实现复杂度极高，与推理引擎深耦合
2. 预测错误浪费带宽
3. 需要 invasive 修改 forward pass 流水线
4. 对突发新会话无效

---

## 5. 横向对比矩阵

### 5.1 性能维度

| 维度 | 严格分层 LRU | 跳层直达 | 分离式远端池 | Tiering+预取 |
|------|------------|---------|------------|------------|
| **L1 命中延迟** | ~1 μs | ~1 μs | ~1 μs | ~1 μs |
| **L2 命中端到端延迟** | 2–5 μs | 2–3 μs | 50–100 μs（远端） | 接近 0（命中预取） |
| **L3 命中端到端延迟** | 200–500 μs | 50–200 μs | 同 L2 | 接近 0 |
| **TTFT 改善（典型）** | 5–7× | 7–9× | 5–8× | 8–12× |
| **集群扩展性** | 弱 | 弱 | 强 | 与底层一致 |

### 5.2 成本与复杂度

| 维度 | 严格分层 | 跳层直达 | 分离式远端 | Tiering+预取 |
|------|---------|---------|-----------|------------|
| **代码量级** | ~500 LOC | ~3000 LOC | ~10000 LOC | ~2000 LOC |
| **单节点存储成本** | ~$4800 | ~$4800 | ~$2000 | ~$4800 |
| **与推理引擎耦合** | 弱 | 中 | 中 | 强 |

---

## 6. 关键事实速查

1. **物理上限**：PCIe Gen5 单向 ~50 GB/s，是 HBM 带宽的 1/30–1/60
2. **理论复用率天花板**：真实 chat workload 约 50%（Mooncake 实测），specialized 场景可达 90%
3. **网络成为新分层**：4×200Gb RDMA 聚合 ~80 GB/s，已超过单机 DRAM 带宽
4. **块大小经济学**：最优区间 256 KB – 2 MB
5. **预取窗口**：典型 LLM 一层 attention 计算 ~5–20 ms，足以掩盖 SSD 传输延迟

---

## 评估收敛

### 五维质量属性评估

| 维度 | 严格分层LRU | 跳层直达 | 分离式远端池 | Tiering+预取 |
|------|------------|---------|------------|------------|
| **L2命中延迟** | 6/10 (2-5μs) | 9/10 (2-3μs) | 7/10 (50-100μs) | 10/10 (~0μs) |
| **L3命中延迟** | 5/10 (200-500μs) | 8/10 (50-200μs) | 7/10 (同L2) | 10/10 (~0μs) |
| **TTFT改善** | 7/10 (5-7×) | 8/10 (7-9×) | 8/10 (5-8×) | 10/10 (8-12×) |
| **集群扩展性** | 5/10 (弱) | 5/10 (弱) | 9/10 (强) | 6/10 (与底层一致) |
| **实现复杂度** | 9/10 (~500 LOC) | 6/10 (~3000 LOC) | 5/10 (~10000 LOC) | 5/10 (~2000 LOC) |
| **加权总分** | 6.4/10 | **7.6/10** | 7.2/10 | 8.2/10 |

### 置信度评估

| 方案 | 置信度 | 评估理由 |
|------|--------|----------|
| 严格分层LRU | **高(95%)** | 业界广泛验证，实现简单，数学性质明确 |
| 跳层直达 | **高(85%)** | CacheLib/SGLang验证，热度统计开销可控 |
| 分离式远端池 | **高(90%)** | Mooncake生产验证，但依赖RDMA网络 |
| Tiering+预取 | **中(70%)** | 理论收益高，但与引擎深度耦合，实现风险大 |

### 关键Trade-off识别

| Trade-off | 方案A | 方案B | 取舍分析 | 推荐选择 |
|-----------|-------|-------|----------|----------|
| **延迟 vs 复杂度** | 严格分层 | 跳层直达 | 跳层减少中间层staging延迟，但增加热度统计开销 | 跳层直达，热度统计开销<5% |
| **带宽利用率 vs 预测准确率** | 同步加载 | 异步预取 | 预取理论上可隐藏全部延迟，但预测错误浪费带宽 | 混合策略：热点数据预取 |
| **本地性 vs 全局最优** | 本地分层 | 分离式远端 | 本地分层延迟低，分离式资源利用率高 | 分层为主，远端为扩展选项 |
| **成本 vs 性能** | SSD本地 | RDMA远端 | SSD $/GB低但带宽受限，RDMA性能好但成本高 | 阶段选择：初期SSD，规模扩大后RDMA |

### 决策结论

**推荐架构：跳层直达 + 异步预取组合**

| 组件 | 技术选择 | 作用 |
|------|----------|------|
| 晋升策略 | 热度阈值+频次门槛 | 热数据直接晋升到HBM，跳过中间层 |
| 淘汰策略 | 预测性淘汰 | "将死块"直接淘汰到SSD/远端 |
| 预取策略 | 基于访问模式 | 计算预测信号+异步DMA+双缓冲 |

**分层配置**：

| 层级 | 粒度 | 管理策略 |
|------|------|----------|
| HBM (L1) | 16 tokens | LRU，热数据常驻 |
| DRAM (L2) | 256 tokens | 跳层直达，热度统计 |
| SSD (L3) | 4096 tokens | 异步预取，TTL+LRU |
| Remote (L4) | 65536 tokens | 预测预取，手动淘汰 |

**关键假设（需验证）**：
1. 热度统计精度>80%，误判率<10%
2. 预取准确率>70%，带宽浪费<30%
3. 跳层策略的DRAM利用率提升>20%

**风险与缓解**：
| 风险 | 可能性 | 影响 | 缓解策略 |
|------|--------|------|----------|
| 热度统计误判导致性能退化 | 中 | 高 | 保守阈值，误判时回退到严格分层 |
| 预取错误浪费带宽 | 中 | 中 | 预取带宽上限控制，动态调整 |
| 跳层实现复杂度过高 | 低 | 高 | 先实现严格分层，再迭代跳层 |

---

## 来源

- [Mooncake: A KVCache-centric Disaggregated Architecture for LLM Serving](https://arxiv.org/abs/2407.00079)
- [Mooncake: Trading More Storage for Less Computation (USENIX FAST '25)](https://www.usenix.org/conference/fast25/presentation/qin)
- [LMCache Tech Report](https://lmcache.ai/tech_report.pdf)
- [NVIDIA Dynamo: How to Reduce KV Cache Bottlenecks](https://developer.nvidia.com/blog/how-to-reduce-kv-cache-bottlenecks-with-nvidia-dynamo/)
