---
name: devforge-spec-review
description: 文档评审 skill，单轮全维度扫描，输出 review.md 报告。评审 proposal/specs/design 三类文档，输出问题清单（CRITICAL/HIGH/MEDIUM/LOW）+ AI 建议决策。默认不做修复、不执行门径；带 autofix 时进入自动修复循环。用于特性级 workflow 的 review artifact 生成或手动临时体检。
allowed-tools: [Read, Write, Edit, Bash, Grep, Glob, Agent]
parameters:
  - name: autofix
    description: 评审后自动修复文档问题（默认只评审不修复）
    required: false
    default: false
---

# devforge-spec-review — 文档评审

## 概述

文档评审是 design 完成后、实现前的质量体检。本 skill 产出 review.md，包含两部分：
1. **AI 评审报告**：单轮扫描，输出问题清单（按 CRITICAL/HIGH/MEDIUM/LOW 分级）+ AI 建议决策
2. **Tech Leader 最终决策区**：留空，由 Tech Leader 在 OpenSpec 流程中人工填写

**两种运行模式**：
- **默认模式**：单轮扫描，输出问题清单，**不做修复**。用于生成 review artifact 或临时体检
- **`autofix` 模式**：评审后若未达 PASS，自动派遣修复 agent 修改问题，重新评审，最多循环 3 轮。循环结束后仍未 PASS 的，输出最终 review.md 供人工决策

**与 skill 内化评审的关系**：
- feature-research / feature-define / feature-design 三个 skill 内部已经做过深度评审循环（最多 3 轮自修），保证基础质量
- 本 skill 是「质量体检 + 报告产出」：默认单轮扫描 19 项核心维度；`autofix` 模式下额外提供独立的外部修复循环

**核心原则**：
1. **默认单轮扫描**：不带 `autofix` 时不做修复循环，只输出问题清单
2. **19 项核心维度**：跨文档一致性（6 项）+ Proposal 质量（2 项）+ Specs 质量（4 项）+ Design 质量（7 项）
3. **只做报告，不执行门径**：AI 建议决策写入报告，最终人工决策由 OpenSpec 流程控制
4. **双模式触发**：workflow 自动触发 + 手动临时体检

---

## 工作目录约定

skill 在 **change-dir** 查找输入文件、输出产出文件：
- **change-dir**：最终要评审的 change 目录，目录下包含 `proposal.md`、`specs/**/*.md`、`design.md`
- **change-dir 解析顺序**：
  1. 用户显式传入 `--change-dir <path>` → 直接使用
  2. 当前工作目录本身已是 change 目录（直接包含 `proposal.md` / `specs/` / `design.md` 中的至少一个） → 直接使用当前目录
  3. 在当前工作目录下查找 `openspec/changes/` → 在该目录下自动选择合适 change
  4. 以上都失败 → 报错并提示用户
- **输入**：`proposal.md`、`specs/**/*.md`、`design.md`
- **输出**：`review.md`（写入 change-dir）
- **报告模板**：`openspec-schema/schemas/spec-driven-enhanced/templates/review.md`（review.md 格式模板）

**调用方式**：
- **手动调用**：用户先 `cd` 到 change 目录，然后调用 `/df:spec-review`；或显式传入 `--change-dir <path>`
- **workflow 调用**：由主会话传入 `--change-dir <path>`，以指定目录为工作上下文

## 启动检测

### 步骤 1：解析 change-dir

按以下顺序确定 change-dir：

1. **显式参数**：由 `--change-dir <path>` 参数指定，直接使用
2. **当前目录即 change 目录**：当前工作目录下已存在 `proposal.md`、`specs/**/*.md`、`design.md` 中的至少一个，直接使用当前目录
3. **自动发现 openspec/changes**：
   - 在当前工作目录下查找 `openspec/changes/` 目录
   - 找到后，列出其下所有子目录，过滤出包含 `proposal.md`、`specs/**/*.md`、`design.md` 中至少一个的候选 change 目录
   - **只有一个候选** → 自动作为 change-dir
   - **多个候选** → 主会话根据上下文推断最合适的 change：
     - 优先选择当前 git 分支名匹配的 change 目录
     - 其次选择最近有文件修改的 change 目录
     - 无法推断时，列出候选目录向用户确认
   - **没有候选** → 报错：未找到可用 change 目录

### 步骤 2：检测 autofix 模式

由 `autofix` 参数开启。

### 步骤 3：读取现有 review.md

读取 change-dir 的 `review.md`：
- **不存在** →
  - 不带 `autofix`：进入「初次评审」模式
  - 带 `autofix`：先执行一次「初次评审」模式，然后进入「autofix 修复循环」
- **已存在** →
  - 不带 `autofix`：反问主人「重新评审 / 查看现有评审」
  - 带 `autofix`：直接进入「autofix 修复循环」（以现有 review.md 作为第 1 轮评审结果）

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

- 不带 `autofix`：按模板写入单轮报告，「AI Review Rounds」下记录为 **Round 1**
- 带 `autofix`（首轮）：同样写入 **Round 1**；后续循环中在此基础上追加 Round

`Tech Leader 最终决策区` 留空，由 OpenSpec 流程中 Tech Leader 人工填写。

完成后提示用户：review.md 已生成，AI 建议决策已写入报告。后续由 Tech Leader 在「Tech Leader 最终决策区」填写最终决策，OpenSpec 流程会根据该决策决定是否允许进入 tasks 阶段。

---

## autofix 修复循环

本章节仅在带 `autofix` 参数时执行。进入本模式时，`review.md` 必须已经存在（由启动检测阶段保证：不存在时会先执行一次「初次评审模式」）。

### 循环条件

以下两个条件同时满足时继续循环：
1. 当前 `review.md` 的 AI 建议决策不是 **PASS**
2. 已执行的修复轮次 < 3

### 每轮循环步骤

#### 步骤 1：主会话判断是否需要修复

主会话从当前 `review.md` 的 `## Review Conclusion` 部分读取 AI 建议决策（不需要读取完整问题清单）：
- **PASS** → 跳出循环，提示用户 autofix 完成
- **PASS WITH CONDITIONS / REJECT** → 继续本轮修复

#### 步骤 2：并行派遣修复 agent

根据实际存在的文件，并行派遣修复 agent。每个 agent 负责读取 `review.md` 中的问题清单、定位自己负责的文件、执行修复并写回原文件。

- **`product`（修复 proposal + specs）**：当 `proposal.md` 或 `specs/**/*.md` 存在时派遣；负责修复 location 落在这些文件上的问题
- **`architect`（修复 design）**：当 `design.md` 存在时派遣；负责修复 location 落在 `design.md` 上的问题

**问题归属规则**：
- location 中文件路径属于 `proposal.md` 或 `specs/**/*.md` 的问题 → 由 `product` 修复
- location 中文件路径属于 `design.md` 的问题 → 由 `architect` 修复
- 一个问题跨多个文件时，各文件由对应 agent 分别修复；agent 读取问题时应自行判断与本职相关的部分

#### 步骤 3：agent 修复并写回

修复 agent 按以下要求执行：
1. 读取 `review.md` 中自己负责文件的问题清单
2. 读取对应模板（proposal/spec/design template）确认格式约束
3. 对 MEDIUM / HIGH / CRITICAL 问题执行修复；LOW 问题可选择性修复
4. 使用 `Edit` 工具直接修改原文件，禁止重写无关章节
5. 输出修改摘要：修改了哪些文件、修复了哪些问题、引入了哪些值得重新评审的变化

#### 步骤 4：重新评审并追加 Round

1. 重新执行「初次评审模式」的步骤 [1]–[4]，生成新一轮问题清单、缺陷密度和 AI 建议决策
2. 主会话读取当前 `review.md` 中 `## AI Review Rounds` 到 `## Review Conclusion` 之间的轻量结构，确定当前最大 Round 数 N
3. 基于新一轮评审结果，按 template 格式组装 **Round N+1**（含 Issues Found 表格、Round Result），插入到 `## Review Conclusion` 之前
4. 更新 `## Review Conclusion` 中的 AI 建议决策、建议理由和遗留问题

**注意**：不要删除现有 `review.md`，而是在其 `AI Review Rounds` 部分追加新轮次，保留 autofix 完整历史。

#### 步骤 5：循环计数 + 1

### 循环结束

- **因 PASS 结束**：提示用户 autofix 完成，当前 review.md 为最终报告
- **因达到 3 轮上限结束**：提示用户已达到最大自动修复轮次，review.md 中保留最终评审结果和 AI 建议决策，需由 Tech Leader 人工决策

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

## autofix 修复 agent Prompt 模板

### product agent（autofix 修复 proposal + specs）

```
当前是 review 的 autofix 阶段，负责根据 review.md 中的问题清单修复 proposal.md 和 specs/**/*.md。

**任务**：修复属于你负责文件的问题。

**负责修复的文件**：
- proposal.md：<路径>（如存在）
- specs/**/*.md：<路径列表>（如存在）

**参考输入**：
- review.md：<路径>（读取其中 Location 落在上述文件的问题，按优先级 CRITICAL → HIGH → MEDIUM → LOW 依次修复）
- proposal.md 模板：`openspec-schema/schemas/spec-driven-enhanced/templates/proposal.md`
- spec 模板：`openspec-schema/schemas/spec-driven-enhanced/templates/spec.md`

**修复规则**：
1. 只修改 Location 落在 proposal.md 或 specs/**/*.md 的问题
2. 修复时必须保持对应模板的章节结构和必填项
3. 优先修复 CRITICAL / HIGH / MEDIUM；LOW 问题可选择性修复
4. 禁止为修复一个问题而破坏其他已通过评审的维度
5. 禁止重写无关章节；优先使用 Edit 做局部修改
6. 若某个问题因信息不足无法修复，在修改摘要中说明并标记为残留风险

**输出**：
1. 直接修改原文件（proposal.md / specs/**/*.md）
2. 修改摘要：修复了哪些问题、修改了哪些文件、残留风险
```

### architect agent（autofix 修复 design）

```
当前是 review 的 autofix 阶段，负责根据 review.md 中的问题清单修复 design.md。

**任务**：修复属于 design.md 的问题。

**负责修复的文件**：
- design.md：<路径>（如存在）

**参考输入**：
- review.md：<路径>（读取其中 Location 落在 design.md 的问题，按优先级 CRITICAL → HIGH → MEDIUM → LOW 依次修复）
- 上游文档（按需读取，确保修复后仍然覆盖 specs 的 Requirement）：
  - proposal.md：<路径>
  - specs/**/*.md：<路径列表>
- design.md 模板：`openspec-schema/schemas/spec-driven-enhanced/templates/design.md`

**修复规则**：
1. 只修改 Location 落在 design.md 的问题
2. 修复时必须保持 design.md 模板的章节结构和必填项
3. 优先修复 CRITICAL / HIGH / MEDIUM；LOW 问题可选择性修复
4. 禁止为修复一个问题而破坏其他已通过评审的维度
5. 禁止重写无关章节；优先使用 Edit 做局部修改
6. 若某个问题因信息不足无法修复，在修改摘要中说明并标记为残留风险

**输出**：
1. 直接修改原文件（design.md）
2. 修改摘要：修复了哪些问题、修改了哪些文件、残留风险
```

---

## 与其他 skill 的协作

- **上游**：proposal.md + specs/**/*.md + design.md（由 feature-research / feature-define / feature-design 生成）
- **下游**：tasks.md（由主人基于 review.md 的 Tech Leader 决策生成，决策为 PASS 或 PASS WITH CONDITIONS 时才允许进入实现阶段）
- **并行**：无（review 是 tasks 的前置依赖）
