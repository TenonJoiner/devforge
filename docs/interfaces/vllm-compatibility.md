# vLLM 版本兼容性策略

**文档版本**: v1.0  
**日期**: 2026-04-11  
**Owner**: engine-integration-owner  
**关联 ADR**: ADR-006 与推理引擎集成接口决策  

---

## 1. 支持版本范围

### 1.1 当前支持版本

| vLLM 版本 | 支持状态 | 说明 |
|-----------|----------|------|
| v0.4.x | ✅ 全力支持 | 当前稳定基线，Connector V1 API 定型版本 |
| v0.5.x | ✅ 全力支持 | 社区广泛使用版本，API 无破坏性变更 |
| v0.6.x | ⚠️ 尽力支持 | 上游活跃开发版本，需逐 minor 版本验证 |
| < v0.4.0 | ❌ 不支持 | Connector V1 未稳定，维护成本过高 |
| > v0.6.x | ❓ 暂不承诺 | 待上游 release note 评估后决定是否支持 |

### 1.2 版本支持生命周期

- **新 minor 版本适配窗口**：上游发布后 2 周内完成兼容性评估，4 周内完成功能验证
- **版本退出机制**：若某 minor 版本发现 ≥2 个无法通过适配层隔离的破坏性 API 变更，则该版本标记为"不支持"
- **LTS 版本**：每 2 个 minor 版本选一个 LTS（如 v0.5.x），LTS 版本适配工作量上限 0.5 人周，非 LTS 上限 1 人周

---

## 2. API 变化监测机制

### 2.1 监测渠道

| 渠道 | 频率 | 责任人 | 具体操作 |
|------|------|--------|----------|
| vLLM GitHub Releases | 每周一 | engine-integration-owner | 阅读 release note，标记可能影响 KV Connector 的变更 |
| vLLM Discord #announcements | 实时 | engine-integration-owner | 订阅通知，捕捉未在 release note 中详细说明的行为变更 |
| vLLM 源码 diff (vllm/core/ + vllm/distributed/) | 每两周 | engine-integration-owner | 扫描 KV Cache 相关文件的变更，识别潜在接口变化 |
| 社区 Issue 搜索 ("KV Connector" / "disaggregation") | 每周 | engine-integration-owner | 收集用户反馈的兼容性问题和回归报告 |

### 2.2 变更响应流程

```
发现潜在 API 变更
    │
    ▼
24 小时内完成影响评估
    │
    ├── 低影响（适配层可隔离）→ 纳入下一个补丁版本
    │
    ├── 中影响（需修改适配层接口）→ 1 周内完成适配
    │
    └── 高影响（破坏 KVStoreInterface 抽象）→ 立即升级事件，48h 内输出应对方案
```

---

## 3. 适配层设计：KVStoreInterface

### 3.1 设计原则

- **零直接依赖**：业务逻辑（存储管理、调度、传输）只调用 `KVStoreInterface`，禁止直接调用 vLLM 内部 API
- **版本隔离**：每个支持的 vLLM 版本实现一个独立的 `VLLMvXXXAdapter`
- **快速降级**：若新版本无法及时适配，可在配置中回退至上一版本的 Adapter（前提是 ABI 兼容）

### 3.2 接口草案

```c
// kv_store_interface.h
// 引擎无关的 KV Cache 存储抽象层

typedef struct KVStoreInterface {
    // Block 生命周期管理
    void* (*allocate_block)(int layer_id, size_t token_count);
    int   (*free_block)(void* block_handle);
    int   (*copy_block)(void* dst, void* src, size_t token_count);

    // Block Table 操作
    void* (*get_block_table)(int64_t request_id);
    int   (*set_block_table)(int64_t request_id, void* block_table);

    // 传输接口（用于 offloading / PD 分离）
    int   (*transfer_to_remote)(void* block_handle, const char* endpoint);
    int   (*transfer_from_remote)(void* block_handle, const char* endpoint);

    // 元数据查询
    size_t (*get_block_size)(void* block_handle);
    int    (*get_block_layer)(void* block_handle);

    // 版本信息（用于调试和兼容性检查）
    const char* (*version)();
} KVStoreInterface;

// 工厂函数：根据运行时检测的 vLLM 版本返回对应 Adapter
KVStoreInterface* kvstore_create_adapter(const char* vllm_version);
```

### 3.3 vLLM 特定适配器

```c
// vllm_v0.5_adapter.c
// 封装 vLLM v0.5.x 的 BlockTable、Worker 和 KV Cache 分配逻辑

static void* vllm_v05_allocate_block(int layer_id, size_t token_count) {
    // 内部调用 vLLM 的 CacheEngine.allocate()
    // 但对外隐藏 BlockTable 的具体结构
}

static void* vllm_v05_get_block_table(int64_t request_id) {
    // 内部调用 scheduler.block_manager.get_block_table()
    // 返回引擎无关的 BlockTable 拷贝
}

// ... 其他接口实现
```

### 3.4 适配器测试策略

| 测试层 | 覆盖率目标 | 测试内容 |
|--------|-----------|----------|
| 单元测试 | 80% | 每个 Adapter 的接口独立 mock 测试 |
| 集成测试 | 100% | 每个支持的 vLLM 版本至少跑通一次端到端 offloading |
| 回归测试 | 100% | 新 Adapter 加入时，旧版本 LTS 必须全部通过回归 |

---

## 4. 升级与热切换策略

### 4.1 Library/Sidecar 双模式运行

ADR-006 决策要求实现 Library 与 Sidecar 的运行时切换能力：

| 模式 | 默认运行 | 切换触发条件 |
|------|----------|--------------|
| Library | 正常运行态 | 默认启动 |
| Sidecar | 升级/故障兜底态 | 收到配置中心切换信号、或 Library 初始化失败、或检测到未适配的 vLLM 版本 |

### 4.2 滚动升级流程

```
1. 准备新版本 Library (*.so)
   │
   ▼
2. 配置中心下发"灰度节点列表"
   │
   ▼
3. 灰度节点：热切换至 Sidecar 模式（~10ms 中断）
   │
   ▼
4. 替换 Library 文件，重新加载
   │
   ▼
5. 灰度节点：切回 Library 模式
   │
   ▼
6. 观察 30 分钟，无异常后扩大灰度范围
   │
   ▼
7. 全量 rollout
```

### 4.3 版本兼容性测试流程

1. **CI 兼容性矩阵**：每次 PR 在以下版本组合上跑通集成测试
   - vLLM v0.4.2 + CUDA 11.8
   - vLLM v0.5.4 + CUDA 12.1
   - vLLM v0.6.x (latest) + CUDA 12.1
2. **版本兼容性检查清单（发布前必做）**：
   - [ ] `kvstore_create_adapter()` 能正确识别并加载各版本 Adapter
   - [ ] Block allocate/free/copy 在 GPU 显存紧张时无泄漏
   - [ ] BlockTable get/set 在 10K 序列并发下正确
   - [ ] `transfer_to_remote` / `transfer_from_remote` 在 RDMA 和 TCP 降级路径均通过
   - [ ] 适配器版本号与测试日志一致

---

## 5. 维护预算与熔断机制

### 5.1 维护预算

- **每个 vLLM minor 版本适配工作量上限**：1 人周
- **LTS 版本上限**：0.5 人周
- **若连续 2 个 minor 版本均超出预算**：触发"是否切换为更稳定的集成模式"的强制评审

### 5.2 熔断条件

| 条件 | 触发行动 |
|------|----------|
| 单版本适配 > 2 人周 | 暂停对该版本的支持，评估是否切换为 Sidecar 为主 |
| Connector V1 API 被弃用 | 启动 Connector V2 / 替代接口的迁移评估 |
| vLLM 发布节奏加快至 < 4 周 / minor | 评估缩减支持版本范围，仅保留 LTS |

---

## 6. 多引擎适配路线图

### 6.1 引擎优先级

| 引擎 | 优先级 | 计划时间 | 备注 |
|------|--------|----------|------|
| vLLM | P0 | MVP 必选 | 当前深度集成目标 |
| TensorRT-LLM | P1 | Phase 2 | 需调研其 KV Cache 管理机制 |
| SGLang | P1 | Phase 2 | RadixAttention 原生支持，接口差异较大 |
| TGI | P2 | 待定 | 根据社区需求和资源评估 |

### 6.2 多引擎抽象预留

`KVStoreInterface` 的设计已预留多引擎扩展能力：
- 不同引擎实现各自的 `create_adapter()` 工厂函数
- 存储管理层（tiering、传输、淘汰）完全 engine-agnostic
- 引擎特定代码只存在于 Adapter 层和初始化层

---

## 7. 相关文档

- [ADR-006](../adr.md#ADR-006) — 与推理引擎集成接口决策
- [decision-integration.md](../architecture/decisions/decision-integration.md) — 集成接口维度探索笔记
- [decision-integration.research.md](../architecture/decisions/decision-integration.research.md) — 集成接口 researcher 原材料
