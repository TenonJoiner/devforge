# CLAUDE.md

本文件为 Claude Code (claude.ai/code) 在本仓库中工作时提供指导。

## 项目概述

**teamskills** 是面向分布式存储开发团队的统一技能仓库，解决团队级 AI 辅助开发工作流的标准化问题。产品级使用启发式 Skills 辅助思考（与 OpenSpec 脱离），特性级基于 OpenSpec 的规范驱动开发，代码级和测试验证级使用 Claude Code 原生扩展。构建覆盖产品规划到代码交付全流程的 skill 体系。

## 核心定位

- **团队协作优先**：目标是团队整体提效和高效协作，减少并行开发冲突，而非个人开发者效率工具
- **分层驱动**：产品级用启发式 skill 辅助创意迭代（重输出质量），特性级用 OpenSpec 引擎驱动工作流（重流程控制）
- **统一技能仓库**：采用 Monorepo 模式，teamskills 作为产品级统一仓库，所有子系统代码位于同一仓库中，通过 `.claude/` 目录直接使用技能

## 要解决的问题

### P1: 缺少产品级规划视角

OpenSpec 侧重特性级别的 proposal，但团队实际需要从产品级视角出发：编写架构设计文档、需求规格文档、子系统架构设计，完成架构与需求在子系统间的分解分配和接口定义，最终生成产品级的迭代开发计划和详细的 proposal 清单。

### P2: 特性开发输出质量不足

OpenSpec 的 design/spec/task 输出质量有待提高。特性级产出应遵从产品级文档约束，task 应支持 TDD 测试驱动开发、多 Agent 并行开发，并集成单元测试、代码检视、代码简化重构等质量活动。

### P3: 代码开发阶段能力不足

缺少 TDD、多 Agent 代码检视、代码重构、git worktree 并行开发、代码规范 lint 及相应自动化 hook 等开发阶段的支撑能力。

### P4: 集成测试不成体系

经常使用 mock 跑单元测试或简单集成测试就认为通过。缺乏独立的集成测试方案设计和用例开发，集成测试与单元测试的边界不清晰。

### P5: 变更无法有效回溯同步

设计和开发过程中，方案或需求变更时缺乏同步到产品级文档的机制；特性范围或开发顺序变更时，也缺乏反馈同步机制。

### P6: 缺少文档评审能力

设计文档、需求文档、task 清单缺少系统化的评审手段。

## 设计原则

1. **以 OpenSpec 为基础扩展（特性级）+ 启发式 Skills（产品级）**：特性级以 OpenSpec workflow 为骨架。产品级与 OpenSpec 彻底脱离，使用 6 个启发式 skill（explore/define/plan/review/test-design/verify）按思考模式辅助设计——因为产品级是持续数月的创意迭代过程，重要的是输出质量而非流程控制
2. **产品级 → 特性级 → 代码级 → 测试验证级**：四层 skill 体系，上层约束下层，下层变更反馈上层。代码级聚焦"写对代码"（单元测试），测试验证级聚焦"集成正确"（集成测试/系统测试/性能测试）
3. **团队协作为核心**：所有 skill 设计围绕多人并行开发场景，而非单人单任务
4. **Monorepo 统一管理**：teamskills 仓库提供统一的 skill/agent/command/hook，所有子系统通过 `.claude/` 目录直接使用，无需额外安装
5. **用现成工具，不造轮子**：所有 skill/hook/command/agent 使用 Claude Code 内置能力、Linux 系统工具（gcc/make/git/grep/sed/awk 等）以及外部成熟工具（cppcheck、valgrind、clang-format、perf 等），不受限制。核心原则是**不自研工具**——避免为了配合 skill 体系而开发需要长期维护的自定义工具链。能用现成的就用现成的
6. **面向 C 语言 + Linux + 分布式存储**：团队主要使用 C 语言开发分布式存储系统，运行在 Linux 环境。分布式存储对**数据一致性**（强一致/最终一致、副本一致性、故障后数据完整性）和**性能**（低延迟、高吞吐、高并发）要求极高。对代码质量要求同样严苛：内存安全（无泄漏、无越界）、并发正确性（锁序、无锁结构、竞态检测）、错误处理完备性（每个返回值都必须检查）、编码规范一致性。所有 skill 和 rule 的设计应以 C 语言、Linux 系统编程和分布式存储场景为第一优先级
7. **中文写作**：所有 skill、command、agent、hook 及相关文档均使用中文编写，确保团队成员无阅读障碍
8. **MCP 依赖可选引入**：可以依赖外部 MCP 服务来增强能力，但优先选择免费可用、且无需翻墙即可直接访问的 MCP 服务。引入时需在文档中注明 MCP 服务名称、用途及访问方式

## 参考仓库

以下仓库作为设计和实现的参考素材，已克隆至本项目目录下：

### `OpenSpec/` — 规范驱动开发框架（workflow 骨架）

核心借鉴点：
- **规范驱动 workflow**：proposal → specs → design → tasks → implement → archive 完整生命周期
- **Delta 规范格式**：变更只声明 ADDED/MODIFIED/REMOVED 的需求差异，避免全量重写规范
- **Artifact 依赖图**：通过 YAML schema 定义工件类型及依赖关系（proposal → specs/design → tasks），支持自定义 workflow
- **Verify 三维评估**：完整性（所有需求是否覆盖）、正确性（实现是否符合规范）、连贯性（工件间是否一致）
- **多工具适配器架构**：`src/core/shared/tool-detection.ts` 支持 20+ AI 工具的适配，可参考其跨工具兼容设计
- **变更归档机制**：`/opsx:archive` 将已完成变更的 delta specs 自动合并入主规范，`/opsx:bulk-archive` 支持批量归档并智能处理规范冲突

### `everything-claude-code/` — Claude Code 增强系统（能力体系参考）

核心借鉴点：
- **Agent 元数据格式**：YAML frontmatter（name/description/tools/model）+ Markdown 正文，28 个 agent 按领域分层（规划/代码质量/开发支持/测试/运维）
- **Skill 分类体系**：119 个 skills 涵盖后端模式、API 设计、ADR、自主循环、多语言生态等，每个 skill 包含 When to Use / How It Works / Examples 结构
- **Rules 多层次体系**：`rules/common/`（通用）+ `rules/<language>/`（语言特定，12 种语言），规则分离清晰
- **代码评审分级标准**：CRITICAL（安全漏洞、硬编码密钥）→ HIGH（函数>50行、无错误处理）→ MEDIUM（性能问题）→ LOW（命名规范），可直接采用
- **Hook JSON 格式**：PreToolUse/PostToolUse/Stop 三类钩子，matcher 匹配工具 + hooks 数组执行命令，包含 Prettier 自动格式化、tsc 类型检查、console.log 审计等实用示例
- **质量活动完整链**：TDD-guide → code-reviewer → security-reviewer → e2e-runner，覆盖开发全流程

### `superpowers/` — 可组合技能工作流（skill 设计范本）

核心借鉴点：
- **铁律驱动的 TDD skill**：`skills/test-driven-development/SKILL.md` — "NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST"，包含常见理由反驳表（解决开发者跳过测试的心理障碍）和红旗检查清单
- **比特大小任务分解**：`skills/writing-plans/SKILL.md` — 每个任务 2-5 分钟，包含确切文件路径、完整代码示例（非伪代码）、精确命令及预期输出
- **Subagent 驱动开发**：`skills/subagent-driven-development/SKILL.md` — 每个 subagent 获得精心构造的上下文（不继承 session 历史），两阶段评审（规范符合性 → 代码质量），按任务复杂度选择模型
- **技能链组合模式**：brainstorming → writing-plans → subagent-driven-development/executing-plans → finishing-a-development-branch，技能间通过 @语法引用形成工作流
- **系统化调试四阶段**：`skills/systematic-debugging/SKILL.md` — 根因调查 → 多分量系统诊断 → 数据流向后追踪 → 验证修复，强制 "NO FIXES WITHOUT ROOT CAUSE"
- **Git worktree 并行开发**：`skills/using-git-worktrees/SKILL.md` — 隔离开发环境的最佳实践

### `SuperClaude_Framework/` — PM Agent 模式与并行执行（质量保障参考）

核心借鉴点：
- **ConfidenceChecker（实现前）**：`src/superclaude/pm_agent/confidence.py` — 五项加权评估（无重复实现 25% + 架构符合 25% + 官方文档验证 20% + OSS 参考 15% + 根因明确 15%），≥0.9 继续 / 0.7-0.89 列出选项 / <0.7 停止提问，ROI: 花 100-200 token 检查可节省 5000-50000 token 错误方向的工作
- **SelfCheckProtocol（实现后）**：`src/superclaude/pm_agent/self_check.py` — 四个强制问题（测试是否通过？需求是否满足？假设是否验证？是否有证据？）+ 七项幻觉红旗检测（无输出声称通过、无证据声称完成等），检测率 94%
- **ReflexionPattern（跨会话）**：`src/superclaude/pm_agent/reflexion.py` — 错误学习与预防的跨会话记忆模式
- **Wave→Checkpoint→Wave 并行执行**：`src/superclaude/execution/parallel.py` — 自动依赖关系图分析，独立操作并行执行，3.5x 性能提升
- **文档驱动架构**：PLANNING.md（架构+绝对规则）、KNOWLEDGE.md（见解+陷阱+解决方案）、AGENTS.md（指南），三文档配合管理项目知识

### `claude-plugins-official/` — 官方插件市场（发布分发参考）

核心借鉴点：
- **插件标准结构**：`plugin-name/.claude-plugin/plugin.json`（元数据）+ `commands/`（命令）+ `agents/`（代理）+ `skills/`（技能）+ `.mcp.json`（可选 MCP 配置），四类扩展形式统一管理
- **最小化元数据 schema**：`plugin.json` 仅需 name/description/author 三个字段，降低发布门槛
- **插件发现与安装**：`/plugin install {name}@marketplace` 语法，内部插件 vs 外部插件的不同审核路径
- **示例插件**：`plugins/example-plugin/` 提供了完整的 skill + command + agent 布局参考

### `agency-agents/` — Agent 人设模板库（角色定义参考）

核心借鉴点：
- **Persona 二元架构**：每个 agent 分为 Persona（Identity/Communication/Critical Rules）和 Operations（Mission/Deliverables/Workflow/Metrics）两个分组，结构化程度高
- **领域分类体系**：`engineering/`（23 个）、`design/`（8 个）、`product/`（5 个）等 13 个领域分类，40+ agent 覆盖完整团队角色
- **可量化成功指标**：每个 agent 定义具体的 Success Metrics（如前端 agent: LCP<2.5s, FID<100ms, CLS<0.1），而非模糊的"表现良好"
- **代码评审评论格式**：🔴blockers / 🟡suggestions / 💭nits 三级分类，配合反暗示规则（不说"有趣"，给出具体意见）
- **YAML frontmatter 标准化**：name/description/color/emoji/vibe/services 字段，支持自动化工具转换（`convert.sh` 可生成多种 AI 工具格式）

### `gstack/` — 虚拟工程团队（多角色协作参考）

核心借鉴点：
- **7 阶段工作流 Pipeline**：思考（office-hours）→ 规划评审（plan-ceo/eng/design-review）→ 构建（design-consultation）→ 代码审查（review）→ QA 测试（qa）→ 发布（ship/land-and-deploy/canary）→ 回顾（retro），28 个 skill 覆盖从产品想法到生产发布全流程
- **Skill 模板编译系统**：`SKILL.md.tmpl` + `{{PREAMBLE}}`/`{{COMMAND_REFERENCE}}` 等占位符，通过 `bun run gen:skill-docs` 从模板自动生成最终 skill 文档，避免文档与代码漂移
- **三层测试验证**：免费静态验证（`skill-validation.test.ts`）→ 付费 LLM-judge 评分（~$0.15/run）→ E2E 端到端测试（~$3.85/run），按成本分级的质量保障
- **Browser Daemon 架构**：持久化 Chromium + HTTP API，首次调用 ~3s、后续 ~100-200ms，Ref 系统（@e1/@e2）替代 CSS 选择器引用页面元素
- **Builder Ethos 决策框架**：`ETHOS.md` — "Boil the Lake"（完整性优先，AI 让完整实现的边际成本趋近于零）+ "Search Before Building"（三层知识: battle-tested → new-and-popular → first-principles）
- **allowed-tools 权限控制**：每个 skill 的 frontmatter 中声明允许使用的工具列表，实现最小权限原则

> 这些仓库仅供参考，不属于本项目的交付物。修改或扩展时应聚焦于 teamskills 自身的代码和配置。

---

## 文档层级与命名空间纪律

本仓库的核心目标之一是**建立可复用的团队级技能体系**（skill/command/rule/agent/workflow），测试项目（如当前 KV Cache Offloading 存储系统）仅作为验证载体。因此，所有 skill 和 agent 的设计必须严格区分以下层级，防止测试项目的具体领域知识污染通用技能逻辑。

### 四层文档的命名空间隔离

| 层级 | 目录 | 组织维度 | 禁止行为 |
|------|------|----------|----------|
| **产品级** | `docs/requirements/` | **Feature Domain**（用户可见的能力域） | 🚫 禁止按架构子系统组织（如 `kvcache-manager.md`、`storage.md`） |
| **架构级** | `docs/architecture/` | **Subsystem**（内部技术子系统） | 🚫 禁止写入需求场景或验收标准 |
| **特性级** | `openspec/changes/<proposal>/` | **Proposal**（规范驱动的变更单元） | — |
| **代码级** | 代码仓库自身 | **Module/File** | — |

### 产品级 vs 架构级的边界（强制）

**产品级（`docs/requirements/`）关注「用户要什么」**：
- 按 **Feature Domain** 拆分，例如 `cache-offloading.md`、`data-lifecycle.md`、`engine-integration.md`、`cluster-management.md`、`observability.md`
- 内容包含：Actors、Feature 价值论证、Scenario（正常+故障+运维）、量化验收标准、非功能需求
- **绝不包含**内部模块名、类名、接口原型、数据结构设计

**架构级（`docs/architecture/`）关注「系统怎么做」**：
- 按 **Subsystem** 拆分，例如 `kvcache-manager/`、`metadata/`、`storage/`、`connector/`
- 内容包含：子系统职责边界、高层接口抽象、关键算法/数据结构设计 rationale、部署拓扑
- **绝不包含**用户故事、验收标准、业务场景描述

### Skill / Agent / Command 的通用约束

所有产品级 skill（如 `product/define`、`product/plan`、`product/architect`）在设计和执行时必须遵守：

1. **目录约束**：产品级 skill 只能读写 `docs/requirements/`、`docs/iteration-plan.md`、`docs/test-strategy.md`；禁止直接操作 `docs/architecture/` 下的子系统文档。
2. **命名约束**：产出文件名必须体现用户能力域，禁止与子系统同名。若用户提到子系统名，skill 必须主动将其映射到对应的能力域。
3. **内容约束**：产品级文档中禁止出现子系统内部模块名（如 `BlockAllocator`、`IndexService`）。若架构文档已产出，产品级文档可通过「追溯关系」链接到架构文档，但不重复描述实现细节。
4. **防混淆检查清单**：每个产品级 skill 在产出文档前必须自检：
   - [ ] 文件名是否属于 Feature Domain 而非 Subsystem？
   - [ ] 文档中是否出现了内部模块/类/函数名？
   - [ ] Scenario 描述是否从用户/外部系统视角出发？
   - [ ] 是否引用了架构文档作为约束，而非复制架构内容？

### 示例：正确 vs 错误

| 场景 | 错误（混淆） | 正确（分离） |
|------|-------------|-------------|
| 需求文档文件名 | `storage.md` | `data-lifecycle.md` |
| Feature 描述 | "Storage 子系统负责 Block 分配" | "用户写入的 KV Cache 数据支持按热度自动在 HBM/DRAM/SSD 间迁移" |
| Actor 定义 | "BlockAllocator 组件" | "推理引擎客户端" |
| 验收标准 | "`block_alloc()` 返回 0 表示成功" | "单节点在 HBM 满时，写入请求在 10ms 内完成降级到 DRAM" |

---

## 变更记录

### 2026-04-08: product/architect Skill 优化

**问题反馈**（主人测试 `/ky:arch` 后）：
1. 架构文档内容过于简单，仅针对单次对话
2. 过早提问是否进入下一步
3. 思考深度不够，生成太快
4. 子系统文档过于深入代码细节，缺少方案设计 rationale
5. 子系统文档缺少动态视图和推导过程
6. reference 目录没有强制生成

**优化措施**：
1. **多 agent 深度思考模式**：引入 Researcher/Analyzer/Evaluator 子 agent 并行研究
2. **强制多轮迭代**：标杆研究 → 方案发散 → 评估收敛 → 迭代完善
3. **置信度检查点**：低置信度禁止推进，强制标注置信度
4. **文档结构**：子系统架构文档保留子目录组织 `docs/architecture/<subsystem>/design.md`，非子系统文档统一放入 `decisions/` 或 `reference/`
5. **标杆研究强制**：未完成研究禁止进入方案设计
6. **内容规范**：聚焦方案设计 + rationale，禁止代码细节
7. **标杆分析模板**：`.claude/templates/ref-architecture.md` 强制深度分析结构
