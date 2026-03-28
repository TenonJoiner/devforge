# 反馈闭环

## 1. 概述

反馈闭环是一种自动化的**发现-修复-再验证**循环，借鉴 harness engineering 中的反馈器概念和 GAN 对抗思想，从多个层面持续发现并修复代码问题，直到收敛。

**两个独立闭环**：

- **闭环 A（编译+测试）**：编译错误 → 测试缺陷 → 修复 → 再验证，聚焦代码正确性
- **闭环 B（代码分析）**：设计违反 → 坏味道 → 技术债务 → 重构/重设计 → 再分析，聚焦代码质量

两个闭环**独立触发、互不依赖**，可以不同频率运行（如 A 每次提交触发，B 定期触发）。

**闭环 A 内部递进**：L1 编译通过才进 L2 测试。

**GAN 式对抗**：复用现有 Agent 角色，通过编排指令约束行为——
- **项目经理 A10**（裁判）：控制对抗节奏，判断收敛和终止
- **集成测试工程师 A6**（判别器）：不断深挖问题
- **开发工程师 A2**（生成器）：不断提高代码质量

Agent 根据当前闭环类型切换行为模式（A 模式做编译+测试，B 模式做分析+重构）。

## 2. 两个闭环

```
闭环 A（编译+测试）                  闭环 B（代码分析）
独立触发，聚焦代码正确性              独立触发，聚焦代码质量

  L1 编译反馈                          L3 分析反馈
     │ 语法/类型/链接                     │ 设计/坏味道/债务
     │ 静态分析告警                       │ 性能反模式
     ▼                                    ▼
   修复语法                            重构/重设计
     │                                    │
     ▼                                    ▼
  L2 测试反馈                          再分析
     │ 缺陷/内存/并发                     │
     │ 性能回归                           ▼
     ▼                                  收敛
   修复缺陷
     │
     ▼
   收敛
```

### 2.1 闭环 A：编译+测试

**目标**：代码能正确编译、功能正确、无已知缺陷。

闭环 A 内部包含两个层级，L1 通过才进 L2：

#### L1 编译反馈

执行项目已有的编译构建脚本（如 `make`、`cmake --build` 等），分析构建输出。具体的编译器选项、静态分析配置等由项目自身的构建系统定义，反馈闭环不关心细节。

**通过标准**：构建脚本零错误退出。

#### L2 测试反馈

执行项目的集成/系统测试（单元测试属于开发阶段 TDD 职责，不在反馈闭环范围内）。

| 检测手段 | 发现的问题 |
|---------|-----------|
| 集成/系统测试 | 跨模块交互问题、接口契约违反、多节点一致性、故障恢复 |
| ASan / TSan / MSan | 内存泄漏、use-after-free、数据竞争、死锁 |

性能测试耗时较长，作为独立专项执行，不纳入常规闭环迭代。

**通过标准**：集成/系统测试全部通过，sanitizer 零告警。

#### 闭环 A 内部递进

```
项目经理每轮判断（A 模式）：

  L1 构建不通过？
    └─ 是 → 只做 L1，修复构建错误
    └─ 否 ↓

  L2 有失败测试或 sanitizer 告警？
    └─ 是 → 做 L2，修复缺陷
    └─ 否 → 收敛，闭环 A 完成
```

### 2.2 闭环 B：代码分析（设计预埋）

**目标**：代码符合设计约束，无结构性问题。

闭环 B 作为设计预埋，具体检测手段和修复策略后续讨论。初步方向：

- **设计约束检查**：对照 `docs/` 设计文档，检查接口契约违反、数据流不一致
- **代码度量**：函数过长（>50行）、文件过大（>800行）、圈复杂度过高
- **坏味道检测**：深嵌套、重复代码、过度耦合
- **技术债务**：TODO/FIXME/HACK、过时 API、缺失错误处理
- **性能反模式**：不必要的拷贝、锁粒度过粗

**待讨论**：L3 的检测主要靠 Agent 阅读分析，还是依赖外部工具（cppcheck、复杂度计算等），还是两者结合。

## 3. 对抗模式

```
       ┌────────── 对抗循环 ──────────┐
       │                              │
集成测试工程师 A6                开发工程师 A2
  （判别器）                      （生成器）
       │                              │
       │  ┌─ 闭环 A 模式 ──────────┐  │
       ├─ │ L1: 编译检查           │  ├─ 修复编译错误 ─┐
       ├─ │ L2: 测试执行           │  ├─ TDD 修复 ────┤
       │  └────────────────────────┘  │               │
       │  ┌─ 闭环 B 模式 ──────────┐  │               │
       ├─ │ L3: 代码分析           │  ├─ 重构/重设计 ──┤
       │  └────────────────────────┘  │               │
       │                                              │
       │←──── 修复后的代码 ──────────────────────────┘
       │
       ├─ 重新检查：修复是否引入新问题？
       └─ 更深检查：是否有之前未发现的问题？

项目经理 A10（裁判）
       ├── 判断收敛：问题数是否减少？
       ├── 判断终止：是否达到停止条件？
       └── 模式切换：根据触发的闭环类型选择 A 或 B 模式
```

**对抗动态**：
- 开发工程师的修复可能引入新问题 → 集成测试工程师在下一轮捕获
- 集成测试工程师每轮可以更深入检查 → 开发工程师需要更高质量的修复
- 对抗推动质量持续提升，直到达到均衡（收敛）

**模式切换**：同一套 Agent 通过项目经理的指令切换行为——
- A 模式：集成测试工程师执行编译检查 + 测试执行，开发工程师做直接修正 + TDD 修复
- B 模式：集成测试工程师执行代码分析，开发工程师做重构 / 重设计

## 4. 架构

```
触发源 A（提交 / CI / 手动）          触发源 B（定期 / 手动）
  │                                     │
  └─→ 外层脚本                          └─→ 外层脚本
        │（时间守护、锁、代码准备、归档）       │
        └─→ Claude Code team session     └─→ Claude Code team session
              │                                │
              ├── 项目经理 A10（A 模式）        ├── 项目经理 A10（B 模式）
              │     ├── 轮次 N:                │     ├── 轮次 N:
              │     │   ├── A6 发现 → L1/L2    │     │   ├── A6 发现 → L3
              │     │   └── A2 修复 → fixes    │     │   └── A2 修复 → fixes
              │     └── 收敛 / 终止             │     └── 收敛 / 终止
              └── 输出：report.md               └── 输出：report.md
```

### 4.1 职责分层

| 层 | 角色 | 职责 | 不负责 |
|----|------|------|--------|
| 外层脚本 | — | 触发调度、timeout 上限、flock 防重入、git 分支管理、归档通知 | 问题发现、代码修复 |
| 项目经理 A10 | team lead | 轮次控制、模式选择、终止判断、任务分派、报告生成 | 直接检查或修复 |
| 集成测试工程师 A6 | 判别器 | A 模式：编译检查+测试执行；B 模式：代码分析。归因定位、结构化输出 | 代码修复 |
| 开发工程师 A2 | 生成器 | A 模式：直接修正+TDD 修复；B 模式：重构/重设计。置信度守门、回归验证、原子 commit | 问题发现 |

### 4.2 通信

- **文件系统**：`feedback-runs/<scenario>/<run_id>/round-N/` 下的 `issues.yaml`、`fixes.yaml`、`state.yaml`，不同场景各自独立目录
- **Team 系统**：项目经理通过 TeamCreate 建团队，SendMessage 分派任务

## 5. 角色与行为约束

反馈闭环不定义新 Agent，而是复用现有角色，通过项目经理分派任务时附加行为约束来实现对抗分工。

### 5.1 项目经理（A10 `project-manager`，新增通用角色）

team lead，不直接检查或修复，只做调度和决策。项目经理是团队通用角色，反馈闭环是其职责之一。

**反馈闭环中的职责**：
1. 根据触发类型选择闭环模式（A 或 B）
2. A 模式：管理 L1 → L2 递进
3. 每轮开始前检查终止条件
4. 分派发现任务（给 A6）和修复任务（给 A2），附加行为约束
5. 维护 state.yaml
6. 生成最终报告

**关键规则**：
- 绝不直接执行检查或修复
- A 模式下层级递进必须有序（L1 通过才 L2）
- 恶化时立即终止并回滚
- state.yaml 实时更新

### 5.2 集成测试工程师（A6 `integration-tester`，判别器角色）

反馈闭环中承担判别器角色，按项目经理指定的模式发现问题，输出结构化报告。

**行为约束（由项目经理分派时附加）**：
- **只发现不修复**——区别于日常工作中可能顺手修 test 的习惯
- 每个问题必须有证据（stack trace / 编译输出 / 分析依据）
- A 模式下 L1 阻塞 L2——编译不通过不跑测试
- 先查 error-learning.jsonl 历史再分析
- 输出 issues.yaml

**A 模式具体行为**：
1. L1：执行项目构建脚本，分析构建输出
2. L2：执行项目测试脚本，分析测试结果和 sanitizer 输出

**B 模式具体行为**：
1. L3：执行代码分析（设计约束 + 代码度量 + 坏味道）

### 5.3 开发工程师（A2 `developer`，生成器角色）

反馈闭环中承担生成器角色，修复发现的问题。质量优先——宁可跳过不确定的修复，也不引入新问题。

**行为约束（由项目经理分派时附加）**：
- **只修复不发现**——聚焦于 issues.yaml 中列出的问题，不主动扩大范围
- 置信度守门（≥ REVIEW_CONFIDENCE 自动提交，< MIN_CONFIDENCE 跳过）
- 安全限制（MAX_FILES_PER_FIX / MAX_LINES_PER_FIX）
- 回归验证 + 原子 commit
- 记录到 error-learning.jsonl

**A 模式具体行为**：
1. L1：直接修正编译错误
2. L2：TDD 修复（铁律：NO FIX WITHOUT A FAILING TEST FIRST）

**B 模式具体行为**：
1. L3：重构 / 重设计

**通用规则**：
- 每个问题最多重试 3 次
- 修复后回归测试必须通过
- 不做超出当前问题范围的大改动

## 6. 终止条件

两个闭环各自独立判断终止：

### 6.1 闭环 A 终止条件

| 条件 | 判定 | 动作 |
|------|------|------|
| L1+L2 问题归零 | **收敛** | 生成成功报告，退出 |
| L1 问题归零 | **升级** | 进入 L2 |
| 连续 N 轮问题数不减少 | **停滞** | 生成报告（含未修复问题），退出 |
| 达到 MAX_ROUNDS | **超限** | 生成报告（含未修复问题），退出 |
| 接近 DEADLINE_HOUR | **超时** | 生成报告（含当前状态），退出 |
| CRITICAL 问题修复失败 | **阻塞** | 立即通知，生成紧急报告，退出 |
| 新增问题 > 修复问题 | **恶化** | 回滚本轮修复，生成报告，退出 |

### 6.2 闭环 B 终止条件

| 条件 | 判定 | 动作 |
|------|------|------|
| L3 问题归零 | **收敛** | 生成成功报告，退出 |
| 连续 N 轮问题数不减少 | **停滞** | 生成报告（含未修复问题），退出 |
| 达到 MAX_ROUNDS | **超限** | 生成报告（含未修复问题），退出 |
| 接近 DEADLINE_HOUR | **超时** | 生成报告（含当前状态），退出 |
| 新增问题 > 修复问题 | **恶化** | 回滚本轮修复，生成报告，退出 |

## 7. 数据格式

### 7.1 issues.yaml（集成测试工程师输出）

```yaml
round: 1
timestamp: "2026-03-25T22:30:00+08:00"
level: L2                        # build-test: L1 | L2；code-analysis: L3

summary:
  total_issues: 8
  by_level: { L1: 0, L2: 8 }
  by_severity: { CRITICAL: 1, HIGH: 3, MEDIUM: 2, LOW: 2 }
  test_stats:                    # 仅 L2 时填充
    total: 150
    passed: 142
    failed: 6
    skipped: 2
    duration_seconds: 1200

issues:
  - id: "ISSUE-001"
    level: L2
    severity: CRITICAL
    category: memory             # L1: compile-error | compile-warning | link-error | static-analysis
                                 # L2: memory | concurrency | logic | io | protocol | config
                                 # L3: design-violation | code-smell | tech-debt | perf-antipattern | complexity
    title: "use-after-free in replica_handle_sync"
    description: "AddressSanitizer: heap-use-after-free in replica_handle_sync"
    location:
      file: "src/replication/sync.c"
      function: "replica_handle_sync"
      line: 234
    evidence: |
      #0 replica_handle_sync src/replication/sync.c:234
      #1 handle_message src/network/handler.c:89
    reproduction: "make test TEST=test_replica_sync_after_crash"
    historical_matches:
      - issue_id: "ISSUE-xxx"
        similarity: high         # high | medium | low
        fix_pattern: "引用计数延长生命周期"
    suggested_root_cause: "sync 缓冲区在回调完成前被释放"
```

### 7.2 fixes.yaml（开发工程师输出）

```yaml
round: 1
timestamp: "2026-03-25T23:15:00+08:00"
fixes:
  - issue_id: "ISSUE-001"
    status: FIXED                # FIXED | SKIPPED | NEEDS_REVIEW
    confidence: 0.95
    approach: TDD                # DIRECT_FIX (L1) | TDD (L2) | REFACTOR (L3) | REDESIGN (L3)
    root_cause: "sync_buf 在异步回调注册后立即释放，回调触发时访问已释放内存"
    fix_description: "将 sync_buf 生命周期延长至回调完成，使用引用计数管理"
    changes:
      - file: "src/replication/sync.c"
        lines_added: 12
        lines_removed: 3
      - file: "tests/unit/test_sync_buf_lifecycle.c"
        lines_added: 45
        lines_removed: 0
    test_added: "test_sync_buf_lifecycle"
    regression_passed: true
    commit_hash: "a1b2c3d"
    commit_message: "fix(replication): extend sync_buf lifetime with refcount to prevent use-after-free"
    retry_count: 0
    self_check:
      root_cause_clear: true
      evidence_based: true
      impact_assessed: true
      regression_risk_low: true
```

### 7.3 state.yaml（运行状态）

每次运行一个 state.yaml，场景由目录路径隐含（`feedback-runs/<scenario>/<run_id>/`）：

```yaml
run_id: "2026-03-25-220015"
start_time: "2026-03-25T22:00:00+08:00"
status: IN_PROGRESS              # IN_PROGRESS | CONVERGED | STALLED | TIMEOUT | ABORTED

# build-test 专有
current_level: L2                # L1 | L2（仅 build-test）
level_status:                    # 仅 build-test
  L1: PASSED                    # PASSED | IN_PROGRESS | BLOCKED
  L2: IN_PROGRESS

current_round: 2

rounds:
  - round: 1
    level: L2
    status: COMPLETED
    issues_found: 6
    issues_fixed: 4
    issues_skipped: 2
    new_issues_introduced: 0
    duration_seconds: 2700

history:
  issue_trend: [6, 2]
  fix_rate: [0.67]
  level_transitions:             # 仅 build-test
    - { from: L1, to: L2, round: 1, reason: "L1 编译零问题" }
```

### 7.4 error-learning.jsonl（Reflexion）

每个场景各自独立一份，位于 `feedback-runs/<scenario>/error-learning.jsonl`，每行一条，追加写入：

```json
{
  "timestamp": "2026-03-25T23:15:00+08:00",
  "issue_id": "ISSUE-001",
  "level": "L2",
  "category": "memory",
  "error_type": "use-after-free",
  "root_cause": "异步回调中访问已释放的缓冲区",
  "fix_pattern": "引用计数延长生命周期",
  "location": "src/replication/sync.c:replica_handle_sync",
  "keywords": ["use-after-free", "async-callback", "refcount", "buffer-lifetime"],
  "confidence": 0.95,
  "was_correct": true
}
```

发现 Agent 每次分析新问题时先查此文件，匹配历史相似问题的修复经验（精确匹配 > 模式匹配 > 模糊匹配）。超过 30 天的记录权重降低。

## 8. 配置参数

### 8.0 参数默认值

以下参数均可由外层脚本通过环境变量覆盖：

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `MAX_ROUNDS` | 5 | 单次运行最大迭代轮数，超限后生成报告退出 |
| `DEADLINE_HOUR` | 6 | 截止时间（24 小时制），接近此时间点时优雅退出 |
| `MIN_CONFIDENCE` | 0.7 | 修复置信度下限，低于此值跳过修复标记为 NEEDS_REVIEW |
| `REVIEW_CONFIDENCE` | 0.9 | 修复置信度上限，高于此值自动提交，介于两者之间需人工审查 |
| `MAX_FILES_PER_FIX` | 5 | 单次修复最多允许修改的文件数 |
| `MAX_LINES_PER_FIX` | 200 | 单次修复最多允许修改的行数 |
| `STALL_ROUNDS` | 2 | 连续 N 轮问题数不减少判定为停滞 |
| `LEARNING_DECAY_DAYS` | 30 | error-learning.jsonl 中超过此天数的记录权重降至 0.5 |

### 8.1 场景（Scenario）定义

每次反馈闭环运行对应一个场景，场景按**子系统代码仓名称**划分（如 `storage-engine`、`metadata-service`）。场景决定：
- 运行数据存储路径：`feedback-runs/<scenario>/<run_id>/`
- flock 锁文件：`/tmp/feedback-loop-<scenario>.lock`（各场景独立，可并行运行不同场景）
- error-learning.jsonl 文件：`feedback-runs/<scenario>/error-learning.jsonl`（各场景独立积累经验）

外层脚本通过 `repos.yaml` 遍历子系统仓库列表，每个仓库名称即为 scenario。

## 9. 安全机制

### 9.1 多层防护

| 层级 | 机制 |
|------|------|
| 系统级 | `timeout` 包裹整个流程；`flock` 防重入（各场景独立锁）；信号处理优雅退出 |
| 流程级 | MAX_ROUNDS 上限；DEADLINE_HOUR 截止；停滞检测；恶化检测 |
| 闭环 A 层级级 | L1 不通过不进 L2 |
| 修复级 | MAX_FILES_PER_FIX / MAX_LINES_PER_FIX；置信度守门；3 次重试上限；回归测试 |

### 9.2 恶化处理

修复引入的新问题比修复的还多时：
1. 回滚本轮所有修复 commit
2. 标记 state.yaml 为 ABORTED
3. 生成报告（标注恶化原因）
4. 立即退出

## 10. 报告格式

每个闭环独立生成报告：

```markdown
# 反馈闭环报告 — 2026-03-25（闭环 A：编译+测试）

## 概要

| 指标 | 值 |
|------|-----|
| 运行时间 | 22:00 ~ 01:30 (3.5h) |
| 闭环类型 | A（编译+测试） |
| 迭代轮次 | 3 |
| 终止原因 | 收敛 |
| 初始问题 | L1: 2, L2: 6 |
| 最终问题 | L1: 0, L2: 0 |
| 修复成功 | 6 |
| 跳过（需人工） | 2 |

## 层级进展

| 轮次 | 层级 | 发现 | 修复 | 跳过 | 新增 | 剩余 |
|------|------|------|------|------|------|------|
| 1    | L1   | 2    | 2    | 0    | 0    | 0    |
| 2    | L2   | 6    | 4    | 2    | 0    | 2    |
| 3    | L2   | 2    | 2    | 0    | 0    | 0    |

## 修复详情

### L2 测试反馈
#### [FIXED] ISSUE-001: use-after-free in replica_handle_sync (CRITICAL)
- **根因**：sync_buf 在异步回调注册后立即释放
- **修复**：引用计数延长生命周期
- **置信度**：0.95 · **commit**: a1b2c3d

## 需人工关注

1. ISSUE-003 需人工审查（置信度 0.75）

## 错误学习

本次新增 6 条到 error-learning.jsonl。
```

## 11. 与现有体系的集成点

### 11.1 与 Skills 的关系

| Skill | 闭环 | 使用场景 |
|-------|------|---------|
| `code/tdd-workflow` | A | 开发工程师在 L2 使用 TDD 流程 |
| `code/lint-check` | A | 集成测试工程师在 L1 调用静态分析 |
| `code/code-review` | B | 集成测试工程师在 L3 可选调用 |
| `code/code-refactor` | B | 开发工程师在 L3 使用重构流程 |

### 11.2 与 Agents 的关系

反馈闭环复用现有 Agent 角色，不定义专用 Agent：

| 角色 | Agent | 反馈闭环中的职责 |
|------|-------|-----------------|
| 裁判（编排） | A10 `project-manager` | 轮次控制、终止判断、任务分派 |
| 判别器（发现） | A6 `integration-tester` | 编译检查、测试执行、代码分析 |
| 生成器（修复） | A2 `developer` | 直接修正、TDD 修复、重构 |

项目经理是团队通用角色（不仅限于反馈闭环），同样适用于并行开发调度、跨子系统协调等场景。

### 11.3 与 Hooks 的关系

| Hook | 作用 |
|------|------|
| H1 `pre-commit-lint` | 开发工程师 commit 前触发 clang-tidy |
| H2 `post-edit-format` | 开发工程师编辑后触发 clang-format |

### 11.4 与 Rules 的关系

`.claude/rules/` 规则对反馈闭环中的 Agent 同样生效：
- R2 `git-workflow.md`：conventional commits
- R3 `coding-style.md`：C 编码规范
- R4 `testing.md`：TDD 流程、覆盖率 ≥80%

## 12. 待定事项

- [ ] 闭环 B（L3 分析反馈）的具体检测手段和修复策略——初步方向：Agent 阅读分析 + clang-tidy（代码度量）混合模式，阈值复用 R3 coding-style 中的标准（函数 >50 行、文件 >800 行、圈复杂度 >10）
- [x] ~~配置参数的完整定义~~ → 已在第 8 章定义默认值
- [ ] 外层脚本的具体实现——存放路径：`scripts/feedback-loop.sh`，通过 `repos.yaml` 遍历子系统仓库，各 scenario 独立运行
- [ ] 闭环 A 和闭环 B 的触发策略——初步方案：闭环 A 由 CI 在 merge to main 后触发，闭环 B 每周定期触发（或迭代结束时手动触发）
- [x] ~~项目经理 Agent（A10）的完整角色定义~~ → 已收录到 extensions-catalog.md Agents 清单（A10），完整 Agent 文件在实施阶段创建
- [x] ~~场景（scenario）定义~~ → 已在第 8.1 章定义
