# 架构与基础

## 一、架构分层

采用三层架构：产品级使用启发式 Skills（与 OpenSpec 脱离），特性级基于 OpenSpec 引擎，代码级和测试验证级基于 Claude Code 原生扩展。

```
┌─────────────────────────────────────────────────────────────────┐
│ 第一层：产品级启发式 Skills + 特性级 OpenSpec Schema                  │
│                                                                 │
│   产品级：6 个启发式 skill（explore/define/plan/review/              │
│           test-design/verify）                                     │
│           docs/ 目录，templates/product/ 参考模板                   │
│           与 OpenSpec 彻底脱离，按思考模式辅助设计                     │
│                                                                 │
│   特性级：spec-driven-enhanced schema（5 个 artifact，fork spec-driven）│
│           openspec/config.yaml（注入 C 语言 + 分布式存储上下文）       │
│           复用 OpenSpec 引擎：依赖图、拓扑排序、命令系统、              │
│           Delta spec、模板、archive、verify                        │
├─────────────────────────────────────────────────────────────────┤
│ 第二层：Claude Code 原生扩展（代码级 + 评审 + 反馈闭环）                │
│                                                                 │
│   8 个 skills · 10 个 agents · 13 个 commands（/ky: 前缀）         │
│   3 个 hooks · 4 个 rules                                        │
├─────────────────────────────────────────────────────────────────┤
│ 第三层：四层工作流串联                                               │
│                                                                 │
│   产品级（启发式 skills + /ky:explore、/ky:define、/ky:plan、        │
│          /ky:product-review、/ky:test-design、/ky:verify）         │
│   特性级（spec-driven-enhanced schema + /opsx:* 命令）              │
│   代码级（teamskills /ky:* skills）                                │
│   测试验证级（独立测试仓专用 workflow（待定义）+ 脚本执行）             │
└─────────────────────────────────────────────────────────────────┘
```

---

## 二、OpenSpec 提供的基础（不重建）

OpenSpec 已经提供了完整的特性级 workflow 引擎，teamskills 直接复用以下能力：

| 能力 | 说明 | 关键实现 |
|------|------|---------|
| **Workflow 命令** | `/opsx:propose`、`/opsx:continue`、`/opsx:apply`、`/opsx:archive`、`/opsx:sync`、`/opsx:verify`、`/opsx:bulk-archive` | `src/commands/workflow/` |
| **Artifact 依赖图** | DAG 有向无环图 + Kahn 拓扑排序，自动推导 artifact 就绪状态 | `src/core/artifact-graph/graph.ts` |
| **Schema 自定义** | `openspec schema fork/init/validate`，项目本地 schema 优先于内置 | `src/core/artifact-graph/resolver.ts` |
| **配置系统** | `openspec/config.yaml`：`context` 注入到所有 artifact，`rules` 按 artifact 类型注入 | `src/core/project-config.ts` |
| **模板系统** | 每个 artifact 对应 Markdown 模板，定义文档结构框架 | `schemas/*/templates/` |
| **Delta spec** | ADDED/MODIFIED/REMOVED/RENAMED 四种操作，支持增量变更而非全量重写 | `src/core/parsers/change-parser.ts` |
| **Archive 机制** | 自动合并 delta spec 到主 spec，支持批量归档和冲突检测 | `src/core/specs-apply.ts` |
| **指令注入** | 生成 artifact 时自动注入 `<project_context>` + `<rules>` + `<dependencies>` + `<template>` | `src/core/artifact-graph/instruction-loader.ts` |
| **三维验证** | Completeness（完整性）+ Correctness（正确性）+ Coherence（一致性） | `/opsx:verify` |

**Schema 文件查找优先级**（从高到低）：
1. 项目本地：`<projectRoot>/openspec/schemas/<name>/schema.yaml`
2. 用户全局：`~/.local/share/openspec/schemas/<name>/schema.yaml`
3. 包内置：`<package>/schemas/<name>/schema.yaml`

teamskills 的自定义 schema 放在 `openspec/schemas/` 目录下，自动被 OpenSpec 识别。
