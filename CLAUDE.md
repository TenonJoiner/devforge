# DevForge — 复杂基础软件开发 TeamSkills 框架

## 项目概述

DevForge 是一个面向复杂基础软件（如分布式存储、数据库、操作系统内核）的三层 TeamSkills 开发框架：

- **产品级**：架构探索、需求定义、迭代规划与测试策略（`/df:product-design`、`/df:product-define`、`/df:plan`、`/df:test-design`）
- **特性级**：基于 OpenSpec 的规范驱动开发——OpenSpec 引擎提供流程编排（`/opsx:*`），DevForge 提供 artifact 生成与评审能力（`/df:research`、`/df:define`、`/df:design`、`/df:spec-review`）
- **代码级**：TDD 工作流、代码评审、简化重构、调试、编译检查、Worktree 隔离（`/df:tdd`、`/df:code-review`、`/df:simplify`、`/df:debug`、`/df:lint`、`/df:switch-worktree`、`/df:finish-worktree`）

### 核心设计理念

1. **以 OpenSpec 为底座**：特性级开发使用 OpenSpec 的 spec-driven-enhanced schema，确保 proposal → specs → design → tasks 的严格依赖链
2. **自动化质量守护**：通过 hooks（pre-commit、post-edit 等）和 agents（developer、tester、reviewer）实现编码规范、测试覆盖、代码质量的自动化保障

## 目录结构

### 开发目录

- `.claude/` — 项目配置与框架定义
  - `agents/` — 预定义的专业化 agent（developer、tester、architect、reviewer 等）
  - `rules/` — 编码规范、Git 工作流、测试规范（R1-R4 分层规则）
  - `templates/` — 文档模板（产品级需求、架构、迭代计划等）
  - `skills/` — 本项目定义的所有 skills（产品级、特性级、代码级）
  - `hooks/` — 自动化守护 hooks（pre-commit、post-edit、post-test 等）
- `skills/` — Skill 设计文档与实现方案（framework 设计、agent 职责定义、workflow 规范）
- `test-skill/` — Skill 开发测试目录

### 文档目录（仅作 skill 输出沉淀，与框架本身无关）

- `docs/`、`docs-v0.1/` — 产品级 skill 试运行的产出物归档，用于回看 skill 输出质量

### OpenSpec 目录（仅作 skill 输出沉淀，与框架本身无关）

- `openspec/` — 特性级 skill 试运行的产出物归档（OpenSpec 引擎工作目录）

### 参考资料

- `reference/` — 参考的开源项目与框架
  - `OpenSpec/` — OpenSpec 框架源码
  - `agency-agents/`、`agent-skills/` — Agent 实现参考
  - `claude-plugins-official/`、`everything-claude-code/` — Claude Code 官方资料
  - `gstack/`、`SuperClaude_Framework/`、`superpowers/` — 其他 AI 开发框架

---

## Skill 设计核心规范

### 1. Skill 四文件分工

Skill 由四个文件构成，职责严格分离，避免内容重复和职责混乱：

- **SKILL.md**（编排法典）：主会话加载，定义阶段结构、agent 调度规则（何时派遣哪个角色、数量要求）、质量门禁、串并行约束、文件 I/O 规则。**禁止**包含 agent 人设描述、文档章节结构、模板内容。
- **Command**（启动引导，≤60 行）：用户可见，一句话说明 + 用法示例 + 产出物清单。**禁止**包含流程细节、agent 调度逻辑、质量标准。
- **Agent.md**（独立人格）：子 agent 加载，定义身份（专业领域、角色定位）、能力边界（能做/不能做）、通用输出标准、协作原则。**禁止**包含具体阶段流程、何时被派遣、文档章节结构。
- **Template**（内容契约）：agent 按需读取，定义必填章节、可选章节、每个章节的内容要求、自检清单、示例片段。**禁止**包含流程逻辑、agent 调度、由谁写作。

**去重铁律**：Agent.md 不描述"产出后如何评审"（属于 SKILL.md）、"写入哪个文件"（属于 SKILL.md）、"文档包含哪些章节"（属于 Template）；SKILL.md 不描述"architect 是什么角色"（属于 Agent.md）。

### 2. 主会话职责边界

主会话是调度中枢，不是执行者。职责边界清晰可防止主会话越界做 agent 的事，导致上下文膨胀和质量下降。

**应该做**：
- 交互式调研（询问用户、读取配置文件、检测现有文档）
- 调度编排（决定派遣哪个 agent、何时派遣、传递什么 prompt）
- 状态跟踪（记录哪些阶段完成、哪些 agent 产出了什么）
- 质量门禁（检查 agent 产出是否符合格式要求、是否通过评审）
- 判定推进（决定是继续下一阶段、回退修正、还是等待用户决策）

**不应该做**：
- 深度专业分析（应由 architect/researcher agent 完成）
- 内容创作（应由产出 agent 完成，主会话不 Write 大文档）
- 读取 agent 完整产出（只读 ≤5 行轻量摘要，避免上下文污染）
- 委托 plan agent 生成调度方案（plan agent 是脆弱的对话中间件，方案易丢失）

### 3. Skill 自解释与可移植性

Skill 文件必须自包含所有执行所需的信息，不依赖项目特定配置。这确保 skill 可以在任何使用 DevForge 框架的项目中使用。

**核心要求**：
- Skill 文件**禁止引用 CLAUDE.md**（项目特定配置，不同项目内容不同）
- Skill 文件**可以引用框架基础设施**（`.claude/agents/`、`.claude/templates/`、`.claude/rules/`），这些是框架的一部分
- 项目特定信息（如系统类型、编程语言、测试框架）必须通过**交互式提问**从用户处获取，或通过**自动探测**（读取 package.json、Cargo.toml、pom.xml 等标准配置文件）获得
- **禁止** version/changelog 字段，版本历史由 git 管理（避免手动维护版本号导致的不一致）

**可移植性边界**：Skill 依赖 `.claude/agents/`、`.claude/templates/`、`.claude/rules/` 是合理的，因为它们是 DevForge 框架的标准组成部分。项目特定信息通过交互或探测获取，不硬编码、不依赖特定配置文件。

### 4. 术语统一规范

跨 skill 的术语必须统一，避免同一概念在不同 skill 中使用不同名称，导致用户和 agent 理解混乱。

**基础设施层（强制统一）**：
- **问题分级**：CRITICAL（阻塞性问题）、HIGH（严重问题）、MEDIUM（一般问题）、LOW（建议改进）
- **推进模式**：自动推进（无需确认直接进入下一阶段）、确认后推进（等待用户输入"继续"）、等待人工决策（列出选项，用户选择后推进）

**流程骨架层（命名规则）**：
- 主流程：统一用「第 X 阶段」（如"第 1 阶段：标杆研究"）
- 阶段内：统一用「步骤 X」（如"步骤 1：读取现有文档"）
- **禁止**混用同义词（轮/层/步/Phase/Round），避免术语混乱

### 5. Agent 预定义角色铁律

Agent 角色必须预定义在 `.claude/agents/` 中，禁止在 skill 运行时临时构造 agent。这确保 agent 人格稳定、能力边界清晰、可复用性高。

**核心要求**：
- 必须使用 `.claude/agents/` 中的**预定义角色**（如 `architect.md`、`product.md`、`developer.md`），禁止在 SKILL.md 中临时描述 agent 人格
- **禁止**"一个 agent 内部发散多方案"替代多 agent 独立产出（如禁止让 architect 一次性产出 3 个架构方案，应派遣 3 个 architect 独立产出）
- **禁止运行时 plan agent 调度**：主会话直接决定派遣哪个 agent（基于当前阶段、用户输入、文档状态），不委托给 plan agent 生成调度方案（plan agent 是脆弱的对话中间件，一旦会话中断方案丢失）

**同角色多实例**：当需要同角色多实例时（如 3 个 architect），通过 prompt 明确区分关注点（按范围切分、按约束侧重切分、按分析范式切分），确保视角独立性。
