---
name: devforge-feature-define
description: 特性级需求定义 skill，产出 specs/*.md（Delta 格式 Requirement + Scenario）。用于 OpenSpec workflow 的 specs artifact 生成。派遣 product agent 生成、product-reviewer + architect-reviewer 双视角评审（最多 3 轮）。当 OpenSpec 引擎触发 specs artifact 生成时自动调用。
allowed-tools: [Read, Write, Edit, Bash, Grep, Glob, Agent]
---

# devforge-feature-define — 特性级需求定义

## 概述

特性级需求定义是 OpenSpec workflow 中 proposal + research 之后的规范化阶段。本 skill 产出 specs/*.md，使用 Delta 格式（ADDED / MODIFIED / REMOVED / RENAMED Requirements）。

**与产品级 define 的区别**：
- 产品级（`/df:product-define`）：Actor 识别 + Feature-Scenario 分层展开，产出 `docs/requirements/*.md`
- 特性级（本 skill）：承接已识别 Actor，在既有 Feature 框架内定义 Requirement + Scenario，产出当前工作目录的 `specs/*.md`

**核心原则**：
1. **承接 Actor**：不重新识别 Actor，从产品级需求文档中获取已识别的 Actor 清单
2. **Delta 语义**：严格遵守 ADDED / MODIFIED / REMOVED / RENAMED 格式，archive 引擎依赖这套语义
3. **Requirement 可测试**：每条 Requirement 读完能明确判断"通过"还是"不通过"
4. **Scenario 完整**：每条 Requirement 至少一个正常路径 + 一个异常路径 Scenario
5. **skill 内化评审**：最多 3 轮 product agent → product-reviewer + architect-reviewer 循环

---

## 工作目录约定

skill 在**当前工作目录**查找输入文件、输出产出文件：
- **输入**：`proposal.md`（必需）、`research.md`（如已存在）、`design.md`（如已存在）
- **输出**：`specs/` 目录及其下的 spec 文件
- **产品级文档**：通过项目根目录的 CLAUDE.md#产品级文档索引定位

**调用方式**：
- **OpenSpec workflow 调用**：workflow 先 `cd openspec/changes/<name>/`，然后调用 skill
- **手动调用**：用户先 `cd` 到包含 `proposal.md` 的目录，然后调用 `/df:define`

## 启动检测

检查当前工作目录的 `specs/` 目录：
- **不存在或为空** → 进入「初次生成」模式
- **已存在 spec 文件** → 反问主人「修订 / 补全」，按指定模式运行

如果当前工作目录无 `proposal.md`，立即报错并提示主人 `cd` 到正确目录。

---

## 初次生成模式

### [1] 上下文准备

读取以下输入：
1. **proposal.md**：本特性的 Capabilities 清单（每个 Capability 对应一个 spec 文件）
2. **research.md**：约束清单 + 设计空间地图（作为 Requirement 边界依据）
3. **产品级需求文档**（按需）：`docs/requirements/` 下相关 Feature 规格，获取 Actor 清单和验收标准
4. **design.md**（如已存在）：了解实现方案，避免 spec 与 design 矛盾
5. **spec.md template**：`openspec/schemas/spec-driven-enhanced/templates/spec.md`

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
**任务**：为 Capability「<capability>」定义 Requirement + Scenario。

**输入**：
- proposal.md：当前工作目录（读该 Capability 的描述）
- research.md：当前工作目录（读约束清单，作为 Requirement 边界）
- 产品级需求文档：docs/requirements/<相关 Feature>.md（获取 Actor 清单和验收标准）
- spec.md template_path：openspec/schemas/spec-driven-enhanced/templates/spec.md

**output_path**：`specs/<capability>/spec-draft.md`（当前工作目录）

**输出**：
使用 Delta 格式（## ADDED Requirements / ## MODIFIED Requirements / ## REMOVED Requirements / ## RENAMED Requirements）。
每条 Requirement：
- 使用 SHALL/MUST 表达规范性要求
- 至少一个正常路径 + 一个异常路径 Scenario
- 填写追溯字段（关联 docs/requirements/ 或"不适用：<原因>"）
- Scenario 必须 4 个 hashtag（####）

写入 `specs/<capability>/spec-draft.md`。

**质量约束**：
- Requirement 可测试（读完能明确判断"通过"还是"不通过"）
- Scenario WHEN 描述具体的前置状态和触发动作
- Scenario THEN 描述可验证的预期结果
- 异常路径聚焦业务语义（权限、配额、冲突等），不罗列系统级异常
```

### product-reviewer agent

```
当前是特性级 specs 阶段，评审 specs/<capability>/spec-draft.md。

**被评审对象**：<路径>
**被评审 template_path**：openspec/schemas/spec-driven-enhanced/templates/spec.md
**review_output_path**：`specs/<capability>/spec-review.md`（多轮追加同一文件）
**report_template_path**：`.claude/templates/review-report.md`（如存在）
**复杂度档位**：中等（≥5 个质疑点，覆盖 7 项维度）

**评审维度**（视角清单，7 项）：
- 需求合理性：每条 Requirement 本身是否合理（不过度、不遗漏、不矛盾）
- 需求必要性：每条 Requirement 是否必要（能否追溯到 proposal Capability 或产品级���求）
- 需求完整性：Requirement 集合是否完整覆盖问题域
- 需求清晰性：每条 Requirement 是否清晰无歧义
- 需求可验收性：每条 Requirement 是否可独立验收
- 异常路径质量：每条 Requirement 的异常路径 Scenario 是否从业务语义出发
- 安全覆盖：安全相关的行为是否有对应 Requirement 覆盖

**输出**：
问题清单（CRITICAL / HIGH / MEDIUM / LOW），计算缺陷密度。
```

### architect-reviewer agent

```
当前是特性级 specs 阶段，评审 specs/<capability>/spec-draft.md。

**被评审对象**：<路径>
**被评审 template_path**：openspec/schemas/spec-driven-enhanced/templates/spec.md
**review_output_path**：`specs/<capability>/spec-review.md`（多轮追加同一文件）
**report_template_path**：`.claude/templates/review-report.md`（如存在）
**复杂度档位**：中等（≥5 个质疑点）

**评审维度**（3 项）：
- 与 research.md 约束的一致性：Requirement 是否违反约束清单中的约束
- 与产品级需求的追溯链：每条 Requirement 的追溯字段是否正确填写
- Delta 格式正确性：ADDED / MODIFIED / REMOVED / RENAMED 章节是否符合 OpenSpec 语义

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

- **上游**：proposal.md + research.md（由 OpenSpec 引擎或主人创建）
- **下游**：design.md（由 `devforge-feature-design` 读取 specs/*.md）
- **并行**：无（specs 是 design 的前置依赖）
