# teamskills 内容体系设计方案

## Context

teamskills 仓库当前仅有 CLAUDE.md 和 7 个参考仓库。需要设计完整的 skills/agents/commands/hooks/rules 体系，解决团队面临的 6 个问题（P1-P6），构建产品级 → 特性级 → 代码级 → 测试验证级四层 skill 体系。

**核心决策**：安装 OpenSpec 作为基础，利用其特性级 workflow 引擎（命令系统、依赖图、Schema 自定义、模板、Delta spec、archive），不重建这些基础设施。特性级的工作流表达为 OpenSpec Schema（spec-driven-enhanced），代码级使用 Claude Code 原生扩展（skills/agents/commands/hooks/rules）自建，测试验证级在独立测试目录中走专用 workflow（待定义，不复用功能代码的 spec-driven-enhanced）。产品级与 OpenSpec 彻底脱离，使用 6 个启发式 skill（按思考模式拆分：explore/define/plan/review/test-design/verify）辅助产品级设计——因为产品级设计是持续数月的创意迭代过程，重要的是**输出质量**而非**流程控制**。不安装 superpowers，但借鉴其 TDD、Subagent、计划编写等理念。

### 设计约束

- **用现成工具，不造轮子**：所有 skill/hook/command/agent 使用 Claude Code 内置能力、Linux 系统工具（gcc/make/git/grep/sed/awk 等）以及外部成熟工具（clang-tidy、valgrind、clang-format、perf 等），不受限制。核心原则是**不自研工具**——避免为了配合 skill 体系而开发需要长期维护的自定义工具链。能用现成的就用现成的
- **面向 C 语言 + Linux + 分布式存储**：团队主要使用 C 语言开发分布式存储系统，运行在 Linux 环境。分布式存储对**数据一致性**（强一致/最终一致、副本一致性、故障后数据完整性）和**性能**（低延迟、高吞吐、高并发）要求极高。对代码质量要求同样严苛：内存安全（无泄漏、无越界）、并发正确性（锁序、无锁结构、竞态检测）、错误处理完备性（每个返回值都必须检查）、编码规范一致性。所有 skill 和 rule 的设计以 C 语言、Linux 系统编程和分布式存储场景为第一优先级

---

## 文档索引

| 文档 | 内容 |
|------|------|
| **[架构与基础](architecture.md)** | 三层架构分层 + OpenSpec 提供的基础能力 |
| **[产品级与特性级设计](product-feature-schema.md)** | 产品级启发式 Skills + 特性级 Schema + 目录结构 |
| **[扩展清单](extensions-catalog.md)** | Skills(14) / Agents(10) / Commands(13) / Hooks(3) / Rules(4) 完整清单 + 格式规范 |
| **[工作流串联](workflow.md)** | 四层工作流总览 + 各层级详细流程 |
| **[团队协作与变更同步](team-and-sync.md)** | Monorepo 模式 + 并行开发 + 使用方式 + 变更回溯机制 |
| **[反馈闭环](feedback-loop.md)** | GAN 式对抗反馈闭环（编译+测试/代码分析）+ 角色约束 + 数据格式 |
| **[决策与实施计划](decisions-and-plan.md)** | 关键设计决策 + 问题覆盖矩阵 + 实施优先级 + 验证方式 + 参考文件 |
