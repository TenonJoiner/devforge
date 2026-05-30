# 扩展清单

## 五、Skills 清单（14 个）

> 产品级 6 个启发式 skill（按思考模式拆分），含 `product/verify` 解决变更回溯问题（P5）。代码级 8 个 skill，含 `code/spec-review` 覆盖特性级交付件评审（P2+P6）和 `code/systematic-debug` 覆盖系统化调试（P3）。测试验证级不设独立 skill——测试策略设计由 `product/test-design` 调度测试 Agent 执行，测试用例开发在 `tests/` 目录下走 OpenSpec workflow（由 `integration-tester`/`perf-tester` 作为执行 Agent），测试执行通过脚本或夜间 CI 触发。

### 5.0 产品级 Skills（6 个，解决 P1+P4+P5）

> 产品级设计是持续 2-3 个月的创意迭代过程——架构↔需求↔接口反复纠缠，重要的是**输出质量**而非**流程控制**。因此产品级与 OpenSpec 彻底脱离，用 6 个启发式 skill（按思考模式拆分）替代原 product-design schema。

| # | Skill | 思考模式 | 适用交付物 | 核心启发方法 |
|---|-------|---------|-----------|------------|
| PS1 | `product/explore` | 探索性思考 | vision.md、architecture/、子系统分解 | 竞品分析框架 + 多方案探索（≥3 候选）+ 质量属性五维评估（性能/一致性/可靠性/可维护性/扩展性）+ ADR 输出 + 置信度守门（≥90% 推进）。**执行角色**：`architect`(A1) |
| PS2 | `product/define` | 定义性思考 | requirements/、interfaces/ | Feature-Scenario 两级结构（Scenario 独立可验收）+ 场景挖掘（正常+4 种故障）+ 接口契约设计 + 非功能需求量化。**执行角色**：`architect`(A1) |
| PS3 | `product/plan` | 规划性思考 | iteration-plan.md（含测试相关 proposal） | MVP 识别 + 依赖图分析 + 并行分组（Wave）+ 复杂度估算（S/M/L）+ 递归深化 + 测试相关 proposal 生成。**执行角色**：`project-manager`(A10) 编排 + `architect`(A1) 技术可行性判断 |
| PS4 | `product/review` | 审视性思考 | 所有产品级文档 + test-strategy.md + 各级测试方案 | 跨文档一致性检查 + 完备性检查 + 红旗检测 + 两轮评审（AI + 人员交叉）。**执行角色**：`architect`(A1) 主导，按需调度其他 Agent 参与评审 |
| PS5 | `product/test-design` | 定义性思考 | test-strategy.md、各级测试方案 | 测试分层定义（单测/集成/系统/性能边界）+ 覆盖率目标分配 + 集成测试方案（组件交互/接口契约/故障注入）+ 系统测试方案（多节点/一致性/故障恢复）+ 性能测试方案（基准/压力/回归检测）。**执行角色**：调度 `integration-tester`(A6) 设计集成/系统测试方案，调度 `perf-tester`(A7) 设计性能测试方案 |
| PS6 | `product/verify` | 审视性思考 | 产品级文档 vs 特性级（spec/design/code） | 全量双向一致性检查：对比所有已实现 feature 的 spec/design/code 与产品级文档，识别不一致点并判断方向——上行同步（特性级变更合理，建议更新产品级文档）或下行修正（违反产品级设计，建议修正特性级文档/代码）。输出不一致清单 + 方向判断 + 修改建议，由人确认。**执行角色**：`architect`(A1) 主导 |

**关键特性**：
- **可反复使用**：没有"完成"状态，只有"当前最佳版本"。愿景、架构、需求随时可以回来迭代
- **无固定顺序**：explore/define/plan 可以任意顺序执行，review 随时可以对任何文档执行
- **与特性级衔接**：iteration-plan.md 的每个 proposal 名称使用 kebab-case，团队人工通过 `/opsx:propose <name>` 启动特性级开发

**推荐前置条件**（非强制，按需提示）：

| Skill | 推荐前置条件 | 说明 |
|-------|------------|------|
| PS1 explore | — | 起点，无前置条件 |
| PS2 define | 已有初步架构（explore 至少执行一轮） | 需求定义参考架构子系统划分 |
| PS3 plan | 已有需求和接口（define 至少执行一轮） | 迭代计划依赖 Feature-Scenario 分解 |
| PS4 review | 已有至少一份产品级文档 | 需要评审对象 |
| PS5 test-design | 已有架构和需求 | 测试方案依赖子系统划分和接口定义 |
| PS6 verify | 特性级已有实现产出（spec/design/code） | 需要对比对象 |

**产品级交付物目录结构**：

```
docs/                         # 产品级交付物（不在 openspec/ 下）
├── vision.md                         # 产品愿景
├── architecture/                     # 架构设计
│   ├── design.md                     #   系统级总纲
│   └── <subsystem>/                  #   子系统架构
├── adr.md                            # 架构决策记录（跨架构与需求）
├── requirements/                     # 需求规格
│   └── <feature-domain>.md
├── interfaces/                       # 接口规格
│   └── <subsystem>.md
└── iteration-plan.md                 # 迭代计划 + proposal 清单
```

### 5.1 代码级 Skills（8 个，解决 P2+P3+P6）

| # | Skill | 用途 | 借鉴来源 |
|---|-------|------|---------|
| S1 | `code/tdd-workflow` | TDD 铁律：RED-GREEN-REFACTOR + 借口反驳表，聚焦 C 语言单元测试（CMocka） | superpowers/test-driven-development |
| S2 | `code/code-review` | 代码评审三级管线：通用检视（CRITICAL/HIGH/MEDIUM/LOW）→ C 语言专项（内存安全/并发/指针/错误处理）→ 安全审计（OWASP/STRIDE + 分布式存储安全） | everything-claude-code/code-reviewer + agency-agents/code-reviewer + gstack/cso |
| S3 | `code/spec-review` | 特性级交付件评审：proposal/spec/design/tasks 每阶段质量检查——proposal 是否符合产品级需求、spec 是否完整可验收、design 是否可实现、tasks 分解是否合理。可在 `/opsx:continue` 前手动调用，也可独立使用 | OpenSpec verify 三维评估 + product/review |
| S4 | `code/code-refactor` | 代码简化重构 + 死代码清除，保持测试绿色 | everything-claude-code/refactor-cleaner + Claude Code 内置 /simplify |
| S5 | `code/parallel-develop` | 多 Agent 并行协调 + 冲突检测 + Wave/Checkpoint | superpowers/dispatching-parallel-agents + SuperClaude/parallel.py |
| S6 | `code/lint-check` | 编译器警告 + clang-tidy 静态分析：`gcc -Wall -Wextra -Werror` + `clang-tidy` | everything-claude-code/rules/cpp（理念借鉴） |
| S7 | `code/git-worktree` | git worktree 并行开发，隔离环境最佳实践 | superpowers/using-git-worktrees |
| S8 | `code/systematic-debug` | 系统化调试四阶段：根因调查（日志/core dump/strace/gdb）→ 多分量诊断（隔离可疑模块）→ 数据流向后追踪（从症状向输入追溯）→ 验证修复（铁律：NO FIX WITHOUT ROOT CAUSE）。聚焦 C 语言分布式存储场景：内存损坏定位（ASan/valgrind）、并发死锁分析（helgrind/锁序图）、网络协议异常追踪、状态机不一致诊断 | superpowers/systematic-debugging |

### SKILL.md 格式规范

参考 superpowers 的 CSO 原则 + gstack 的 allowed-tools 机制：

```yaml
---
name: skill-name
description: Use when [触发条件]    # CSO 原则：只写触发条件，不写流程
version: 1.0.0
allowed-tools: [Read, Write, ...]  # 最小权限（参考 gstack）
---
```

正文结构：

````markdown
# Skill Name

## Overview
一句话核心原则 + Core principle 强调句。

## When to Use
- 适用场景
- 不适用场景

## The Iron Law（核心铁律，如有）
```code
不可违反的绝对规则
```

## 核心流程
分阶段详细说明，含 Good/Bad 对比代码示例。

## Red Flags
停止并重来的反模式信号。

## Common Rationalizations（如有）
| 借口 | 现实 |
|------|------|

## Verification Checklist
- [ ] 检查项 1
- [ ] 检查项 2

## Integration
与哪些 skill/agent 协作。
````

---

## 六、Agents 清单（10 个）

> 按存储开发团队的实际角色定义 Agent，遵循 **Agent 专业化原则**——专注于特定领域、拥有受限工具的 Agent 优于拥有全部权限的通用 Agent。专业化本身就是上下文管理策略：每个 Agent 因为携带更少的无关信息，运行在更高效的"Smart Zone"内。原 `backend-developer`（4 种认知模式）拆分为 `developer`（生成式）+ `code-reviewer`（批判式）+ `debugger`（侦探式），原 `test-engineer` 拆分为 `integration-tester`（功能验证）+ `perf-tester`（性能验证）。流程驱动与执行工作分离：产品级由人驱动 + skill 辅助，特性级由 OpenSpec 引擎驱动——但实际执行工作的是这些 Agent。项目经理负责反馈闭环编排、并行开发调度和跨子系统协调。夜间 CI 由脚本编排，复用 integration-tester 和 developer 角色。

| # | Agent | 定位 | Model | 解决 | 借鉴来源 |
|---|-------|------|-------|------|---------|
| A1 | `architect` | 架构师：系统架构设计、子系统分解、技术选型、ADR、需求分解分配。**关注数据分布策略、副本一致性模型、故障域划分、存储引擎分层（元数据/数据/索引）、IO 路径设计** | opus | P1,P2 | everything-claude-code/architect + agency-agents/software-architect |
| A2 | `developer` | C 语言开发工程师：TDD 实现、代码重构、构建问题。**只写代码，不审代码**。关注内存安全、并发正确性（锁序/无锁结构/竞态）、错误码传播链、IO 管线、状态机、引用计数 | sonnet | P3 | superpowers/tdd + everything-claude-code/cpp-reviewer |
| A3 | `code-reviewer` | 代码评审工程师：三级评审管线（通用检视→C 语言专项→安全审计）。**只审代码，不写代码**（Read-heavy，极少 Write）。关注代码质量分级（CRITICAL/HIGH/MEDIUM/LOW）、内存安全模式、并发正确性模式、错误处理完备性 | sonnet | P3,P6 | everything-claude-code/code-reviewer + agency-agents/code-reviewer |
| A4 | `debugger` | 调试工程师：系统化调试四阶段（根因调查→多分量诊断→数据流追踪→验证修复）。**铁律：NO FIX WITHOUT ROOT CAUSE**。关注内存损坏定位（ASan/valgrind）、并发死锁分析（helgrind/锁序图）、网络协议异常追踪、状态机不一致诊断、gdb/strace/core dump 分析。**使用时机**：手动 `/df:debug` 触发 + 夜间 CI 复杂失败时由 PM 分派介入（developer 无法直接修复的场景） | sonnet | P3 | superpowers/systematic-debugging |
| A5 | `frontend-developer` | 前端开发工程师：管理工具/CLI/UI 开发、代码评审。**关注集群拓扑可视化、存储容量/性能监控展示、运维操作安全确认**。在前端代码的 `/opsx:apply` 中担任执行 Agent（兼任开发+评审，因前端代码不适用 A3 的 C 语言专项评审管线） | sonnet | P3 | everything-claude-code/code-reviewer |
| A6 | `integration-tester` | 集成/系统测试工程师：集成测试和系统测试方案设计与执行。**关注多节点数据一致性验证、故障注入（磁盘/网络/进程）、组件交互验证、接口契约验证、故障恢复验证、数据完整性校验** | sonnet | P4 | agency-agents/testing + gstack/qa |
| A7 | `perf-tester` | 性能测试工程师：性能测试方案设计与执行。**关注 IOPS/吞吐/延迟基准测试、性能回归检测、热点分析（perf/flamegraph）、资源瓶颈定位、压力测试、性能调优建议** | sonnet | P4 | agency-agents/testing |
| A8 | `security-engineer` | 安全工程师：**里程碑级**专项安全审计、威胁建模（STRIDE）、数据完整性、传输安全。**关注存储访问控制、数据加密（静态/传输）、多租户隔离、篡改检测**。与 A3 的分工：A3 在每次代码评审中执行**常规**安全检查（第三级管线），A8 在版本发布前/安全敏感特性完成后执行**深度**专项审计（威胁建模、攻击面分析、渗透测试方案） | sonnet | P3,P6 | everything-claude-code/security-reviewer + gstack/cso + agency-agents/security-engineer |
| A9 | `doc-writer` | 文档工程师：客户文档写作与评审。**关注存储概念解释（副本/分片/一致性级别）、运维操作手册、故障排查指南、性能调优指南**。**使用时机**：特性归档（`/opsx:archive`）后编写/更新用户文档 + 版本发布前文档收尾 | sonnet | P6 | agency-agents/technical-writer + SuperClaude/technical-writer |
| A10 | `project-manager` | 项目经理：反馈闭环编排（裁判角色）、并行开发调度、跨子系统协调。**不直接检查或修复代码**，只做调度和决策。**使用时机**：① 产品级 PS3 迭代计划编排 ② 跨子系统特性的并行开发协调（冲突检测+任务分派） ③ 夜间 CI 失败分级决策（简单失败→分派 developer 修复 / 复杂失败→分派 debugger 定位根因） ④ 反馈闭环中控制对抗轮次、判断收敛和终止，分派任务给 A6（判别器）和 A2（生成器） | opus | P3,P4 | SuperClaude/pm_agent + gstack/plan-ceo |

**Agent 与 Skill 映射关系**：

| Agent | 主要对应 Skill | 工具权限特征 |
|-------|--------------|-------------|
| A1 `architect` | `product/explore` + `product/define` + `product/review` + `product/verify` | 全权限（Read/Write/Edit/Bash） |
| A2 `developer` | `code/tdd-workflow` + `code/code-refactor` | 全权限（Read/Write/Edit/Bash） |
| A3 `code-reviewer` | `code/code-review` + `code/spec-review` | 读重写轻（Read/Grep/Glob 为主，极少 Edit） |
| A4 `debugger` | `code/systematic-debug` | 调查型（Read/Grep/Bash[gdb/valgrind/strace]） |
| A5 `frontend-developer` | `code/tdd-workflow`（前端仓上下文） | 全权限（Read/Write/Edit/Bash） |
| A6 `integration-tester` | `product/test-design`（集成/系统测试方案） | 测试执行型（Read/Write/Edit/Bash[编译运行测试]） |
| A7 `perf-tester` | `product/test-design`（性能测试方案） | 基准测试型（Read/Write/Edit/Bash[perf/flamegraph/benchmark]） |
| A8 `security-engineer` | —（里程碑专项审计，无独立 Skill） | 读重写轻（Read/Grep/Glob/Bash[静态分析工具]） |
| A9 `doc-writer` | —（文档编写，无独立 Skill） | 全权限（Read/Write/Edit） |
| A10 `project-manager` | `product/plan` + `code/parallel-develop` | 编排型（Read/Grep/Glob/Agent，不直接 Edit 代码） |

**各 Agent 使用场景总览**：

> 下表列出每个 Agent 在各工作流阶段的调用点。"—"表示该阶段不参与。

| Agent | 产品级 | 特性级 | 质量收尾 / 夜间 CI | 独立手动触发 |
|-------|--------|--------|-------------------|------------|
| A1 `architect` | PS1 explore + PS2 define + PS4 review + PS6 verify 执行角色 | — | — | `/df:explore` `/df:define` `/df:product-review` `/df:verify` |
| A2 `developer` | — | 生产代码 `/opsx:apply`：TDD 循环 + 重构 | Q.1-Q.2 编译+单测；夜间 CI 修复 | `/df:tdd` `/df:refactor` |
| A3 `code-reviewer` | — | 生产代码 `/opsx:apply`：代码检视 (N.M.6) | Q.4 全量 diff 评审 | `/df:review` `/df:spec-review` |
| A4 `debugger` | — | — | 夜间 CI 复杂失败：PM 分派介入定位根因 | `/df:debug` |
| A5 `frontend-developer` | — | 前端代码 `/opsx:apply`：TDD + 重构 + 评审（全周期） | — | `/df:tdd`（前端代码上下文） |
| A6 `integration-tester` | PS5 集成/系统测试方案设计 | 测试代码 `/opsx:apply`：编写集成/系统测试用例 | Q.3 冒烟验证；夜间 CI 执行+分析 | — |
| A7 `perf-tester` | PS5 性能测试方案设计 | 测试代码 `/opsx:apply`：编写性能测试用例 | 夜间 CI 执行+分析 | — |
| A8 `security-engineer` | — | — | — | 里程碑安全审计（版本发布前 / 安全敏感特性完成后） |
| A9 `doc-writer` | — | `/opsx:archive` 后编写用户文档 | — | 版本发布前文档收尾 |
| A10 `project-manager` | PS3 plan 计划编排 | 跨子系统特性并行开发协调 | 夜间 CI 失败分级决策 | 并行开发冲突协调 |

**分组详解**：

**产品级 Agent（A1 + A10）**：

| 阶段 | Agent | 做什么 | 触发方式 |
|------|-------|-------|---------|
| **架构探索** | `architect`(A1) | 作为 PS1 `product/explore` 执行角色：竞品分析、多方案探索、质量属性评估、ADR 输出 | `/df:explore` |
| **需求定义** | `architect`(A1) | 作为 PS2 `product/define` 执行角色：Feature-Scenario 分解、接口契约设计、非功能需求量化 | `/df:define` |
| **迭代计划** | `project-manager`(A10) + `architect`(A1) | A10 编排计划结构（MVP 识别、Wave 分组、复杂度估算），A1 提供技术可行性判断和依赖分析 | `/df:plan` |
| **文档评审** | `architect`(A1) 主导 | 作为 PS4 `product/review` 执行角色：跨文档一致性检查、完备性检查、红旗检测 | `/df:product-review` |
| **一致性验证** | `architect`(A1) 主导 | 作为 PS6 `product/verify` 执行角色：产品级文档 vs 特性级 spec/design/code 的双向一致性检查 | `/df:verify` |

**测试 Agent（A6 + A7）**：

| 阶段 | Agent | 做什么 | 触发方式 |
|------|-------|-------|---------|
| **产品级：测试策略设计** | `integration-tester`(A6) + `perf-tester`(A7) | 作为 PS5 执行角色：A6 设计集成/系统测试方案（组件交互、故障注入、一致性验证），A7 设计性能测试方案（基准指标、压力场景、回归检测阈值）。输出纳入 test-strategy.md | `/df:test-design` 内部调度 |
| **特性级：测试用例开发** | `integration-tester`(A6) 或 `perf-tester`(A7) | 在 `tests/` 目录下的 `/opsx:apply` 中作为执行 Agent（替代生产代码中 `developer` 的角色），编写集成/性能测试代码。遵循 R4 `testing.md` 中的 Mock 纪律、环境搭建/拆除、故障注入验证标准 | `tests/` 目录的 `/opsx:apply` |
| **夜间 CI / 质量收尾** | `integration-tester`(A6) + `perf-tester`(A7) | 执行测试套件 → 分析失败用例（区分环境问题/真实缺陷）→ 生成结构化 bug 报告（含复现步骤、根因初判、影响范围）。`developer`(A2) 根据报告修复 | 夜间 CI 脚本编排；`/opsx:apply` 质量收尾 Q.3 |

**调试 Agent（A4）**：

| 场景 | 触发条件 | 做什么 |
|------|---------|-------|
| **手动调试** | 开发者遇到难以定位的问题，执行 `/df:debug` | 系统化调试四阶段：根因调查→多分量诊断→数据流追踪→验证修复 |
| **夜间 CI 复杂失败** | PM(A10) 判定失败根因不明确，分派 debugger 介入 | 分析 CI 日志/core dump → 定位根因 → 输出诊断报告（含根因、影响范围、修复建议）→ 交由 developer(A2) 修复 |

> **与 `developer`(A2) 的调试边界**：developer 处理**明确的**测试失败（错误信息直接指向问题代码，可直接修复）。debugger 处理**不明确的**失败（崩溃、数据损坏、间歇性失败、并发竞态等需要深入调查的场景）。

**安全 Agent（A8）与 A3 的分工**：

| 维度 | A3 `code-reviewer`（常规安全检查） | A8 `security-engineer`（里程碑安全审计） |
|------|----------------------------------|---------------------------------------|
| **触发频率** | 每次代码评审自动执行（三级管线第三级） | 里程碑节点手动触发（版本发布前/安全敏感特性完成后） |
| **检查范围** | 单次变更的 diff 范围 | 全系统或子系统级别的完整审计 |
| **检查深度** | 代码模式匹配（硬编码密钥、注入漏洞、缓冲区溢出） | 威胁建模（STRIDE）、攻击面分析、数据流安全分析、渗透测试方案设计 |
| **输出物** | 评审意见（CRITICAL/HIGH/MEDIUM/LOW 分级） | 安全审计报告（威胁清单 + 风险评级 + 缓解方案 + 遗留风险声明） |

**文档 Agent（A9）的使用时机**：

| 时机 | 触发条件 | 做什么 |
|------|---------|-------|
| **特性归档后** | `/opsx:archive` 完成后 | 根据归档的 spec/design 编写或更新用户文档（API 参考、使用指南、配置说明） |
| **版本发布前** | 版本发布决策后 | 收尾全量文档：更新版本变更日志、补齐缺失文档、校验文档与代码一致性 |

**前端 Agent（A5）的工作模式**：

> A5 在前端代码（管理工具/CLI/UI）的 `/opsx:apply` 中担任全周期执行 Agent——兼任开发（TDD）+ 评审。因前端代码不适用 A3 的 C 语言三级评审管线（内存安全/并发/指针检查），由 A5 自行完成前端相关的代码评审（可读性/组件结构/状态管理/UI 一致性）。

**关键分工边界**：

| 边界 | 左侧 | 右侧 | 判断标准 |
|------|------|------|---------|
| 单元测试 vs 集成测试 | `developer`(A2) 编写 | `integration-tester`(A6) 编写 | 进程内无外部依赖 → 单测；跨组件/跨节点/真实 IO → 集成 |
| 常规安全 vs 专项审计 | `code-reviewer`(A3) 执行 | `security-engineer`(A8) 执行 | 单次 diff 的模式匹配 → 常规；全系统威胁建模 → 专项 |
| 简单失败 vs 复杂失败 | `developer`(A2) 直接修复 | `debugger`(A4) 定位根因 | 错误信息明确可直接修 → 简单；崩溃/竞态/间歇性 → 复杂 |
| C 代码评审 vs 前端评审 | `code-reviewer`(A3) 执行 | `frontend-developer`(A5) 自行评审 | `.c/.h` 文件 → A3；前端代码 → A5 |
| 编排决策 vs 技术执行 | `project-manager`(A10) 决策 | 其他 Agent 执行 | 调度/分派/终止判断 → PM；实际编码/测试/审计 → 对应 Agent |

### Agent 格式规范

参考 everything-claude-code 的 YAML frontmatter + agency-agents 的 Persona/Operations 二元架构：

```yaml
---
name: agent-name
description: 触发条件描述（含 PROACTIVELY 关键词指导自动激活时机）
tools: ["Read", "Write", "Grep", ...]   # allowed-tools 白名单（最小权限）
model: opus | sonnet | haiku
---

# Agent Name

## Identity
角色认同：你是谁、你的专业领域。

## Core Mission
核心任务和优先级排序。

## Critical Rules
不可违背的规则（列表形式，5-7 条）。

## Workflow
工作流程（分步骤，含决策分支）。

## Deliverables
交付物模板（结构化输出格式）。

## Success Metrics
可量化成功指标（如：0 个 CRITICAL 漏洞、内存泄漏检出率 > 95%）。

## Communication Style
沟通风格（如：直接指出问题，不说"有趣"，给出具体修复建议）。
```

---

## 七、Commands 清单（13 个，/df: 前缀）

> `/df:parallel` 和 `/df:worktree`（创建）仅作为 Skill 存在，由 `opsx:apply` 内部调度，不设独立命令。`/df:switch-worktree` 供用户手动切换 worktree 或切回主干。

teamskills 的自建命令使用 `/df:` 前缀，与 OpenSpec 的 `/opsx:` 前缀区分。

### 7.0 产品级 Commands（6 个，解决 P1+P4+P5）

| # | Command | 用途 | 解决 | 映射 Skill |
|---|---------|------|------|-----------|
| C1 | `/df:explore` | 探索架构方案、竞品分析、子系统分解 | P1 | product/explore |
| C2 | `/df:define` | 定义需求、接口契约、验收标准 | P1 | product/define |
| C3 | `/df:plan` | 制定迭代计划和 proposal 清单 | P1 | product/plan |
| C4 | `/df:product-review` | 多维评审产品级文档 | P1,P6 | product/review |
| C5 | `/df:test-design` | 制定测试策略和具体测试方案 | P4 | product/test-design |
| C6 | `/df:verify` | 全量双向一致性检查：产品级文档 vs 特性级 spec/design/code | P5 | product/verify |

### 7.1 代码级 Commands（7 个）

| # | Command | 用途 | 解决 | 映射 Skill |
|---|---------|------|------|-----------|
| C7 | `/df:tdd` | 启动 TDD 开发流程（RED-GREEN-REFACTOR） | P3 | code/tdd-workflow |
| C8 | `/df:review` | 启动代码评审（三级管线） | P3,P6 | code/code-review |
| C9 | `/df:spec-review` | 特性级交付件评审（proposal/spec/design/tasks） | P2,P6 | code/spec-review |
| C10 | `/df:refactor` | 启动代码重构（保持测试绿色） | P3 | code/code-refactor |
| C11 | `/df:lint` | 运行编译检查 + 静态分析 | P3 | code/lint-check |
| C12 | `/df:switch-worktree` | 切换到指定 worktree 或切回主干（更新 `.claude/active-worktree` 状态文件，配合 worktree-guard hook 实现写操作守护） | P3 | code/git-worktree |
| C13 | `/df:debug` | 启动系统化调试流程（根因调查→多分量诊断→数据流追踪→验证修复） | P3 | code/systematic-debug |

### 与 OpenSpec 命令的分工

| 层级 | 命令前缀 | 示例 |
|------|---------|------|
| 产品级 | `/df:` | `/df:explore`、`/df:define`、`/df:plan`、`/df:product-review`、`/df:test-design`、`/df:verify` |
| 特性级 | `/opsx:` | `/opsx:propose feature-xxx`、`/opsx:continue`、`/opsx:apply`、`/opsx:verify`、`/opsx:archive` |
| 代码级 | `/df:` | `/df:tdd`、`/df:review`、`/df:spec-review`、`/df:refactor`、`/df:lint`、`/df:switch-worktree`、`/df:debug` |

> **测试验证级不设 `/df:*` 命令**：测试用例开发在 `tests/` 目录下走 OpenSpec workflow（由 `integration-tester`/`perf-tester` 作为执行 Agent），测试执行通过脚本触发，不需要专门的 skill 和 command。

### `/opsx:apply` 与代码级 Skills 的关系

`/opsx:apply` 是特性级的**编排入口**，代码级的 `/df:*` skills 是**被调度的执行单元**。两者是调用者与被调用者的关系，不是并列关系。

**正常流程（走完整特性级工作流）**：

```
/opsx:apply
  │ 读取 tasks.md
  │
  │ ┌─ worktree 创建隔离工作区
  │ │
  │ │ 遍历每条实现 task：
  │ ├─→ tdd       RED-GREEN-REFACTOR 循环（N.M.1 ~ N.M.4）
  │ ├─→ refactor  代码简化重构（N.M.5）
  │ ├─→ review    代码检视（N.M.6）
  │ ├─→ commit    提交到 worktree 分支（N.M.7）
  │ │
  │ │ 所有实现 task 完成后：
  │ ├─→ Q.1 全量编译 + clang-tidy 静态分析
  │ ├─→ Q.2 全量单元测试（确保无回归）
  │ ├─→ Q.3 集成测试冒烟（integration-tester 执行核心路径验证）
  │ ├─→ Q.4 代码评审收尾（code-reviewer 全量 diff 评审）
  │ │
  │ └─→ merge     合并回主干 + 清理 worktree
```

**调度机制详解**：

| 机制 | 说明 |
|------|------|
| **Skill 引用** | `/opsx:apply` 的 instruction 中通过 `/df:tdd`、`/df:refactor`、`/df:review` 等命令名引用代码级 skill。Claude Code 自动加载对应 SKILL.md |
| **上下文传递** | 每个 task 携带：spec 中的对应 Requirement/Scenario + design 中的技术方案 + 前序 task 的 commit 记录。通过 tasks.md 中的引用关系串联 |
| **并行策略** | tasks.md 中标注 `[并行: 是]` 的 task 由 parallel-develop skill（S5）调度到独立 subagent 并行执行，共享同一 worktree 分支。标注 `[并行: 否]`（同文件修改）的 task 串行执行 |
| **失败处理** | 单个 task 的 VERIFY-RED/VERIFY-GREEN 失败时暂停该 task 并报告，不影响其他并行 task。所有 task 完成后统一运行质量收尾（Q.1-Q.4） |
| **质量收尾 Agent 调度** | Q.1-Q.2 由 `developer`(A2) 执行（编译和单元测试是开发者职责）；Q.3 由 `integration-tester`(A6) 执行（集成测试冒烟验证核心路径）；Q.4 由 `code-reviewer`(A3) 执行（全量 diff 评审） |

**独立使用（不走 OpenSpec 流程）**：

代码级的每个 `/df:*` 命令也支持开发者手动直接调用，覆盖不经过 OpenSpec 的场景（如修 bug、写工具函数）。此时开发者自行决定调用哪些 skills，不受 `opsx:apply` 编排。

---

## 八、Hooks 清单（3 条）

> 只保留真正有价值且不扰民的 hook。变更回溯统一由 `/df:verify`（PS6）主动触发。

| # | Hook | 类型 | 功能 | 解决 | 借鉴来源 |
|---|------|------|------|------|---------|
| H1 | `pre-commit-lint` | PreToolUse(Bash) | 提交前**增量** `clang-tidy` 静态分析：matcher 精确匹配 `git commit` 命令，仅对本次 staged 的 `.c/.h` 文件运行 clang-tidy（`git diff --cached --name-only --diff-filter=ACM -- '*.c' '*.h'`），避免全量扫描耗时过长 | P3 | everything-claude-code/hooks |
| H2 | `post-edit-format` | PostToolUse(Edit) | clang-format 自动格式化 | P3 | everything-claude-code/hooks |
| H3 | `worktree-guard` | PreToolUse(Edit/Write) | **worktree 写操作守护**：读取 `.claude/active-worktree` 状态文件，当存在活跃 worktree 时，仅放行活跃 worktree 目录内和项目外的写操作，拦截对主干代码及其他非活跃 worktree 的写操作（读操作不拦截，避免高频触发的性能开销）。`/df:switch-worktree` 执行时自动更新状态文件，guard 随之切换守护范围。防止会话中断、compaction 导致记忆丢失后误操作 | P3 | 自创 |

---

## 九、Rules 清单（4 个）

> 放置在 `.claude/rules/` 目录下，由 Claude Code 自动加载。C 语言相关规则使用 `paths:` frontmatter 限定只对 `.c/.h` 文件生效，节省上下文。

| # | Rule | 路径限定 | 内容 | 解决 | 借鉴来源 |
|---|------|---------|------|------|---------|
| R1 | `workflow.md` | 无（全局） | 四层工作流规范（产品级→特性级→代码级→测试验证级）、OpenSpec 与 teamskills 的分工、审批节点、子系统分工、接口对齐、冲突解决、并行开发规约、**漂移信号检测**：`/opsx:archive` 归档时扫描「新增发现」「架构偏离」标签，累计超过阈值（3 个未处理）时提示执行 `/df:verify` | P1,P2,P3,P4,P5 | OpenSpec schema + gstack + SuperClaude + superpowers |
| R2 | `git-workflow.md` | 无（全局） | conventional commits、分支策略、multi-repo 协作 | P3 | everything-claude-code/rules/common |
| R3 | `coding-style.md` | `**/*.c`, `**/*.h` | C11/C17 标准、命名规范、头文件组织、宏使用纪律、小文件（<800行）、小函数（<50行）、缓冲区溢出防护、整数溢出检查、指针生命周期、pthread 锁序/原子操作、返回值必检、密钥管理、输入验证 | P3 | everything-claude-code/rules/cpp（适配 C） |
| R4 | `testing.md` | `**/*.c`, `**/*.h` | 测试分层标准（单测/集成/系统/性能边界）、覆盖率目标（≥80%）、TDD 工作流、CMocka 框架使用规范、故障注入、valgrind memcheck/helgrind、sanitizer 使用、**集成测试编写规则**（见下方详细说明） | P3,P4 | everything-claude-code + superpowers/tdd |

#### R4 集成测试编写规则（详细补充）

R4 `testing.md` 中集成测试部分需包含以下规则：

**Mock 纪律（与 spec-driven-enhanced tasks 模板一致）**：
- 子系统内部模块之间**禁止 mock**，测试必须走真实的内部调用链
- 只允许 mock 子系统外部边界（外部 RPC、外部服务依赖、外部存储介质模拟）
- 每个 mock 必须注释说明：mock 了什么、为什么必须 mock、mock 行为与真实行为的差异

**环境搭建/拆除要求**：
- 每个集成测试套件必须有独立的 `setup()`/`teardown()`，确保测试间无状态泄漏
- 文件系统测试使用临时目录（`mkdtemp`），teardown 时清理
- 网络测试使用随机端口绑定，避免端口冲突
- 多进程测试使用 `waitpid` 确保子进程正确回收，避免僵尸进程
- 数据库/存储引擎测试使用独立数据目录，teardown 时完整清除

**故障注入验证标准**：
- 磁盘故障：使用 `fallocate` + 只读挂载 / `LD_PRELOAD` 注入 IO 错误，验证错误处理路径
- 网络故障：使用 `iptables`/`tc` 模拟丢包/延迟/分区，验证超时和重试逻辑
- 进程故障：使用 `kill -9` 模拟崩溃，验证重启后数据完整性和状态恢复
- 并发故障：使用 `helgrind`/`TSan` 检测竞态，使用延迟注入放大时间窗口

**多节点测试编排规则**：
- 使用进程模拟多节点（单机多进程），Docker 按需用于需要网络隔离的场景
- 节点启动顺序和时机必须可控（支持延迟启动、乱序启动）
- 每个多节点测试必须验证至少一种故障场景（节点宕机/网络分区/脑裂）
- 一致性验证：写入后读取验证、多副本数据比对、故障恢复后数据完整性校验

**集成测试反模式（Red Flags）**：
- 🚩 mock 了子系统内部模块（应走真实调用链）
- 🚩 测试通过但未验证数据正确性（只检查返回码不检查数据内容）
- 🚩 无故障场景（只测试 happy path）
- 🚩 测试间有隐式状态依赖（执行顺序影响结果）
- 🚩 硬编码端口/路径（导致并行运行冲突）
