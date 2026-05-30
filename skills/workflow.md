# 工作流串联

## 十、工作流串联

### 10.1 四层关系总览

```
产品级（启发式 Skills + /df: 命令，与 OpenSpec 脱离）──────────────
  /df:explore ←→ /df:define ←→ /df:plan（反复迭代，无固定顺序）
      │               │              │
      ▼               ▼              ▼
  vision.md    requirements/    iteration-plan.md
  architecture/  interfaces/    （含测试相关 proposal）
      │
      │ /df:test-design（测试策略 + 各级测试方案）
      │ /df:product-review（多维评审 + 红旗检测）
      │
      └── proposal 清单（人工执行）
          ▼
特性级（OpenSpec spec-driven-enhanced schema + /opsx:* 命令）─────────
  proposal → specs → design → review（评审门禁）→ tasks
  → /opsx:apply → /opsx:verify → /opsx:archive
          │                               │
          │ apply 阶段调度代码级             │ 合并 Delta + 归档
          ▼                               │
代码级（teamskills /df:* skills）──────────────────────────────
  worktree 隔离 → /df:tdd(R→G→R) → /df:refactor → /df:lint
  → /df:review → commit
          │                                          │
          │ 单元测试通过                                │ 触发测试验证级
          ▼                                          ▼
测试验证级（独立测试目录 workflow（待定义）+ 脚本执行）─────────────
  测试用例开发（独立测试目录走专用 workflow）
  → 脚本执行（集成测试 + 性能测试）→ merge
          │                                           │
          │ 测试失败反馈代码级                             │ 测试通过
          ▼                                           ▼
       ┌──── 变更反馈回路 ──────────────────────────────┘
       ▼
  /df:verify: 全量双向一致性检查（产品级文档 ↔ 特性级 spec/design/code）
```

> **四层边界说明**：代码级聚焦"写对代码"（单元测试验证函数/模块内部逻辑），测试验证级聚焦"集成正确"（验证跨子系统交互、端到端行为、性能指标）。两层通过 commit 事件衔接。测试用例开发在独立测试仓中走 OpenSpec workflow，测试执行通过脚本触发，不设专门的 `/df:*` 命令。

### 10.2 产品级流程（启发式 Skill 驱动）

产品级设计是持续 2-3 个月的创意迭代过程——架构↔需求↔接口反复纠缠，重要的是**输出质量**而非**流程控制**。因此产品级与 OpenSpec 彻底脱离，使用 6 个启发式 skill（按思考模式拆分）辅助思考。

**触发方式**：`/df:explore`、`/df:define`、`/df:plan`、`/df:product-review`、`/df:test-design`、`/df:verify`

典型迭代流程（非强制顺序，可反复执行）：

1. `/df:explore` → 探索架构方案、竞品分析、子系统分解
   - 输出：docs/vision.md、docs/architecture/
   - 置信度 ≥90% 后推进，否则继续探索
2. `/df:define` → 定义需求、接口契约、验收标准
   - 输出：docs/requirements/、docs/interfaces/
   - 铁律：每个 Scenario 可独立验收，每个接口有错误处理契约
3. `/df:plan` → 制定迭代计划和 proposal 清单（含测试相关 proposal）
   - 输出：docs/iteration-plan.md
   - MVP 优先 → 依赖分析 → 最大化并行（Wave 分组）
4. `/df:test-design` → 制定测试策略和具体测试方案
   - 输出：test-strategy.md、集成测试方案、性能测试方案
   - 测试分层定义（单元测试 vs 集成测试边界）+ 覆盖率目标分配 + 集成测试方案（跨子系统交互/接口契约/故障注入/数据一致性/故障恢复）+ 性能测试方案（基准/压力/回归检测）
5. `/df:product-review` → 多维评审所有产品级文档（含 test-strategy.md 和各级测试方案）
   - 跨文档一致性 + 完备性 + 红旗检测
   - 两轮评审：AI 评审 + 人员交叉评审
6. `/df:verify` → 全量双向一致性检查
   - 对比所有已实现 feature 的 spec/design/code 与产品级文档
   - 识别不一致点，判断方向：上行同步（特性级变更合理，建议更新产品级文档）或下行修正（违反产品级设计，建议修正特性级文档/代码）
   - 输出：不一致清单 + 方向判断 + 修改建议，由人确认

**可反复迭代**：愿景可以回来改，架构可以反复迭代，需求可以随时调整。没有"完成"状态，只有"当前最佳版本"。评审发现问题后回到对应 skill 修正。

产品级文档就绪后，团队根据 iteration-plan.md 中的 proposal 清单和并行分组，人工逐个通过 `/opsx:propose <name> ` 启动特性级开发。

### 10.3 特性级流程

**触发方式**：`/opsx:propose <feature-name> `

OpenSpec 引擎按 spec-driven-enhanced schema 的依赖图推进：

1. 生成 proposal.md（遵循产品级约束，追溯到 iteration-plan 条目）
   - `/df:spec-review` → 检查 proposal 是否符合产品级需求
2. `/opsx:continue` → 生成 specs/\*\*/\*.md（Delta 格式特性规格）
   - `/df:spec-review` → 检查 spec 是否完整可验收
3. `/opsx:continue` → 生成 design.md（技术设计）
   - `/df:spec-review` → 检查 design 是否可实现
4. `/opsx:continue` → 生成 review.md（设计评审，新增 artifact）
   - **第一阶段：AI 迭代评审**（最多 5 轮）
     - 评审维度：完整性、正确性、一致性、安全性、性能影响、可维护性
     - 自动修复 CRITICAL/HIGH 问题，重复直到清零或达到 5 轮上限
   - **第二阶段：人员交叉评审**（AI 评审达标后）
     - 评审人员：本模块技术 leader（必须）+ 其他模块开发人员（≥1 人）
     - 聚焦：领域知识判断、跨子系统影响、可落地性、历史踩坑经验
   - **技术 leader 签字**：
     - APPROVED → 继续进入 tasks
     - CONDITIONAL → 修复指定问题后重新评审
     - REJECTED → 回到 design 阶段
5. `/opsx:continue` → 生成 tasks.md（TDD 粒度任务清单，前置条件：leader 签字 APPROVED）
   - `/df:spec-review` → 检查 tasks 分解是否合理
6. `/opsx:apply` → 按 tasks.md 逐条实现（调度代码级 skills）
7. `/opsx:verify` → 三维验证（完整性/正确性/一致性）
8. `/opsx:archive` → 合并 Delta + 归档

> `/df:spec-review` 与 review artifact 的区别：

| 维度 | `/df:spec-review`（S3，轻量质检） | review artifact（正式评审门禁） |
|------|----------------------------------|-------------------------------|
| **触发方式** | 手动调用 `/df:spec-review`，每个 `/opsx:continue` 前可选执行 | `/opsx:continue` 自动生成 review.md |
| **检查范围** | 单个 artifact（当前阶段的 proposal/spec/design/tasks） | proposal + specs + design 三者整体 |
| **检查深度** | 快速质检：格式完整性、产品级追溯、明显缺漏 | 六维深度评审：完整性/正确性/一致性/安全性/性能/可维护性 |
| **阻塞能力** | 不阻塞，仅建议修改 | CRITICAL/HIGH 问题硬阻塞进入 tasks |
| **人员参与** | 无 | 技术 leader 签字 + 跨模块评审 |
| **适用场景** | 快速确认当前 artifact 质量再推进 | design 完成后的正式评审门禁 |

### 10.4 代码级流程（每个 task 的执行循环）

**触发方式**：`/opsx:apply` 阶段自动调度，或手动 `/df:tdd`

**`/opsx:apply` 编排流程**：

```
/opsx:apply
  │ 读取 tasks.md
  │
  │ ┌─ worktree skill 创建隔离工作区
  │ │  （/df:switch-worktree 切换工作区）
  │ │
  │ │ 遍历每条实现 task：
  │ ├─→ /df:tdd      RED-GREEN-REFACTOR 循环（N.M.1 ~ N.M.4）
  │ ├─→ /df:refactor  代码简化重构（N.M.5）
  │ ├─→ /df:review    代码检视（N.M.6）
  │ ├─→ commit        提交到 worktree 分支（N.M.7）
  │ │
  │ │ 所有实现 task 完成后：
  │ ├─→ 质量收尾（Q.1 ~ Q.4）
  │ │
  │ └─→ merge     合并回主干 + 清理 worktree
```

**单个 task 执行步骤**：

1. TDD 铁律循环（/df:tdd）：
   - TEST: 编写失败测试（CMocka 框架）→ VERIFY-RED: 确认失败
   - IMPL: 写最小实现 → VERIFY-GREEN: 确认通过
   - REFACTOR: `/df:refactor` 代码简化重构 → VERIFY-GREEN: 再次确认
2. `/df:lint` 编译检查（`gcc -Wall -Wextra -Werror`）+ clang-tidy 静态分析
3. `/df:review` 三级代码评审（通用检视 → C 语言专项 → 安全审计）
4. git commit（conventional commits 格式）

**自动化 Hook 守护**（全程生效）：

| Hook | 类型 | 功能 |
|------|------|------|
| H1: pre-commit-lint | PreToolUse(Bash) | 提交前 clang-tidy 静态分析 |
| H2: post-edit-format | PostToolUse(Edit) | 编辑后 clang-format 自动格式化 |
| H3: worktree-guard | PreToolUse(Edit/Write) | worktree 写操作守护，防止误写主干或非活跃 worktree |

> `/opsx:apply` 是特性级的**编排入口**，代码级的 `/df:*` skills 是**被调度的执行单元**，两者是调用者与被调用者的关系。代码级的每个 `/df:*` 命令也支持开发者手动直接调用，覆盖不经过 OpenSpec 的场景（如修 bug、写工具函数）。并行开发（parallel skill）和 worktree 创建由 `/opsx:apply` 内部调度，不设独立命令。

### 10.5 测试验证级流程（代码合并前的验证关卡）

> 测试验证级不设 `/df:*` 命令。测试用例开发在独立测试目录中走 OpenSpec workflow，测试执行通过脚本触发。

**测试方案来源**：

- 产品级 `/df:test-design`（PS5）统一定义测试策略和测试方案（集成测试 + 性能测试）
- `/df:plan`（PS3）在 iteration-plan.md 中生成测试相关的 proposal 条目
- `/df:product-review`（PS4）对 test-strategy.md 和各级测试方案进行评审

**测试用例开发**：

在 `tests/` 目录下走 OpenSpec workflow（测试专用 schema 待定义，不复用功能代码的 spec-driven-enhanced）：
1. 测试 proposal 追溯到产品级 iteration-plan.md 中的测试条目
2. 测试 workflow 需要单独设计，因为集成测试的关注点（测试拓扑、环境管理、故障注入、数据策略）与功能开发（架构设计、TDD、代码实现）本质不同

**测试执行**：

通过脚本触发：

1. **集成测试**：跨模块交互验证（接口契约 + 故障注入 + 数据一致性 + 多节点故障恢复）
2. **性能测试**（按需）：吞吐量/延迟基准测试，对比历史数据检测性能回归
3. 全部测试通过 → 允许合并
4. 测试失败 → 反馈代码级修复

**变更反馈回路**：

测试通过并合并后，通过 `/df:verify`（PS6）执行全量双向一致性检查，识别产品级文档与特性级 spec/design/code 之间的不一致，确保上下层文档同步更新。
