---
name: devforge-feature-design
description: 特性级架构设计 skill，产出 design.md（HOW 实现 specs）。用于 OpenSpec workflow 的 design artifact 生成。派遣 architect agent 生成、architect-reviewer 评审（最多 3 轮）。强制图示触发条件。当 OpenSpec 引擎触发 design artifact 生成时自动调用。
allowed-tools: [Read, Write, Edit, Bash, Grep, Glob, Agent]
---

# devforge-feature-design — 特性级架构设计

## 概述

特性级架构设计是 OpenSpec workflow 中 specs + research 之后的实现方案阶段。本 skill 产出 design.md，说明如何（HOW）实现 specs 中定义的需求。

**与产品级 design 的区别**：
- 产品级（`/df:product-design`）：子系统分解 + ADR + 系统架构总纲，产出 `docs/architecture/*.md`
- 特性级（本 skill）：在既有架构内展开，不新建子系统，产出当前工作目录的 `design.md`

**核心原则**：
1. **在既有架构内展开**：不新建子系统，不改变系统级架构决策
2. **强制图示**：结构图 / 时序图 / 状态机图 / 数据流图，按触发条件强制出图
3. **Decision 追溯标杆**：每个 Decision 的候选方案标注 research.md 中的标杆来源
4. **skill 内化评审**：最多 3 轮 architect agent → architect-reviewer 循环

---

## 工作目录约定

skill 在**当前工作目录**查找输入文件、输出产出文件：
- **输入**：`proposal.md`（必需）、`research.md`（必需）、`specs/*.md`（如已存在）
- **输出**：`design.md`
- **产品级文档**：通过项目根目录的 CLAUDE.md#产品级文档索引定位

**调用方式**：
- **OpenSpec workflow 调用**：workflow 先 `cd openspec/changes/<name>/`，然后调用 skill
- **手动调用**：用户先 `cd` 到包含 `proposal.md` 的目录，然后调用 `/df:design`

## 启动检测

检查当前工作目录的 `design.md`：
- **不存在** → 进入「初次生成」模式
- **已存在** → 反问主人「修订 / 补全」，按指定模式运行

如果当前工作目录无 `proposal.md` 或 `research.md`，立即报错并提示主人 `cd` 到正确目录或先完成前置 artifact。

---

## 初次生成模式

### [1] 上下文准备

读取以下输入：
1. **proposal.md**：本特性的动机和范围
2. **research.md**：约束清单 + 标杆方案空间 + 设计空间地图
3. **specs/*.md**（如已存在）：行为规范的详细定义
4. **产品级架构文档**（按需）：`docs/architecture/` 下相关子系统设计、ADR
5. **design.md template**：`openspec/schemas/spec-driven-enhanced/templates/design.md`

### [2] Decision 生成

派遣 1 个 architect agent，任务：
- 读 research.md 的设计空间地图，识别关键决策点
- 对每个决策点，列出候选方案（标注 research.md 中的标杆来源）
- 用表格比较 trade-off（复杂度 / 性能影响 / 可维护性 / 与本项目约束的匹配度）
- 明确写出"选择 X 因为 Y"，不选其他候选的具体理由
- 产出：Decisions 章节（写入 `design-draft.md`）

### [3] 强制图示检查

主会话读 design-draft.md，检查是否满足强制出图条件：
- 模块结构、组件关系（≥3 个组件）→ 结构图（Mermaid graph 或 ASCII）
- 跨进程/跨节点交互 → 时序图（Mermaid sequenceDiagram）
- 有生命周期的对象（租约、连接、会话）→ 状态机图（Mermaid stateDiagram）
- 数据缓存、读写路径分离 → 数据流图（Mermaid flowchart）

未满足 → 派遣 architect agent 补充图示。

### [4] 其他章节生成

派遣 1 个 architect agent，任务：
- 补全 Context / Architecture Traceability / Goals / Non-Goals / Interface Changes / Risks / Migration Plan / Open Questions
- 产出：完整 design.md（写入 `design-draft.md`）

### [5] 评审循环（最多 3 轮）

派遣 1 个 architect-reviewer agent，任务：
- 读 design-draft.md 全文
- 检查：方案可行性、方案竞争力、方案合理性、架构一致性、设计内部一致性、可维护性、故障处理、决策备选方案、并发模型、状态机表达、性能评估
- 产出：问题清单（CRITICAL / HIGH / MEDIUM / LOW）

计算缺陷密度（问题分数之和 / Decision 数）：
- 无 CRITICAL + 缺陷密度 ≤ 2.0 → 通过，进入 [6]
- 否则 → 派遣 1 个 architect agent 修正，回到本步骤重新评审
- 3 轮后仍未通过 → 标注残留问题，进入 [6]

### [6] 落地输出

将 `design-draft.md` 重命名为 `design.md`。在终端汇报：
- Decision 数
- 图示数（结构图 / 时序图 / 状态机图 / 数据流图）
- 置信度（评审通过 / 带债通过）

---

## 修订模式

反问主人「想修订哪一块」，提供选项：
1. 修订 Decisions（重新比较候选方案）
2. 修订图示（补充或调整图）
3. 修订其他章节（Context / Risks / Migration Plan 等）

只跑对应范围的生成阶段，merge 结果回 design.md，不动其他章节。评审循环只检查变更范围。

---

## 补全模式

用结构性元素清单扫描 design.md，识别缺失项：
- Decision 缺失候选方案或 trade-off 分析
- 缺失强制图示
- 缺失 Architecture Traceability

直接在缺失位置生成补全内容，评审循环。

---

## Agent 派遣 Prompt 模板

### architect agent（Decision 生成）

```
当前是特性级 design 阶段，生成 design.md。

**任务模式**：特性级架构决策主角（既有架构内展开 Decisions）
**任务**：生成 Decisions 章节。

**输入**：
- proposal.md：当前工作目录
- research.md：当前工作目录（读设计空间地图，识别关键决策点）
- specs/*.md：当前工作目录（如已存在）
- 产品级架构文档：docs/architecture/<相关子系统>/design.md
- design.md template_path：openspec/schemas/spec-driven-enhanced/templates/design.md

**output_path**：`design-draft.md`（当前工作目录）

**输出**：
每个 Decision：
- 候选方案（标注 research.md 中的标杆来源）
- 对比表格（复杂度 / 性能影响 / 可维护性 / 与本项目约束的匹配度）
- 结论（选择 X 因为 Y，不选 A 因为 ...，不选 B 因为 ...）
- 取舍代价 + 缓解措施
- 演进性（或"本决策无演进性需求"）

写入 `design-draft.md`。

**质量约束**：
- 有选择空间的决策必须有 ≥2 个候选方案
- 量化优先（性能用具体数值，空间开销用具体公式）
- 涉及并发时声明并发模型（锁类型、粒度、获取顺序）
- 涉及多状态组件时提供状态转换表
```

### architect-reviewer agent

```
当前是特性级 design 阶段，评审 design-draft.md。

**被评审对象**：<路径>
**被评审 template_path**：openspec/schemas/spec-driven-enhanced/templates/design.md
**review_output_path**：`design-review.md`（当前工作目录，多轮追加同一文件）
**report_template_path**：`.claude/templates/review-report.md`（如存在）
**复杂度档位**：复杂（≥7 个质疑点，覆盖 11 项维度）

**评审维度**（11 项）：
- 方案可行性：技术方案是否可行（能否满足 specs 的每条 Requirement）
- 方案竞争力：方案是否具备竞争力（对比业界标准或已知方案）
- 方案合理性：技术决策是否合理（trade-off 权衡是否得当）
- 架构一致性：是否违反架构设计原则（对照 docs/architecture/ 检查）
- 设计内部一致性：设计内部是否一致（Decision 之间无矛盾）
- 可维护性：设计复杂度是否合理，是否过度工程化
- 故障处理：故障场景是否充分考虑（关键路径的失败模式、降级策略、恢复机制）
- 决策备选方案：有选择空间的决策是否有备选方案和 trade-off 分析
- 并发模型：涉及并发交互的决策是否声明了并发模型
- 状态机表达：涉及多状态组件是否有状态转换表
- 性能评估：性能影响评估是否充分（关键路径延迟和吞吐量是否有量化分析）

**输出**：
问题清单（CRITICAL / HIGH / MEDIUM / LOW），计算缺陷密度。

**问题分级标准**：
- CRITICAL：方案不可行、违反架构原则、关键路径无故障处理
- HIGH：方案竞争力不足、决策不合理、缺少备选方案
- MEDIUM：可维护性问题、性能评估不充分
- LOW：文档格式、命名不一致

**问题分值**：CRITICAL=10分, HIGH=3分, MEDIUM=1分, LOW=0.1分  
**缺陷密度** = 问题分数之和 / Decision 数
```

---

## 禁忌项

- 禁止在 design.md 中新建子系统（特性级在既有架构内展开）
- 禁止跳过强制图示检查
- 禁止 Decision 只列一个方案没有备选（已被架构约束的除外）
- 禁止跳过评审循环直接输出

---

## 与其他 skill 的协作

- **上游**：proposal.md + research.md + specs/*.md（由 OpenSpec 引擎或主人创建）
- **下游**：tasks.md（由 OpenSpec 引擎读取 design.md 生成任务清单）
- **并行**：无（design 是 tasks 的前置依赖）
