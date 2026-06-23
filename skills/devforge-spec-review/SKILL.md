---
name: devforge-spec-review
description: 文档评审 skill，单轮全维度扫描，输出 review.md 报告。评审 proposal/specs/design 三类文档，输出问题清单（CRITICAL/HIGH/MEDIUM/LOW）+ AI 建议决策。不做修复、不执行门径。用于特性级 workflow 的 review artifact 生成或手动临时体检。
allowed-tools: [Read, Write, Edit, Bash, Grep, Glob, Agent]
---

# devforge-spec-review — 文档评审

## 概述

文档评审是 design 完成后、实现前的质量体检。本 skill 产出 review.md，包含两部分：
1. **AI 评审报告**：单轮扫描，输出问题清单（按 CRITICAL/HIGH/MEDIUM/LOW 分级）+ AI 建议决策。**不做修复**
2. **Tech Leader 最终决策区**：留空，由 Tech Leader 在 OpenSpec 流程中人工填写

**与 skill 内化评审的关系**：
- feature-research / feature-define / feature-design 三个 skill 内部已经做过深度评审循环（最多 3 轮自修），保证基础质量
- 本 skill 是「质量体检 + 报告产出」：单轮扫描 19 项核心维度，发现问题不修复，输出清单供人决策

**核心原则**：
1. **单轮扫描**：不做修复循环，只输出问题清单
2. **19 项核心维度**：跨文档一致性（6 项）+ Proposal 质量（2 项）+ Specs 质量（4 项）+ Design 质量（7 项）
3. **只做报告，不执行门径**：AI 建议决策写入报告，最终人工决策由 OpenSpec 流程控制
4. **双模式触发**：workflow 自动触发 + 手动临时体检

---

## 工作目录约定

skill 在 **change-dir**（默认当前工作目录）查找输入文件、输出产出文件：
- **change-dir**：由 `--change-dir <path>` 参数指定，无参数时默认当前工作目录
- **输入**：`proposal.md`、`specs/**/*.md`、`design.md`
- **输出**：`review.md`
- **报告模板**：`openspec-schema/schemas/spec-driven-enhanced/templates/review.md`（review.md 格式模板）

**调用方式**：
- **手动调用**：用户先 `cd` 到包含 `proposal.md` 的目录，然后调用 `/df:spec-review`；或显式传入 `--change-dir <path>`
- **workflow 调用**：由主会话传入 `--change-dir <path>`，以指定目录为工作上下文

## 启动检测

**change-dir**：由 `--change-dir <path>` 参数指定，无参数时默认当前工作目录。

读取 change-dir 的 `review.md`：
- **不存在** → 进入「初次评审」模式
- **已存在** → 反问主人「重新评审 / 查看现有评审」

---

## 初次评审模式

### [1] 上下文准备

主会话做轻量准备，为调度 agent 和计分提供必要信息：

1. **验证输入存在性**：确认 change-dir 下存在 `proposal.md`、`specs/**/*.md`、`design.md` 中的至少一个；一个都不存在则立即报错并停止。存在多个时，由 agent 按需评审实际存在的文件。
2. **发现产品级架构文档**：用 `Glob` 列出项目根目录 `docs/architecture/` 下可能与本次变更相关的文件路径，供 architect-reviewer 读取。
3. **统计 spec 文件数**：用于后续缺陷密度计算的文档总数。
4. **读取 review.md template**：`openspec-schema/schemas/spec-driven-enhanced/templates/review.md`，作为组装最终 review.md 的格式依据。

主会话**不读取** proposal.md / specs/**/*.md / design.md / 产品级架构文档的内容；由各 agent 在 prompt 中按需读取。

### [2] 并行评审

根据实际存在的文件，并行派遣 reviewer agent：
- **`product-reviewer（proposal + specs）`**：当 `proposal.md` 或 `specs/**/*.md` 存在时派遣；评审 Proposal 质量 + Specs 质量
- **`product-reviewer（cross-doc）`**：当 `proposal.md`、`specs/**/*.md`、`design.md` 中任一存在时派遣；评审跨文档一致性与格式合规（6 项）；其中需要跨文档比对的维度仅在至少两个文档存在时检查
- **`architect-reviewer`**：当 `design.md` 存在时派遣；评审 Design 质量 + 对照 `docs/architecture/` 检查架构约束

每个被派遣的 reviewer 产出问题清单（CRITICAL / HIGH / MEDIUM / LOW）。

**被评审文件缺失时的处理**：agent 只读取实际存在的文件；若因关键文件缺失导致某维度无法评审，在问题清单中标注为 HIGH 或 MEDIUM（如「design.md 缺失，无法评审 Requirement→Decision 一致性」）。

### [3] 汇总计分

主会话收集实际派遣的 agent 的评审结果，合并问题清单，去重后分别计算：
- proposal.md 的缺陷总分（存在时）
- specs/ 中每个 spec 文件的缺陷总分（存在时）
- design.md 的缺陷总分（存在时）

跨文档一致性问题按 Location 归属到对应文档参与计分。

**缺陷密度计算公式**：
```
单文档缺陷密度 = 该文档的问题分数之和 / 1
全局缺陷密度 = 所有文档的问题分数之和 / 实际存在的文档总数
```

问题分值：**CRITICAL=10分, HIGH=3分, MEDIUM=1分, LOW=0.1分**

**示例**：
- proposal.md：1 个 HIGH（3 分）+ 2 个 MEDIUM（2 分）= 5 分
- spec1.md：1 个 CRITICAL（10 分）= 10 分
- design.md：3 个 MEDIUM（3 分）= 3 分
- 全局缺陷密度 = (5 + 10 + 3) / 3 = 6.0

### [4] AI 建议决策

根据缺陷密度和 CRITICAL 问题数，给出 AI 建议：
- **PASS**：所有文档单文档缺陷密度均 ≤ 2.0，且无 CRITICAL 问题
- **PASS WITH CONDITIONS**：无 CRITICAL 问题，但有文档单文档缺陷密度 > 2.0（仅 MEDIUM/LOW 累积超标）
- **REJECT**：任一文档有 CRITICAL 问题，或全局缺陷密度 > 5.0

### [5] 写入 review.md

主会话按 `openspec-schema/schemas/spec-driven-enhanced/templates/review.md` 的章节结构，将合并后的问题清单、缺陷密度、AI 建议决策组装写入 `review.md`。

`Tech Leader 最终决策区` 留空，由 OpenSpec 流程中 Tech Leader 人工填写。

完成后提示用户：review.md 已生成，AI 建议决策已写入报告。后续由 Tech Leader 在「Tech Leader 最终决策区」填写最终决策，OpenSpec 流程会根据该决策决定是否允许进入 tasks 阶段。

---

## 重新评审模式

删除现有 review.md，重新执行「初次评审」模式。

---

## 评审标准

以下维度清单用于主会话调度、状态跟踪和计分。各维度的具体评审定义见对应 agent prompt 中的「评审标准定义」。

**跨文档一致性与格式合规**（由 `product-reviewer（cross-doc）` 统一评审）：
- 模板符合性
- 内部一致性
- 同一外部行为一致性
- 范围一致性
- 跨文档叙事连贯性
- 写作质量与外部视角

**Proposal 质量**（由 `product-reviewer（proposal + specs）` 评审）：
- 动机合理性
- 方案合理性

**Specs 质量**（由 `product-reviewer（proposal + specs）` 评审）：
- 需求合理性与必要性
- 需求完整性与边界
- 需求清晰性与可验收性
- 异常路径与非功能需求

**Design 质量**（由 `architect-reviewer` 评审）：
- 方案可行性与合理性
- 方案竞争力
- 架构一致性
- 设计内部一致性
- 可维护性与故障处理
- 决策备选方案
- 性能与升级影响评估

---

## Agent 派遣 Prompt 模板

### product-reviewer agent（proposal + specs）

```
当前是 review 阶段，从产品视角评审 proposal 和 specs。

**任务**：从产品视角评审。

**被评审对象**（如存在）：
- proposal.md：<路径>
- specs/**/*.md：<路径列表>

**被评审 template 路径**（评审锚点来源 1：章节结构、必填项、自检清单；请读取对应 template 并逐项核对具体格式要求）：
- proposal.md 模板：`openspec-schema/schemas/spec-driven-enhanced/templates/proposal.md`
- spec 模板：`openspec-schema/schemas/spec-driven-enhanced/templates/spec.md`

**review_output_path**：`review.md`（change-dir，多视角合并到同一文件）

**评审维度与标准**（按此逐项评审；具体章节要求以 template 文件为准）：

**Proposal 质量**
- **动机合理性**：Why 清晰说明问题根因、业务价值、影响范围，不只是表面描述
- **方案合理性**：Capabilities 从外部调用方/用户视角定义，是可见的行为能力或质量属性承诺；覆盖完整且粒度适当（能独立验收、避免为内部实现动作拆分过细）；命名规范；Acceptance Criteria 可验证；考虑过替代方案

**Specs 质量**
- **需求合理性与必要性**：每条 Requirement 合理、必要，不过度、不遗漏、不矛盾，能追溯到 proposal 的 Capability
- **需求完整性与边界**：Requirement 集合从领域视角覆盖问题域，边界明确（不做什么 + 理由）
- **需求清晰性与可验收性**：每条 Requirement 清晰无歧义，可独立验收；Scenario 使用 WHEN/THEN 表达可验证的预期结果，测试人员能据此推导集成测试用例
- **异常路径与非功能需求**：异常路径从业务语义出发；Non-Functional Requirements 覆盖所需维度，指标可量化、可验证并落地到 Requirement

**输出**：
问题清单（CRITICAL / HIGH / MEDIUM / LOW），每个问题标注 Location（文件:章节）。
```

### architect-reviewer agent

```
当前是 review 阶段，从架构视角评审 design 是否满足 specs 的 Requirement，并符合产品级架构约束。

**任务**：从架构视角评审。

**被评审对象**（如存在）：
- design.md：<路径>

**参考文档**（按需读取）：
- proposal.md：<路径>（理解变更范围和商业目标）
- specs/**/*.md：<路径列表>（核对 design 是否覆盖每条 Requirement）
- 产品级架构文档：`docs/architecture/<相关子系统>/design.md` 及 ADR（检查 design 是否违反架构原则）

**被评审 template 路径**（评审锚点来源 1：章节结构、必填项、自检清单；请读取对应 template 并逐项核对具体格式要求）：
- design.md 模板：`openspec-schema/schemas/spec-driven-enhanced/templates/design.md`

**review_output_path**：`review.md`（change-dir，多视角合并到同一文件）

**评审维度与标准**（按此逐项评审；具体章节要求以 template 文件为准）：

**Design 质量**
- **方案可行性与合理性**：技术方案能满足 specs 的每条 Requirement；关键决策有 trade-off 分析
- **方案竞争力**：对比业界标准或已知方案，在性能、可扩展性、成本等关键维度有说服力
- **架构一致性**：不违反 docs/architecture/ 中的架构原则，如有偏差须显式说明原因
- **设计内部一致性**：Decision 之间无矛盾，接口定义与实现方案匹配
- **可维护性与故障处理**：复杂度合理、不过度工程化；关键路径的失败模式、降级策略、恢复机制充分
- **决策备选方案**：有选择空间的决策有备选方案和 trade-off 分析
- **性能与升级影响评估**：关键路径延迟和吞吐量有量化分析；Upgrade Impact 识别升级流程风险并对应 spec NFR 目标

**输出**：
问题清单（CRITICAL / HIGH / MEDIUM / LOW），每个问题标注 Location（文件:章节）。
```

### product-reviewer agent（cross-doc）

```
当前是 review 阶段，统一评审 proposal / specs / design 的跨文档一致性与格式合规。

**任务**：跨文档一致性与格式合规评审。

**被评审对象**（如存在）：
- proposal.md：<路径>
- specs/**/*.md：<路径列表>
- design.md：<路径>

**被评审 template 路径**（评审锚点来源 1：章节结构、必填项、自检清单；请读取对应 template 并逐项核对具体格式要求）：
- proposal.md 模板：`openspec-schema/schemas/spec-driven-enhanced/templates/proposal.md`
- spec 模板：`openspec-schema/schemas/spec-driven-enhanced/templates/spec.md`
- design.md 模板：`openspec-schema/schemas/spec-driven-enhanced/templates/design.md`

**review_output_path**：`review.md`（change-dir，多视角合并到同一文件）

**评审维度与标准**（按此逐项评审；具体章节要求以 template 文件为准；第 2-5 项需至少两个文档存在时才可检查）：

1. **模板符合性**：proposal/specs/design 是否分别遵循对应模板的章节结构、必填项和自检清单
2. **内部一致性**：Capability、Requirement、Design/Decisions 之间无矛盾；Interface Changes 覆盖 proposal Impact 中识别的接口/协议/数据格式影响方向；Risks / Upgrade Impact 覆盖 specs 中 NFR 的关键风险
3. **同一外部行为一致性**：同一 Capability / Requirement 对应的外部可见行为在三类文档中的描述一致（包括正常路径、异常路径、边界条件）
4. **范围一致性**：proposal 的 Capabilities / What Changes / Impact 所表达的范围在 specs 和 design 中得到尊重；design 的 Goals / Non-Goals 与 proposal 的范围一致
5. **跨文档叙事连贯性**：三类文档组合起来形成清晰、可读的变更故事线；专有名词、术语一致
6. **写作质量与外部视角**：从外部调用方/用户视角描述可见行为，避免源码级细节；术语准确、长句拆分、叙事清晰；鼓励图文并茂，但文字本身能独立表达方案

**输出**：
问题清单（CRITICAL / HIGH / MEDIUM / LOW），每个问题标注 Location（文件:章节）。
```

---

## 与其他 skill 的协作

- **上游**：proposal.md + specs/**/*.md + design.md（由 feature-research / feature-define / feature-design 生成）
- **下游**：tasks.md（由主人基于 review.md 的 Tech Leader 决策生成，决策为 PASS 或 PASS WITH CONDITIONS 时才允许进入实现阶段）
- **并行**：无（review 是 tasks 的前置依赖）
