---
name: devforge-feature-define
description: 特性级需求定义 skill，产出 specs/*.md（Delta 格式 Requirement + Scenario + Non-Functional Requirements）。派遣 product agent 生成、product-reviewer + architect-reviewer 双视角评审（最多 3 轮）。
allowed-tools: [Read, Write, Edit, Bash, Grep, Glob, Agent]
---

# devforge-feature-define — 特性级需求定义

## 概述

特性级需求定义是 proposal + research 之后的规范化阶段。本 skill 产出 specs/*.md，使用 Delta 格式（ADDED / MODIFIED / REMOVED / RENAMED Requirements）。

> **内容规范强牵引**：spec 交付件的所有内容结构、章节要求、自检清单**以 `openspec-schema/schemas/spec-driven-enhanced/templates/spec.md` 为唯一准绳**。本 skill 只负责定义**努力程度、写作风格、质量门槛和流程控制**，不再重复模板中已有的内容要求。

**与产品级 define 的区别**：
- 产品级（`/df:product-define`）：Actor 识别 + Feature-Scenario 分层展开，产出 `docs/requirements/*.md`
- 特性级（本 skill）：承接已识别 Actor，在既有 Feature 框架内定义 Requirement + Scenario，产出 change-dir 的 `specs/*.md`

**核心原则**：
1. **承接 Actor**：不重新识别 Actor，从产品级需求文档中获取已识别的 Actor 清单
2. **Delta 语义**：严格遵守 ADDED / MODIFIED / REMOVED / RENAMED 格式，archive 引擎依赖这套语义
3. **Requirement 可测试**：每条 Requirement 读完能明确判断"通过"还是"不通过"
4. **Scenario 完整**：每条 Requirement 至少一个正常路径 + 一个异常路径 Scenario
5. **skill 内化评审**：最多 3 轮 product agent → product-reviewer + architect-reviewer 循环

---

## 工作目录约定

skill 在 **change-dir**（默认当前工作目录）查找输入文件、输出产出文件：
- **change-dir**：由 `--change-dir <path>` 参数指定，无参数时默认当前工作目录
- **输入**：`proposal.md`（必需）、`research.md`（如已存在）、`design.md`（如已存在）
- **输出**：`specs/` 目录及其下的 spec 文件
- **内容模板**：`openspec-schema/schemas/spec-driven-enhanced/templates/spec.md`（plugin 内置模板，章节结构与内容要求的唯一准绳）
- **产品级文档**：通过项目根目录的 CLAUDE.md#产品级文档索引定位

**调用方式**：
- **手动调用**：用户先 `cd` 到包含 `proposal.md` 的目录，然后调用 `/df:define`；或显式传入 `--change-dir <path>`
- **workflow 调用**：由主会话传入 `--change-dir <path>`，以指定目录为工作上下文

## 启动检测

**change-dir**：由 `--change-dir <path>` 参数指定，无参数时默认当前工作目录。

检查 change-dir 的 `specs/` 目录：
- **不存在或为空** → 进入「初次生成」模式
- **已存在 spec 文件** → 反问主人「修订 / 补全」，按指定模式运行

如果 change-dir 无 `proposal.md`，立即报错并提示主人检查 `--change-dir` 参数或 `cd` 到正确目录。

---

## 初次生成模式

### [1] 上下文准备

读取以下输入（路径均相对于 change-dir）：
1. **proposal.md**：本特性的 Capabilities 清单（每个 Capability 对应一个 spec 文件）
2. **research.md**：约束清单 + 设计空间地图（作为 Requirement 边界依据）
3. **产品级需求文档**（按需）：`docs/requirements/` 下相关 Feature 规格，获取 Actor 清单和验收标准
4. **design.md**（如已存在）：了解实现方案，避免 spec 与 design 矛盾
5. **输出格式**：见下方「Agent 派遣 Prompt 模板」中的输出结构定义

### [2] Capability 拆解

对每个 Capability（来自 proposal.md），派遣 1 个 product agent（并发上限 5），任务：
- 读 proposal.md 的该 Capability 描述
- 读 research.md 的约束清单（作为 Requirement 边界）
- 读产品级需求文档（获取 Actor 清单和验收标准）
- 产出：该 Capability 的 Requirement 清单（每条 Requirement 至少一个 Scenario）
- 写入：`specs/<capability>/spec-draft.md`（使用 Delta 格式）

所有 agent 完成后，主会话检查文件存在性。

### [3] 双视角评审（最多 3 轮）

并行派遣 2 个 reviewer agent：
- **product-reviewer**：检查 Requirement 合理性、必要性、完整性、清晰性、可验收性、异常路径质量、安全覆盖
- **architect-reviewer**：检查 Requirement 与 research.md 约束的一致性、与产品级需求的追溯链

每个 reviewer 产出问题清单（CRITICAL / HIGH / MEDIUM / LOW）。

计算缺陷密度（问题分数之和 / spec 文件数）：
- 无 CRITICAL + 缺陷密度 ≤ 2.0 → 通过，进入 [4]
- 否则 → 派遣 1 个 product agent 修正，回到本步骤重新评审
- 3 轮后仍未通过 → 标注残留问题，进入 [4]

### [4] 落地输出

将 `spec-draft.md` 重命名为 `spec.md`（去掉 `-draft` 后缀）。在终端汇报：
- Capability 数
- Requirement 总数
- Scenario 总数（正常路径 / 异常路径）
- 置信度（评审通过 / 带债通过）

---

## 修订模式

反问主人「想修订哪个 Capability」，提供选项（从 proposal.md 的 Capabilities 清单生成）。

只跑对应 Capability 的生成阶段，merge 结果回 spec.md，不动其他 Capability。评审循环只检查变更范围。

---

## 补全模式

用结构性元素清单扫描 specs/*.md，识别缺失项：
- Requirement 缺失异常路径 Scenario
- Requirement 缺失追溯字段
- Capability 在 proposal.md 中有但 specs/ 中无对应文件

直接在缺失位置生成补全内容，评审循环。

---

## Agent 派遣 Prompt 模板

### product agent（Requirement 生成）

```
当前是特性级 specs 阶段，为 Capability「<capability>」生成 spec.md。

**任务模式**：特性需求定义主角（不重新识别 Actor，复用产品级 Actor 清单）
**任务**：为 Capability「<capability>」定义 Requirement + Scenario，输出 specs/<capability>/spec-draft.md。

**输入**：
- proposal.md：change-dir（读该 Capability 的描述）
- research.md：change-dir（读约束清单，作为 Requirement 边界）
- 产品级需求文档：docs/requirements/<相关 Feature>.md（获取 Actor 清单和验收标准）
- 内容模板：openspec-schema/schemas/spec-driven-enhanced/templates/spec.md（plugin 内置模板，必须严格遵循其章节结构与内容要求）

**template_path**：`openspec-schema/schemas/spec-driven-enhanced/templates/spec.md`（写作前 MUST 先读取，按模板章节顺序和占位符要求生成）
**output_path**：`specs/<capability>/spec-draft.md`（change-dir）

**输出要求**：
- 严格遵循 `openspec-schema/schemas/spec-driven-enhanced/templates/spec.md` 的章节结构、占位符说明和自检清单
- 模板已定义 Delta 格式、Requirements Overview、Non-Functional Requirements 五类等要求，无需在本 prompt 中重复
- 每条 Requirement 至少包含一个正常路径 Scenario 和一个异常路径 Scenario
- Scenario 必须使用 4 个 hashtag（`####`）

**质量约束**：
- Requirement 可测试（读完能明确判断"通过"还是"不通过"）
- Scenario WHEN 描述具体的前置状态和触发动作
- Scenario THEN 描述可验证的预期结果
- 异常路径聚焦业务语义（权限、配额、冲突等），不罗列系统级异常
- 禁止在 spec.md 中写实现细节（如具体代码、API 签名、数据结构）

写入 `specs/<capability>/spec-draft.md`。
```

### product-reviewer agent

```
当前是特性级 specs 阶段，评审 specs/<capability>/spec-draft.md。

**任务**：从产品视角评审 spec 质量。

**被评审对象**：<路径>
**被评审 template 路径**：`openspec-schema/schemas/spec-driven-enhanced/templates/spec.md`（评审锚点来源 1：章节结构、必填项、自检清单）
**review_output_path**：`specs/<capability>/spec-review.md`（change-dir，多轮追加同一文件）
**report_template_path**：`templates/review-report.md`（如存在）
**复杂度档位**：中等（≥5 个质疑点）

**评审维度**：
1. 模板符合性：是否严格遵循 `openspec-schema/schemas/spec-driven-enhanced/templates/spec.md` 的章节结构、Delta 格式、Scenario 层级、NFR 五类覆盖要求
2. 通用质量（8 项）：需求合理性、必要性、完整性、清晰性、可验收性、异常路径质量、安全覆盖、非功能需求覆盖

**输出**：
问题清单（CRITICAL / HIGH / MEDIUM / LOW），计算缺陷密度。
```

### architect-reviewer agent

```
当前是特性级 specs 阶段，评审 specs/<capability>/spec-draft.md。

**任务**：从架构视角评审 spec 与约束/追溯的一致性。

**被评审对象**：<路径>
**被评审 template 路径**：`openspec-schema/schemas/spec-driven-enhanced/templates/spec.md`（评审锚点来源 1：章节结构、必填项、自检清单）
**review_output_path**：`specs/<capability>/spec-review.md`（change-dir，多轮追加同一文件）
**report_template_path**：`templates/review-report.md`（如存在）
**复杂度档位**：中等（≥5 个质疑点）

**评审维度**：
1. 模板符合性：是否严格遵循 `openspec-schema/schemas/spec-driven-enhanced/templates/spec.md` 的章节结构、Delta 格式、NFR 五类覆盖要求
2. 与 research.md 约束的一致性：Requirement 是否违反约束清单中的约束
3. 与产品级需求的追溯链：每条 Requirement 的追溯字段是否正确填写
4. Delta 格式正确性：ADDED / MODIFIED / REMOVED / RENAMED 章节是否符合 Delta 语义
5. 非功能需求与约束的一致性：NFR 中的量化指标是否与 research.md 约束及产品级非功能目标一致

**输出**：
问题清单（CRITICAL / HIGH / MEDIUM / LOW），计算缺陷密度。
```

---

## 禁忌项

- 禁止在 spec.md 中写实现细节（如具体代码、API 签名、数据结构）
- 禁止破坏 Delta 格式（MODIFIED 必须复制完整 Requirement block，不能只写差异）
- 禁止 Scenario 使用 3 个 hashtag 或 bullet（必须 4 个 hashtag：####）
- 禁止跳过评审循环直接输出
- 禁止重新识别 Actor（从产品级需求文档中获取已识别的 Actor 清单）

---

## 与其他 skill 的协作

- **上游**：proposal.md + research.md（由主人创建）
- **下游**：design.md（由 `devforge-feature-design` 读取 specs/*.md）
- **并行**：无（specs 是 design 的前置依赖）
