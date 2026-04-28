# 实施优先级

## 完整性交叉验证

> 下表列出所有交付物及其所属 Phase，确保设计文档中的每个条目都已纳入实施计划。

| 类别 | 编号 | 名称 | Phase | 解决问题 |
|------|------|------|-------|---------|
| **Skills（14）** | | | | |
| | PS1 | `product/explore` | 2 | P1 |
| | PS2 | `product/define` | 2 | P1 |
| | PS3 | `product/plan` | 2 | P1 |
| | PS4 | `product/review` | 5 | P1,P6 |
| | PS5 | `product/test-design` | 5 | P4 |
| | PS6 | `product/verify` | 5 | P5 |
| | S1 | `code/tdd-workflow` | 3 | P3 |
| | S2 | `code/code-review` | 3 | P3,P6 |
| | S3 | `code/spec-review` | 4 | P2,P6 |
| | S4 | `code/code-refactor` | 3 | P3 |
| | S5 | `code/parallel-develop` | 4 | P3 |
| | S6 | `code/lint-check` | 3 | P3 |
| | S7 | `code/git-worktree` | 3 | P3 |
| | S8 | `code/systematic-debug` | 4 | P3 |
| **Agents（10）** | | | | |
| | A1 | `architect` | 2 | P1,P2 |
| | A2 | `developer` | 3 | P3 |
| | A3 | `code-reviewer` | 3 | P3,P6 |
| | A4 | `debugger` | 4 | P3 |
| | A5 | `frontend-developer` | 5 | P3 |
| | A6 | `integration-tester` | 5 | P4 |
| | A7 | `perf-tester` | 5 | P4 |
| | A8 | `security-engineer` | 5 | P3,P6 |
| | A9 | `doc-writer` | 5 | P6 |
| | A10 | `project-manager` | 5 | P3,P4 |
| **Commands（13）** | | | | |
| | C1 | `/ky:explore` | 2 | P1 |
| | C2 | `/ky:define` | 2 | P1 |
| | C3 | `/ky:plan` | 2 | P1 |
| | C4 | `/ky:product-review` | 5 | P1,P6 |
| | C5 | `/ky:test-design` | 5 | P4 |
| | C6 | `/ky:verify` | 5 | P5 |
| | C7 | `/ky:tdd` | 3 | P3 |
| | C8 | `/ky:review` | 3 | P3,P6 |
| | C9 | `/ky:spec-review` | 4 | P2,P6 |
| | C10 | `/ky:refactor` | 3 | P3 |
| | C11 | `/ky:lint` | 3 | P3 |
| | C12 | `/ky:switch-worktree` | 3 | P3 |
| | C13 | `/ky:debug` | 4 | P3 |
| **Rules（4）** | | | | |
| | R1 | `workflow` | 2 | P1-P5 |
| | R2 | `git-workflow` | 3 | P3 |
| | R3 | `coding-style` | 3 | P3 |
| | R4 | `testing` | 3 | P3,P4 |
| **Hooks（3）** | | | | |
| | H1 | `pre-commit-lint` | 3 | P3 |
| | H2 | `post-edit-format` | 3 | P3 |
| | H3 | `worktree-guard` | 3 | P3 |

---

## Phase 1：基础设施 — OpenSpec 集成 + 特性级 Schema

**目标**：安装 OpenSpec，创建 spec-driven-enhanced schema，验证特性级工作流可用。

**前置依赖**：无

**交付物**：

| # | 交付物 | 文件路径 |
|---|--------|---------|
| 1.1 | 安装 OpenSpec | `npm install -g openspec` 或项目本地安装 |
| 1.2 | spec-driven-enhanced schema 定义 | `openspec/schemas/spec-driven-enhanced/schema.yaml` |
| 1.3 | proposal 模板 | `openspec/schemas/spec-driven-enhanced/templates/proposal.md` |
| 1.4 | spec 模板 | `openspec/schemas/spec-driven-enhanced/templates/spec.md` |
| 1.5 | design 模板 | `openspec/schemas/spec-driven-enhanced/templates/design.md` |
| 1.6 | review 模板（新增 artifact） | `openspec/schemas/spec-driven-enhanced/templates/review.md` |
| 1.7 | tasks 模板（TDD 粒度增强） | `openspec/schemas/spec-driven-enhanced/templates/tasks.md` |
| 1.8 | config.yaml 模板 | `openspec/config.yaml.template` |

**验证**：
- `openspec schema validate spec-driven-enhanced` — schema 合法性验证
- 在 teamskills 仓库中执行 `/opsx:propose test-change` → `/opsx:continue`（逐步推进）→ 验证 5 个 artifact 均可正常生成

---

## Phase 2：产品级核心 + 分发基础设施

**目标**：建立产品级文档生产能力、骨架工作流规范，为后续代码级能力提供上层约束。

**前置依赖**：Phase 1（schema 可用）

> **为什么产品级先于代码级？** spec-driven-enhanced schema 的 instruction 依赖产品级文档（proposal 需追溯 iteration-plan、spec 需追溯 requirements、design 需参考 architecture）。R1 workflow 是整个四层体系的骨架规则，代码级 skill 应在其约束下开发。

**交付物**：

Skills（3 个产品级文档生产能力）：

| # | 交付物 | 文件路径 |
|---|--------|---------|
| 2.1 | PS1 `product/explore` — 探索性思考 | `.claude/skills/devforge-explore/SKILL.md` |
| 2.2 | PS2 `product/define` — 定义性思考 | `.claude/skills/devforge-define/SKILL.md` |
| 2.3 | PS3 `product/plan` — 规划性思考 | `.claude/skills/devforge-plan/SKILL.md` |

Agent（1 个）：

| # | 交付物 | 文件路径 |
|---|--------|---------|
| 2.4 | A1 `architect` — PS1/PS2/PS4/PS6 执行角色 | `.claude/agents/architect.md` |

Commands（3 个产品级命令）：

| # | 交付物 | 文件路径 |
|---|--------|---------|
| 2.5 | C1 `/ky:explore` | `.claude/commands/explore.md` |
| 2.6 | C2 `/ky:define` | `.claude/commands/define.md` |
| 2.7 | C3 `/ky:plan` | `.claude/commands/plan.md` |

Rule（1 个骨架规则）：

| # | 交付物 | 文件路径 |
|---|--------|---------|
| 2.8 | R1 `workflow` — 四层工作流规范 | `.claude/rules/workflow.md` |

基础设施：

| # | 交付物 | 文件路径 |
|---|--------|---------|
| 2.9 | 产品级参考模板（7 个） | `.claude/templates/{ref-requirements,ref-architecture,ref-paper,arch-subsystem,arch-system,req-overview,req-feature}.md` |
| 2.10 | 产品级交付物目录骨架 | `docs/{vision.md, architecture/, requirements/, interfaces/, adr.md, iteration-plan.md}` |

**验证**：
- `/ky:explore` 执行一轮架构探索，启发式思考引导有效，输出 ADR 和架构文档
- 验证 Claude Code 正确识别并加载 skills/agents/commands/rules

---

## Phase 3：代码级日常工作流 — 开发者每日可用

**目标**：建立完整的日常开发循环——TDD + 重构 + 代码评审 + 静态分析 + worktree 隔离 + 自动化守护，此时已有产品级文档支撑和 R1 约束。

**前置依赖**：Phase 2（R1 workflow 规范已建立）

> **为什么 S4 code-refactor 在 Phase 3 而非 Phase 4？** 每个 TDD 循环的步骤 N.M.5 调用 `/ky:refactor` 进行代码简化重构，S4 是日常开发循环的必需组件，不是补充能力。

**交付物**：

Skills（5 个代码级日常核心）：

| # | 交付物 | 文件路径 |
|---|--------|---------|
| 3.1 | S1 `code/tdd-workflow` — TDD 铁律 RED-GREEN-REFACTOR | `.claude/skills/devforge-tdd-workflow/SKILL.md` |
| 3.2 | S2 `code/code-review` — 三级评审管线 | `.claude/skills/devforge-code-review/SKILL.md` |
| 3.3 | S4 `code/code-refactor` — 代码简化重构 | `.claude/skills/devforge-code-refactor/SKILL.md` |
| 3.4 | S6 `code/lint-check` — 编译检查 + clang-tidy | `.claude/skills/devforge-lint-check/SKILL.md` |
| 3.5 | S7 `code/git-worktree` — worktree 并行开发 | `.claude/skills/devforge-git-worktree/SKILL.md` |

Agents（2 个）：

| # | 交付物 | 文件路径 |
|---|--------|---------|
| 3.6 | A2 `developer` — C 语言开发工程师（只写不审） | `.claude/agents/developer.md` |
| 3.7 | A3 `code-reviewer` — 代码评审工程师（只审不写） | `.claude/agents/code-reviewer.md` |

Commands（5 个代码级日常命令）：

| # | 交付物 | 文件路径 |
|---|--------|---------|
| 3.8 | C7 `/ky:tdd` | `.claude/commands/tdd.md` |
| 3.9 | C8 `/ky:review` | `.claude/commands/review.md` |
| 3.10 | C10 `/ky:refactor` | `.claude/commands/refactor.md` |
| 3.11 | C11 `/ky:lint` | `.claude/commands/lint.md` |
| 3.12 | C12 `/ky:switch-worktree` | `.claude/commands/switch-worktree.md` |

Rules（3 个代码级规范）：

| # | 交付物 | 文件路径 |
|---|--------|---------|
| 3.13 | R2 `git-workflow` — conventional commits + 分支策略 | `.claude/rules/git-workflow.md` |
| 3.14 | R3 `coding-style` — C 语言编码规范（`paths: **/*.c, **/*.h`） | `.claude/rules/coding-style.md` |
| 3.15 | R4 `testing` — 测试分层 + TDD + 集成测试编写规则（`paths: **/*.c, **/*.h`） | `.claude/rules/testing.md` |

Hooks（3 条自动化守护，统一配置于 `.claude/hooks.json`）：

| # | 交付物 | 说明 |
|---|--------|------|
| 3.16 | H1 `pre-commit-lint` | PreToolUse(Bash)：提交前增量 clang-tidy，仅扫描 staged 的 `.c/.h` 文件 |
| 3.17 | H2 `post-edit-format` | PostToolUse(Edit)：编辑后 clang-format 自动格式化 |
| 3.18 | H3 `worktree-guard` | PreToolUse(Edit/Write)：worktree 写操作守护，防止误写主干 |

**验证**：
- `/ky:tdd` 在 C 项目中执行完整 RED-GREEN-REFACTOR 循环，测试先红后绿
- `/ky:review` 执行三级评审管线（通用 → C 语言专项 → 安全审计），输出分级评审意见
- `/ky:refactor` 对代码执行简化重构，保持测试绿色
- H1 提交前触发 clang-tidy，H2 编辑后触发 clang-format，H3 在 worktree 外写操作时拦截

---

## Phase 4：代码级补充能力 — 特性评审 + 并行开发 + 系统化调试

**目标**：补齐代码级剩余能力——特性级交付件评审、多 Agent 并行协调、系统化调试。

**前置依赖**：Phase 3（日常开发工作流已就绪）

**交付物**：

Skills（3 个代码级补充）：

| # | 交付物 | 文件路径 |
|---|--------|---------|
| 4.1 | S3 `code/spec-review` — 特性级交付件评审 | `.claude/skills/devforge-spec-review/SKILL.md` |
| 4.2 | S5 `code/parallel-develop` — 多 Agent 并行协调 | `.claude/skills/devforge-parallel-develop/SKILL.md` |
| 4.3 | S8 `code/systematic-debug` — 系统化调试四阶段 | `.claude/skills/devforge-systematic-debug/SKILL.md` |

Agent（1 个）：

| # | 交付物 | 文件路径 |
|---|--------|---------|
| 4.4 | A4 `debugger` — 调试工程师（NO FIX WITHOUT ROOT CAUSE） | `.claude/agents/debugger.md` |

Commands（2 个代码级补充命令）：

| # | 交付物 | 文件路径 |
|---|--------|---------|
| 4.5 | C9 `/ky:spec-review` | `.claude/commands/spec-review.md` |
| 4.6 | C13 `/ky:debug` | `.claude/commands/debug.md` |

**验证**：
- `/ky:spec-review` 对一个 OpenSpec proposal/spec/design 执行质量检查，输出格式完整性和产品级追溯结果
- `/ky:debug` 执行系统化调试四阶段（根因调查→多分量诊断→数据流追踪→验证修复）

---

## Phase 5：产品级质量保障 + 补充 Agent

**目标**：补齐产品级评审、测试策略制定、一致性验证能力，以及所有剩余 Agent 角色。

**前置依赖**：Phase 4（代码级能力完整，有实现产出可供评审和验证）

> **为什么 PS4/PS5/PS6 在 Phase 5 而非 Phase 2？** PS4 product-review 需要评审对象（至少一份产品级文档）——这在 Phase 2 完成后即可用，但其价值在特性级开发产出后更大。PS5 test-design 需要架构和需求（explore/define 完成后）。PS6 verify 需要特性级实现产出（spec/design/code）作为对比对象。整体上，这三个 skill 在代码级能力就绪后使用效果最佳。

**交付物**：

Skills（3 个产品级质量保障）：

| # | 交付物 | 文件路径 |
|---|--------|---------|
| 5.1 | PS4 `product/review` — 多维评审 + 跨文档一致性 + 红旗检测 | `.claude/skills/devforge-review/SKILL.md` |
| 5.2 | PS5 `product/test-design` — 测试策略 + 各级测试方案 | `.claude/skills/devforge-test-design/SKILL.md` |
| 5.3 | PS6 `product/verify` — 全量双向一致性检查 | `.claude/skills/devforge-verify/SKILL.md` |

Agents（6 个补充角色）：

| # | 交付物 | 文件路径 | 说明 |
|---|--------|---------|------|
| 5.4 | A6 `integration-tester` | `.claude/agents/integration-tester.md` | PS5 执行角色 + 反馈闭环判别器 |
| 5.5 | A7 `perf-tester` | `.claude/agents/perf-tester.md` | PS5 执行角色 |
| 5.6 | A10 `project-manager` | `.claude/agents/project-manager.md` | PS3 编排 + 反馈闭环裁判 |
| 5.7 | A5 `frontend-developer` | `.claude/agents/frontend-developer.md` | 前端仓全周期执行 |
| 5.8 | A8 `security-engineer` | `.claude/agents/security-engineer.md` | 里程碑级专项安全审计 |
| 5.9 | A9 `doc-writer` | `.claude/agents/doc-writer.md` | 归档后文档编写 + 版本发布收尾 |

Commands（3 个产品级质量命令）：

| # | 交付物 | 文件路径 |
|---|--------|---------|
| 5.10 | C4 `/ky:product-review` | `.claude/commands/product-review.md` |
| 5.11 | C5 `/ky:test-design` | `.claude/commands/test-design.md` |
| 5.12 | C6 `/ky:verify` | `.claude/commands/verify.md` |

**验证**：
- `/ky:product-review` 评审产品级文档，跨文档一致性检查和红旗检测正常工作
- `/ky:test-design` 输出 test-strategy.md，含测试分层定义和各级测试方案
- `/ky:verify` 执行产品级 vs 特性级一致性检查，输出不一致清单和方向建议

---

## Phase 6：反馈闭环 — 自动化质量保障

**目标**：建立 GAN 式对抗反馈闭环，自动发现并修复代码问题。

**前置依赖**：Phase 5（A6 integration-tester + A10 project-manager + A2 developer 三个角色就绪）

**交付物**：

| # | 交付物 | 文件路径 | 说明 |
|---|--------|---------|------|
| 6.1 | 闭环 A 外层脚本 | `scripts/feedback-loop.sh` | 编译+测试反馈循环（时间守护、flock 防重入、git 分支管理、归档） |
| 6.2 | 闭环 B 设计预埋 | — | 代码分析闭环，具体实现后续完善 |
| 6.3 | 跨会话学习机制 | `feedback-runs/<scenario>/error-learning.jsonl` | Reflexion 模式，错误学习与预防 |
| 6.4 | 夜间 CI 场景列表 | `scripts/scenarios.yaml` | 子系统场景列表，各场景独立运行 |

**验证**：
- 手动触发闭环 A 外层脚本，编译+测试反馈循环正常收敛
- A10（裁判）正确控制 L1→L2 递进和终止判断
- A6（判别器）输出结构化 issues.yaml，A2（生成器）输出 fixes.yaml
- 恶化检测正常触发回滚

---

## Phase 依赖关系

```
Phase 1 ─→ Phase 2 ─→ Phase 3 ─→ Phase 4 ─→ Phase 5 ─→ Phase 6
基础设施     产品级核心    代码级日常    代码级补充    产品级质量    反馈闭环
(OpenSpec)   (PS1-3,A1,   (S1-2,4,6-7  (S3,5,8     (PS4-6,      (脚本,
              R1,分发)     A2-3,R2-4,   A4,C9,13)   A5-10,       学习,CI)
                          H1-3,C7-8,               C4-6)
                          10-12)
```

各 Phase 严格顺序执行，前一 Phase 验证通过后进入下一 Phase。
