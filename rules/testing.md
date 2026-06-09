# R4 testing — 测试分层与 TDD 规范

## 适用范围

所有语言的测试代码。语言特定的测试框架和文件组织规范见各语言的 `coding-style-<lang>.md`。

---

## 测试分层

| 层级 | 范围 | Runner | 归属 |
|------|------|--------|------|
| 单元测试 | 单函数/模块（进程内、无外部依赖） | `./run-tests.sh ut` | 特性 proposal |
| 集成测试 | 多节点/组件交互、接口契约、故障注入 | `./run-tests.sh it` | 独立 proposal |
| 性能测试 | 基准/压力/回归 | `./run-tests.sh perf` | 独立 proposal |

---

## TDD 铁律

1. **RED**：先写一个失败的测试
2. **GREEN**：写最小实现使测试通过
3. **REFACTOR**：在绿色下简化代码

---

## 单元测试要求

- 每个公开的 API 函数至少有一个直接测试
- 每个错误路径至少有一个测试
- 新增代码必须被测试覆盖

---

## 覆盖率

- **单元测试行覆盖率**：
  - 通用模块 ≥ **85%**
  - 核心模块（metadata / storage / network / 一致性协议）≥ **90%**
- **新增代码**：行覆盖率 ≥ **95%**，100% 作为努力方向（显著低于 95% 需在 Q.4 说明并补充测试）
- **集成测试**：覆盖所有关键路径、子系统交互接口、端到端场景、故障恢复场景
- **性能测试**：建立基准线，回归检测 ≤5% 波动

---

## 测试文件组织

```
tests/
├── unit/
│   └── test_<module>_<scenario>.c
├── integration/
│   └── test_<subsystem>_<scenario>.c
└── perf/
    └── bench_<module>.c
```

---

## 断言风格

使用 `cmocka` 时的最小推荐子集：

```c
assert_int_equal(expected, actual);
assert_true(cond);
assert_ptr_not_null(ptr);
assert_string_equal("ok", result);
assert_memory_equal(expected, actual, len);
```

---

## 测试命名规范

测试名称是测试的"第一句话"，应让阅读者一眼理解测试在验证什么行为。

### 好测试 vs 坏测试

| 质量 | 好 | 坏 |
|------|-----|-----|
| **Minimal（单一）** | 一个测试只验证一个行为 | `test_wal_append_and_read_and_validate`（用"和"连接了多个行为） |
| **Clear（清晰）** | 名称描述行为 | `test1`、`test_case_42` |
| **Shows intent（展示意图）** | 名称展示期望的 API 用法 | 名称包含内部实现细节（如 `test_hash_insert_collision_chain` 而非 `test_put_with_bucket_full`） |

### 命名模式

- **Scenario 测试**：`test_<module>_<scenario>`
  - 好：`test_wal_append_persists_data`
  - 坏：`test_wal`
- **异常路径**：`test_<module>_<scenario>_rejects_<condition>`
  - 好：`test_wal_append_rejects_null_buffer`
  - 坏：`test_wal_append_error`
- **边界值**：`test_<module>_<scenario>_at_<boundary>`
  - 好：`test_wal_append_at_max_record_size`
  - 坏：`test_wal_append_big`

### 反模式

- 🚩 名称中包含"and"（说明测试在验证多个行为，应拆分）
- 🚩 名称是数字或编号（`test1`、`test_case_42`）
- 🚩 名称描述实现而非行为（`test_binary_search` 而非 `test_finds_element_in_sorted_array`）
- 🚩 名称中同时包含正常路径和异常路径（应拆分为两个测试）

---

## Mock 纪律

Mock 是隔离的手段，不是要测试的东西。

### 通用原则

- **先真实后 mock**：写测试时先用真实实现运行，确认测试对真实代码失败后，才在正确层级添加最小 mock
- **只 mock 慢/不可控的部分**：优先使用轻量级真实替代（内存数据库、临时文件、本地回环），只在确实不可控的外部边界使用 mock
- **不测试 mock 行为**：断言必须针对被测系统的真实行为，不能针对 mock 是否被调用、mock 返回值等 mock 自身行为
- **完整 mock**：mock 的数据结构必须完整镜像真实 API 的全部字段，不能只 mock 已知字段
- **注释说明**：每个 mock 必须注释说明 mock 了什么、为什么必须 mock、mock 行为与真实行为的差异
- **Mock 太复杂时重构**：如果 mock 设置占测试 >50%，说明被测模块耦合过紧，应重构解耦而非继续增加 mock 复杂度

### 单元测试

- mock 内部模块时，遵守 testing-anti-patterns.md 中的 Mock 反模式指导
- 优先使用真实调用链，mock 作为最后手段

### 集成测试

- **原则上禁止 mock**，必须走真实调用链
- 仅在极少数无法真实集成的外部边界（如第三方付费 API、特定硬件）才可例外 mock，且需经 code-reviewer 确认
- mock 必须注释说明其与真实行为的差异及不可真实集成的原因

---

## 集成测试编写规则

### 环境搭建/拆除要求

- 每个集成测试套件必须有独立的 `setup()`/`teardown()`，确保测试间无状态泄漏
- 文件系统测试使用临时目录（`mkdtemp`），teardown 时清理
- 网络测试使用随机端口绑定，避免端口冲突
- 多进程测试使用 `waitpid` 确保子进程正确回收，避免僵尸进程
- 数据库/存储引擎测试使用独立数据目录，teardown 时完整清除

### 故障注入验证标准

- **磁盘故障**：使用 `fallocate` + 只读挂载 / `LD_PRELOAD` 注入 IO 错误，验证错误处理路径
- **网络故障**：使用 `iptables`/`tc` 模拟丢包/延迟/分区，验证超时和重试逻辑
- **进程故障**：使用 `kill -9` 模拟崩溃，验证重启后数据完整性和状态恢复
- **并发故障**：使用 `helgrind`/`TSan` 检测竞态，使用延迟注入放大时间窗口

### 多节点测试编排规则

- 使用进程模拟多节点（单机多进程），Docker 按需用于需要网络隔离的场景
- 节点启动顺序和时机必须可控（支持延迟启动、乱序启动）
- 每个多节点测试必须验证至少一种故障场景（节点宕机/网络分区/脑裂）
- 一致性验证：写入后读取验证、多副本数据比对、故障恢复后数据完整性校验

### 集成测试反模式（Red Flags）

- 🚩 mock 了子系统内部模块（应走真实调用链）
- 🚩 测试通过但未验证数据正确性（只检查返回码不检查数据内容）
- 🚩 无故障场景（只测试 happy path）
- 🚩 测试间有隐式状态依赖（执行顺序影响结果）
- 🚩 硬编码端口/路径（导致并行运行冲突）
