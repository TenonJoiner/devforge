# 参考仓库

以下仓库作为设计和实现的参考素材，已克隆至本项目目录下：

## `OpenSpec/` — 规范驱动开发框架（workflow 骨架）

核心借鉴点：
- **规范驱动 workflow**：proposal → specs → design → tasks → implement → archive 完整生命周期
- **Delta 规范格式**：变更只声明 ADDED/MODIFIED/REMOVED 的需求差异，避免全量重写规范
- **Artifact 依赖图**：通过 YAML schema 定义工件类型及依赖关系（proposal → specs/design → tasks），支持自定义 workflow
- **Verify 三维评估**：完整性（所有需求是否覆盖）、正确性（实现是否符合规范）、连贯性（工件间是否一致）
- **多工具适配器架构**：`src/core/shared/tool-detection.ts` 支持 20+ AI 工具的适配，可参考其跨工具兼容设计
- **变更归档机制**：`/opsx:archive` 将已完成变更的 delta specs 自动合并入主规范，`/opsx:bulk-archive` 支持批量归档并智能处理规范冲突

## `everything-claude-code/` — Claude Code 增强系统（能力体系参考）

核心借鉴点：
- **Agent 元数据格式**：YAML frontmatter（name/description/tools/model）+ Markdown 正文，28 个 agent 按领域分层（规划/代码质量/开发支持/测试/运维）
- **Skill 分类体系**：119 个 skills 涵盖后端模式、API 设计、ADR、自主循环、多语言生态等，每个 skill 包含 When to Use / How It Works / Examples 结构
- **Rules 多层次体系**：`rules/common/`（通用）+ `rules/<language>/`（语言特定，12 种语言），规则分离清晰
- **代码评审分级标准**：CRITICAL（安全漏洞、硬编码密钥）→ HIGH（函数>50行、无错误处理）→ MEDIUM（性能问题）→ LOW（命名规范），可直接采用
- **Hook JSON 格式**：PreToolUse/PostToolUse/Stop 三类钩子，matcher 匹配工具 + hooks 数组执行命令，包含 Prettier 自动格式化、tsc 类型检查、console.log 审计等实用示例
- **质量活动完整链**：TDD-guide → code-reviewer → security-reviewer → e2e-runner，覆盖开发全流程

## `superpowers/` — 可组合技能工作流（skill 设计范本）

核心借鉴点：
- **铁律驱动的 TDD skill**：`skills/test-driven-development/SKILL.md` — "NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST"，包含常见理由反驳表（解决开发者跳过测试的心理障碍）和红旗检查清单
- **比特大小任务分解**：`skills/writing-plans/SKILL.md` — 每个任务 2-5 分钟，包含确切文件路径、完整代码示例（非伪代码）、精确命令及预期输出
- **Subagent 驱动开发**：`skills/subagent-driven-development/SKILL.md` — 每个 subagent 获得精心构造的上下文（不继承 session 历史），两阶段评审（规范符合性 → 代码质量），按任务复杂度选择模型
- **技能链组合模式**：brainstorming → writing-plans → subagent-driven-development/executing-plans → finishing-a-development-branch，技能间通过 @语法引用形成工作流
- **系统化调试四阶段**：`skills/systematic-debugging/SKILL.md` — 根因调查 → 多分量系统诊断 → 数据流向后追踪 → 验证修复，强制 "NO FIXES WITHOUT ROOT CAUSE"
- **Git worktree 并行开发**：`skills/using-git-worktrees/SKILL.md` — 隔离开发环境的最佳实践

## `SuperClaude_Framework/` — PM Agent 模式与并行执行（质量保障参考）

核心借鉴点：
- **ConfidenceChecker（实现前）**：`src/superclaude/pm_agent/confidence.py` — 五项加权评估（无重复实现 25% + 架构符合 25% + 官方文档验证 20% + OSS 参考 15% + 根因明确 15%），≥0.9 继续 / 0.7-0.89 列出选项 / <0.7 停止提问，ROI: 花 100-200 token 检查可节省 5000-50000 token 错误方向的工作
- **SelfCheckProtocol（实现后）**：`src/superclaude/pm_agent/self_check.py` — 四个强制问题（测试是否通过？需求是否满足？假设是否验证？是否有证据？）+ 七项幻觉红旗检测（无输出声称通过、无证据声称完成等），检测率 94%
- **ReflexionPattern（跨会话）**：`src/superclaude/pm_agent/reflexion.py` — 错误学习与预防的跨会话记忆模式
- **Wave→Checkpoint→Wave 并行执行**：`src/superclaude/execution/parallel.py` — 自动依赖关系图分析，独立操作并行执行，3.5x 性能提升
- **文档驱动架构**：PLANNING.md（架构+绝对规则）、KNOWLEDGE.md（见解+陷阱+解决方案）、AGENTS.md（指南），三文档配合管理项目知识

## `claude-plugins-official/` — 官方插件市场（发布分发参考）

核心借鉴点：
- **插件标准结构**：`plugin-name/.claude-plugin/plugin.json`（元数据）+ `commands/`（命令）+ `agents/`（代理）+ `skills/`（技能）+ `.mcp.json`（可选 MCP 配置），四类扩展形式统一管理
- **最小化元数据 schema**：`plugin.json` 仅需 name/description/author 三个字段，降低发布门槛
- **插件发现与安装**：`/plugin install {name}@marketplace` 语法，内部插件 vs 外部插件的不同审核路径
- **示例插件**：`plugins/example-plugin/` 提供了完整的 skill + command + agent 布局参考

## `agency-agents/` — Agent 人设模板库（角色定义参考）

核心借鉴点：
- **Persona 二元架构**：每个 agent 分为 Persona（Identity/Communication/Critical Rules）和 Operations（Mission/Deliverables/Workflow/Metrics）两个分组，结构化程度高
- **领域分类体系**：`engineering/`（23 个）、`design/`（8 个）、`product/`（5 个）等 13 个领域分类，40+ agent 覆盖完整团队角色
- **可量化成功指标**：每个 agent 定义具体的 Success Metrics（如前端 agent: LCP<2.5s, FID<100ms, CLS<0.1），而非模糊的"表现良好"
- **代码评审评论格式**：🔴blockers / 🟡suggestions / 💭nits 三级分类，配合反暗示规则（不说"有趣"，给出具体意见）
- **YAML frontmatter 标准化**：name/description/color/emoji/vibe/services 字段，支持自动化工具转换（`convert.sh` 可生成多种 AI 工具格式）

## `gstack/` — 虚拟工程团队（多角色协作参考）

核心借鉴点：
- **7 阶段工作流 Pipeline**：思考（office-hours）→ 规划评审（plan-ceo/eng/design-review）→ 构建（design-consultation）→ 代码审查（review）→ QA 测试（qa）→ 发布（ship/land-and-deploy/canary）→ 回顾（retro），28 个 skill 覆盖从产品想法到生产发布全流程
- **Skill 模板编译系统**：`SKILL.md.tmpl` + `{{PREAMBLE}}`/`{{COMMAND_REFERENCE}}` 等占位符，通过 `bun run gen:skill-docs` 从模板自动生成最终 skill 文档，避免文档与代码漂移
- **三层测试验证**：免费静态验证（`skill-validation.test.ts`）→ 付费 LLM-judge 评分（~$0.15/run）→ E2E 端到端测试（~$3.85/run），按成本分级的质量保障
- **Browser Daemon 架构**：持久化 Chromium + HTTP API，首次调用 ~3s、后续 ~100-200ms，Ref 系统（@e1/@e2）替代 CSS 选择器引用页面元素
- **Builder Ethos 决策框架**：`ETHOS.md` — "Boil the Lake"（完整性优先，AI 让完整实现的边际成本趋近于零）+ "Search Before Building"（三层知识: battle-tested → new-and-popular → first-principles）
- **allowed-tools 权限控制**：每个 skill 的 frontmatter 中声明允许使用的工具列表，实现最小权限原则

> 这些仓库仅供参考，不属于本项目的交付物。修改或扩展时应聚焦于 teamskills 自身的代码和配置。
