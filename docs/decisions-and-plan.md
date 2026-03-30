# 决策与实施计划

## 十三、关键设计决策

### 13.1 为什么安装 OpenSpec 而非全部自建？

OpenSpec 提供了成熟的特性级 workflow 引擎：

| 能力 | 自建成本 | OpenSpec 提供 |
|------|---------|-------------|
| Artifact 依赖图 + 拓扑排序 | 高（DAG + Kahn 算法 + 状态检测） | ✅ `artifact-graph/graph.ts` |
| Delta spec 解析 + 合并 | 高（Markdown 解析 + 四种操作 + 冲突处理） | ✅ `specs-apply.ts` + `change-parser.ts` |
| Schema 自定义 + 验证 | 中（Zod schema + resolver） | ✅ `schema fork/init/validate` |
| 模板系统 + 指令注入 | 中（context/rules/template 注入） | ✅ `instruction-loader.ts` |
| 命令系统 | 中（propose/continue/apply/verify/archive） | ✅ 6+ 个命令 |
| 三维验证 | 中（Completeness/Correctness/Coherence） | ✅ `/opsx:verify` |

自建所有这些能力违反"不造轮子"原则。OpenSpec 的 schema 自定义能力（fork + config.yaml）足以表达 teamskills 的特性级需求。

### 13.2 为什么不安装 superpowers？

superpowers 提供优秀的理念（TDD 铁律、bite-sized 任务、subagent 驱动开发、系统化调试），但：

1. **工件格式不兼容**：superpowers 使用自有的 skill 格式和 workflow，与 OpenSpec 的 schema/artifact/delta 体系不兼容
2. **无法直接配合**：superpowers 的 TDD 和计划编写不感知 OpenSpec 的 dependency graph、config.yaml 注入、verify 验证
3. **理念 > 安装**：借鉴其核心理念（RED-GREEN-REFACTOR 铁律、借口反驳表、2-5 分钟任务粒度、subagent 两阶段评审、四阶段调试法）自建 skills，可以深度集成 C 语言和分布式存储场景

### 13.3 Skill / Agent / Command / Schema 的分工

| 概念 | 角色 | 所属层级 |
|------|------|---------|
| **Schema** | 工作流定义（artifact + 依赖 + 模板 + 指令），由 OpenSpec 引擎驱动 | 仅特性级 |
| **Skill** | 工作流载体（定义做什么、如何做、allowed-tools） | 产品级、代码级、测试验证级 |
| **Agent** | Skill 内部的执行者（定义角色人设、专业能力） | 跨层级复用 |
| **Command** | 用户主动触发的入口点（`/opsx:*` 触发 Schema，`/ky:*` 触发 Skill） | 全层级 |
| **Hook** | 自动触发的守护逻辑（编辑后/提交前/合并后） | 主要在代码级和同步层 |
| **Rule** | 约束规范（编码/测试/安全/协作） | 全层级 |

---

> **实施优先级** 已拆分至独立文档：[tasks.md](tasks.md)

---

## 十四、验证方式

| 验证项 | 命令/方法 | 预期结果 |
|--------|---------|---------|
| spec-driven-enhanced schema 合法性 | `openspec schema validate spec-driven-enhanced` | 通过验证 |
| 特性级完整流程 | `/opsx:propose test-change` → `/opsx:continue`（4次）→ `/opsx:apply` → `/opsx:verify` → `/opsx:archive` | 所有 artifact 正常生成，verify 通过 |
| 产品级探索 skill | `/ky:explore` 执行一轮架构探索 | 启发式思考引导有效，输出 ADR 和架构文档 |
| 产品级评审 skill | `/ky:product-review` 评审产品级文档 | 跨文档一致性检查和红旗检测正常工作 |
| 产品级一致性检查 | `/ky:verify` 执行产品级 vs 特性级一致性检查 | 输出不一致清单和方向建议 |
| 代码级 TDD | `/ky:tdd` 执行一个完整 RED-GREEN-REFACTOR 循环 | 测试先红后绿 |
| 反馈闭环 A | 手动触发闭环 A 外层脚本 | 编译+测试反馈循环正常收敛 |

---

## 十五、关键参考文件

| 用途 | 文件路径 |
|------|---------|
| OpenSpec spec-driven schema（fork 基础） | `OpenSpec/schemas/spec-driven/schema.yaml` |
| OpenSpec 依赖图引擎 | `OpenSpec/src/core/artifact-graph/graph.ts` |
| OpenSpec 指令注入 | `OpenSpec/src/core/artifact-graph/instruction-loader.ts` |
| OpenSpec Schema 解析 | `OpenSpec/src/core/artifact-graph/resolver.ts` |
| OpenSpec 配置读取 | `OpenSpec/src/core/project-config.ts` |
| OpenSpec Delta 合并 | `OpenSpec/src/core/specs-apply.ts` |
| OpenSpec 自定义文档 | `OpenSpec/docs/customization.md` |
| TDD 铁律 | `superpowers/skills/test-driven-development/SKILL.md` |
| 任务分解粒度 | `superpowers/skills/writing-plans/SKILL.md` |
| Subagent 调度模式 | `superpowers/skills/subagent-driven-development/SKILL.md` |
| 系统化调试 | `superpowers/skills/systematic-debugging/SKILL.md` |
| Git worktree 隔离 | `superpowers/skills/using-git-worktrees/SKILL.md` |
| Agent frontmatter 格式 | `everything-claude-code/agents/code-reviewer.md` |
| 代码评审分级标准 | `everything-claude-code/agents/code-reviewer.md` |
| Hook 配置格式 | `everything-claude-code/hooks/hooks.json` |
| C++ 规则参考（适配 C） | `everything-claude-code/rules/cpp/` |
| 置信度检查 | `SuperClaude_Framework/src/superclaude/pm_agent/confidence.py` |
| 自检协议 | `SuperClaude_Framework/src/superclaude/pm_agent/self_check.py` |
| 并行执行引擎 | `SuperClaude_Framework/src/superclaude/execution/parallel.py` |
| Persona 角色模板 | `agency-agents/engineering/` |
