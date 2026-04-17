# Engine Integration 需求规格

> 全局产品定义参见 [overview.md](overview.md)。
> 架构约束参见 [docs/adr.md](../adr.md) 和 [docs/architecture/README.md](../architecture/README.md)。
>
> 版本: v1.0  
> 日期: 2026-04-12  
> 状态: 已评审 / 待验证假设  
> 修正后置信度: 中 (72%)  
> 置信度理由: layer-wise pipeline fallback 路径已补充，WAL 选型已明确，但 vLLM API 稳定性仍为待验证假设；RDMA 降级路径依赖硬件审计结果。

## 涉及 Actors

- [推理引擎](overview.md#actors)（主 Actor，数据消费者与生产者）
- [缓存服务实例](overview.md#actors)（提供连接、查询、加载/存储接口）
- [AI 应用开发者](overview.md#actors)（集成配置与兼容性确认）
- [平台工程师 / MLOps](overview.md#actors)（升级与运维）
- [全局元数据服务](overview.md#actors)（分布式模式下的 prefix 定位）
- [数据传输服务](overview.md#actors)（层级别异步数据搬运）

---

## Feature: 推理引擎连接与握手

**做什么**：在引擎启动或缓存服务实例变更时，建立引擎与缓存服务之间的连接，并完成版本兼容性、配置参数、数据布局等关键信息的握手校验。

**为什么**：KV Cache 的数据格式对模型版本、block size、dtype、层数等高度敏感。不兼容的数据加载会导致计算错误或崩溃。握手校验是防止此类问题的第一道防线。

**涉及 Actor**：推理引擎、缓存服务实例、AI 应用开发者。

### Scenario: 正常路径 — 引擎成功连接并完成握手

**Actor**：推理引擎、缓存服务实例

**前置条件**：引擎和缓存服务版本兼容；配置参数一致（block_size, dtype, num_layers）。

**触发动作**：引擎启动时初始化 Connector；向缓存服务发送握手请求。

**预期行为**：握手在 1s 内完成；返回 capability 信息（支持的异步模式、最大 chunk 大小、传输路径）；引擎进入 READY 状态，可正常调度请求。

**验证方法**：正常启动 100 次：握手成功率 100%；平均握手时间 < 500ms；握手成功后首个请求 TTFT 与稳定期差异 < 10%。

### Scenario: 升级/回滚 — 缓存服务滚动升级，引擎无感知重连

**Actor**：推理引擎、缓存服务实例、平台工程师

**前置条件**：缓存服务执行滚动升级；旧实例在收到 SIGTERM 后开始优雅关闭。

**触发动作**：旧实例关闭连接；引擎检测到连接中断。

**预期行为**：引擎在 2s 内自动尝试重连到新实例；重连成功后重新握手；若握手成功，新请求继续使用缓存服务；升级期间引擎不崩溃、不中断服务。

**验证方法**：滚动升级 3 节点缓存服务，引擎持续发送请求：重连成功率 > 99%；重连时间 P99 < 2s；0 次引擎因连接中断而 panic 或 stuck > 5s。

### Scenario: 数据损坏/不兼容 — 兼容性 hash 校验失败，拒绝连接

**Actor**：推理引擎、缓存服务实例、AI 应用开发者

**前置条件**：引擎使用 vLLM 0.6.0，缓存服务数据来自 vLLM 0.5.0；block layout 存在差异。

**触发动作**：握手时双方交换 compatibility hash（包含 vllm_version, model_name, cache_dtype, block_size, tp_size, pp_size）。

**预期行为**：hash 不匹配时，缓存服务返回 `incompatible_layout` 错误；引擎将该缓存服务实例标记为不可用；引擎 fallback 到无缓存模式运行，不加载历史数据；告警上报 `engine_compatibility_mismatch`。并行配置（TP/PP）不同会导致 KV Cache 的 layout 和 shard 方式不兼容，必须纳入校验。

**验证方法**：修改握手参数中任意一项（如 block_size 从 16 改为 32）：100% 触发不兼容拒绝；0 次引擎加载错误 layout 的数据；5s 内触发监控告警。

### Scenario: 网络分区 — 分区期间连接中断，恢复后自动恢复

**Actor**：推理引擎、缓存服务实例

**前置条件**：引擎与缓存服务之间已建立长连接；网络发生 10s 分区。

**触发动作**：iptables DROP 引擎到缓存服务的流量。

**预期行为**：分区期间，引擎的缓存请求在 2s 内超时并 fallback 到 miss；分区恢复后，引擎在下次请求前自动重连；重连成功后服务恢复。

**验证方法**：注入 10s 分区：分区期间所有请求 100% fallback 成功（0 失败）；恢复后 5s 内握手成功；后续请求命中率恢复至分区前 95% 以上。

---

## Feature: 调度器侧 Prefix 匹配查询

**做什么**：在推理引擎的调度器进行 block 分配和请求调度前，向缓存服务查询当前请求的前缀在缓存中能匹配多少 token，以帮助调度器决定将多少 block 标记为 "外部加载"。

**为什么**：准确的 prefix 匹配信息是调度器做出最优分配决策的前提。匹配信息直接影响请求的 GPU block 需求量、调度优先级和可能的 TTFT。

**涉及 Actor**：推理引擎（调度器）、缓存服务实例、全局元数据服务。

### Scenario: 正常路径 — 查询返回准确的匹配 token 数

**Actor**：推理引擎（调度器）、缓存服务实例

**前置条件**：请求的 token 序列前 512 tokens 已存在于缓存中；后 100 tokens 为新内容。

**触发动作**：调度器调用 `get_num_new_matched_tokens(request)`。

**预期行为**：返回 `(matched_tokens=512, async_load=true)`；调度器据此分配 512 个外部 block；请求标记为需要异步加载。

**验证方法**：采集 10 万个请求：返回的 matched_tokens 与实际缓存内容一致性 100%；调度器据此分配的 block 数与实际需加载量误差 = 0；查询 P99 延迟 < 5ms。

### Scenario: 节点故障 — 元数据服务不可用，本地降级查询

**Actor**：推理引擎（调度器）、缓存服务实例、全局元数据服务

**前置条件**：分布式部署下，全局元数据服务主节点故障；从节点尚未完成 leader 切换。

**触发动作**：调度器发起 prefix 查询。

**预期行为**：查询在 1s 内检测到全局元数据服务不可达；缓存服务实例 fallback 到本地索引查询（L1 Radix Tree），仅返回本地已缓存的结果；若本地索引也 miss，则返回 `(0, false)`；调度器按 miss 处理，正常分配全量本地 block，请求不失败；后续全局元数据服务恢复后，按正常路径重新进行全局查询。

**验证方法**：kill 全局元数据服务主节点，持续注入请求：0 个请求因查询失败导致调度崩溃；本地降级查询响应率 100%；P99 查询延迟 < 10ms（本地）或 1s（超时 fallback）；元数据恢复后命中率恢复至分区前 95% 以上。

### Scenario: 并发冲突 — 高并发查询冲击

**Actor**：推理引擎（调度器）、缓存服务实例

**前置条件**：单个引擎实例每秒调度 1000+ 请求；多个引擎实例同时查询同一缓存服务。

**触发动作**：突发流量导致查询 QPS 达到平时的 5 倍。

**预期行为**：缓存服务不阻塞调度循环；P99 查询延迟增加 < 50%；无查询超时（若配置超时 > 5ms，允许少量超时并降级）；调度器吞吐量不下降。

**验证方法**：5x 流量压测 60s：查询成功率 ≥ 99.9%；P99 查询延迟 < 基准 P99 × 1.5；调度器 steps/s 与基准差异 < 5%。

### Scenario: 资源耗尽 — 查询队列满，快速失败或限流

**Actor**：推理引擎（调度器）、缓存服务实例

**前置条件**：缓存服务实例 CPU 使用率接近 100%；查询队列长度达到上限（如 1000）。

**触发动作**：极端高并发导致查询排队。

**预期行为**：新查询在 1ms 内返回 `busy` 或 `timeout`；调度器收到信号后将其视为 miss，继续正常调度；系统不因查询队列满而崩溃；CPU 在 30s 内恢复常态。

**验证方法**：使用 stress-ng 将缓存服务 CPU 压满：查询失败/降级率 100%（无成功查询）；0 次 panic/OOM；调度器 steps/s 保持基准的 95% 以上。

---

## Feature: Worker 侧异步加载/存储流水线

**做什么**：在推理引擎的 Worker 执行模型 forward 时，通过层级别（layer-wise）的异步 API，将 KV Cache 的加载和存储与计算重叠，最小化传输对推理延迟的影响。

**为什么**：层级别流水线是隐藏传输延迟的关键技术。该优化可将 offloading 的吞吐提升 ~10×，并将加载延迟对 TTFT 的影响降到最低。

**涉及 Actor**：推理引擎（Worker）、缓存服务实例、数据传输服务。

### Scenario: 正常路径 — 层级别流水线隐藏加载延迟

**Actor**：推理引擎（Worker）、缓存服务实例、数据传输服务

**前置条件**：请求需要加载 32 层 KV Cache；引擎支持 layer-wise pipeline（如 vLLM V1）。

**触发动作**：`start_load_kv()` 在 forward 前启动；每层 attention 计算前调用 `wait_for_layer_load(layer_id)`。

**预期行为**：层 N 的计算与层 N+1 的加载重叠；实际增加的 TTFT < 原始加载时间的 20%；decode 阶段 TPOT 不受影响。

**验证方法**：测量无 pipeline（同步加载）vs 有 pipeline 的 TTFT：pipeline 将额外 TTFT 降低 ≥ 70%；各层 `wait_for_layer_load` 平均等待时间 < 0.5ms；GPU 利用率保持 > 90%。

### Scenario: 引擎不支持 layer-wise pipeline — 同步降级路径

**Actor**：推理引擎（Worker）、缓存服务实例

**前置条件**：引擎为 vLLM V0 或其他不支持 layer-wise pipeline 的版本；请求需要加载完整的 KV Cache。

**触发动作**：握手阶段检测到引擎不支持 `wait_for_layer_load` API；Worker 退化为 `load_kv_blocks()` 同步或 block-wise 异步加载。

**预期行为**：缓存服务按 block 粒度（如 DRAM 256 tokens / SSD 256 tokens 粒度）而非 layer 粒度返回数据；引擎在 prefill 前完成全部缓存加载；相比无缓存基线，额外 TTFT < 原始全量 prefill 的 50%；请求不失败。

**验证方法**：在 vLLM V0 环境下运行 1000 条请求：0 次因降级路径导致引擎崩溃或请求失败；额外 TTFT P99 < 原始全量 prefill 的 50%；命中率统计与 V1 环境差异 < 5%。

### Scenario: 网络分区/抖动 — 加载过程中网络异常，超时降级

**Actor**：推理引擎（Worker）、缓存服务实例

**前置条件**：异步加载已启动；某层数据在传输过程中遇到网络抖动或 5s 分区。

**触发动作**：`wait_for_layer_load(layer_id)` 等待超时；或 `get_block_ids_with_load_errors()` 返回失败 block。

**预期行为**：单 layer 加载超时不影响其他 layer；引擎将该 layer 及之后的 token 标记为未计算，`num_computed_tokens` 回退；引擎按 `recompute` 策略重新计算缺失部分；请求最终成功完成。

**验证方法**：在加载第 10 层时注入 5s 网络分区：请求 100% 最终成功；超时检测时间 < 配置超时 + 200ms；回退重算产生的额外延迟 < 原始全量 prefill 的 50%。

### Scenario: 数据损坏 — 层加载数据校验失败

**Actor**：推理引擎（Worker）、缓存服务实例

**前置条件**：某层 KV Cache 在存储或传输过程中损坏。

**触发动作**：`wait_for_layer_load(layer_id)` 收到数据后进行 checksum 校验。

**预期行为**：校验失败时，引擎将该 layer 之后的 token 回退为未计算；触发本地重算；该 layer 的源数据在缓存服务中被标记为 invalid；请求不失败。

**验证方法**：随机损坏 5% 的 layer 数据：100% 损坏 layer 被检测；0 次引擎 forward 产生错误结果；回退重算成功率 100%；损坏数据 60s 内从缓存索引中移除。

### Scenario: 资源耗尽 — Pipeline 缓冲内存不足

**Actor**：推理引擎（Worker）

**前置条件**：多请求并发执行 layer-wise pipeline；Pipeline 缓冲内存达到 GPU 显存预算上限。

**触发动作**：新请求进入 pipeline 但缓冲内存不足。

**预期行为**：引擎根据 GPU 显存预算自主降低预取深度（如从 4 层预取降为 2 层），或对新请求切换为同步加载；缓存服务不参与该决策；不发生 OOM；已有请求的 pipeline 不受影响。

**验证方法**：人为限制 pipeline 缓冲内存至 100MB：引擎自适应降低并发深度或切换同步加载；0 次 OOM；P99 TTFT 增加 < 100%（相比最优 pipeline）；请求成功率 100%。

---

## 本域非功能需求

| 子项 | 目标值 |
|------|--------|
| 握手成功率 | 正常启动 100%，平均时间 < 500ms |
| 重连时间 | P99 < 2s；重连成功率 > 99% |
| Prefix 查询一致性 | 返回的 matched_tokens 与实际缓存一致性 100%；调度 block 误差 = 0 |
| Prefix 查询延迟 | P99 < 5ms（正常）；本地降级 P99 < 10ms |
| 查询降级可靠性 | 元数据服务故障时 0 请求崩溃；steps/s 保持基准 95% 以上 |
| Pipeline TTFT 收益 | 相比同步加载，额外 TTFT 降低 ≥ 70% |
| Pipeline 等待时间 | 各层 `wait_for_layer_load` 平均等待 < 0.5ms |
| 网络超时降级 |回退重算成功率 100%；额外延迟 < 原始全量 prefill 的 50% |
| 兼容性拒绝 | hash 不匹配时 100% 拒绝连接；0 次加载错误 layout |
