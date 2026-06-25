---
name: devforge-spec-review
description: 文档评审 skill，按各维度的通过标准逐项判定，输出 review.md 报告。评审 proposal/specs/design 三类文档，输出未达标问题清单（CRITICAL/HIGH/MEDIUM/LOW）+ AI 建议决策。默认只评审不修复；带 autofix 时按优先级自动修复所有级别问题并以全新上下文重新评审，最多 3 轮。用于特性级 workflow 的 review artifact 生成或临时评审。
allowed-tools: [Read, Write, Edit, Bash, Grep, Glob, Agent]
parameters:
  - name: autofix
    description: 评审后按优先级自动修复所有级别问题（CRITICAL/HIGH/MEDIUM/LOW），默认只评审不修复
    required: false
    default: false
---

# devforge-spec-review — 文档评审

## 概述

文档评审是 design 完成后、实现前的质量体检。本 skill 产出 review.md，包含两部分：
1. **AI 评审报告**：按各项维度的「通过标准」逐项判定，输出未达标问题清单（按 CRITICAL / HIGH / MEDIUM / LOW 分级）+ AI 建议决策
2. **Tech Leader 最终决策区**：留空，由 Tech Leader 在 OpenSpec 流程中人工填写

**两种运行模式**：
- **默认模式**：单轮评审判定，输出问题清单，**不做修复**。用于生成 review artifact 或临时评审
- **`autofix` 模式**：评审后若未达 PASS，自动派遣修复 agent 按优先级修复各级问题（CRITICAL → HIGH → MEDIUM → LOW），然后以全新上下文重新评审，最多循环 3 轮。循环结束后仍未 PASS 的，输出最终 review.md 供人工决策

**与 skill 内化评审的关系**：
- feature-research / feature-define / feature-design 三个 skill 内部已经做过深度评审循环（最多 3 轮自修），保证基础质量
- 本 skill 是「质量判定 + 报告产出」：默认单轮按各项核心维度的通过标准判定；`autofix` 模式下按优先级自动修复各级问题

**核心原则**：
1. **判定达标而非穷举问题**：每个维度有明确「通过标准」，满足即不提出问题，只在未满足时记录问题
2. **19 项核心维度**：跨文档一致性（6 项）+ Proposal 质量（2 项）+ Specs 质量（4 项）+ Design 质量（7 项）
3. **只做报告，不执行门径**：AI 建议决策写入报告，最终人工决策由 OpenSpec 流程控制

---

## 模板路径解析

本 skill 引用的 `openspec-schema/...` 路径均相对于 DevForge plugin 安装目录。plugin 安装目录 = 文档顶部「Base directory for this skill」指示目录的上两级。

读取模板时请拼接为绝对路径：`<skill_base_dir>/../../openspec-schema/schemas/spec-driven-enhanced/templates/<name>.md`。

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
- **报告模板**：`../../openspec-schema/schemas/spec-driven-enhanced/templates/review.md`（review.md 格式模板）

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
3. **读取 review.md template**：`../../openspec-schema/schemas/spec-driven-enhanced/templates/review.md`，作为组装最终 review.md 的格式依据。

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
单文档缺陷密度 = 该文档的问题分数之和
```

问题分值：**CRITICAL=10分, HIGH=3分, MEDIUM=1分, LOW=0.1分**

**示例**：
- proposal.md：1 个 HIGH（3 分）+ 2 个 MEDIUM（2 分）= 5 分
- spec1.md：1 个 CRITICAL（10 分）= 10 分
- design.md：3 个 MEDIUM（3 分）= 3 分

### [4] AI 建议决策

根据各文档缺陷密度、CRITICAL 问题数和 HIGH 问题数，给出 AI 建议。评审目标是**判定文档是否达到进入 tasks 阶段的最低质量标准**，而非穷举所有可改进点。

**问题分级判定标准**（reviewer 必须按此归类）：
- **CRITICAL**：存在事实错误、与上游文档直接矛盾、无法通过实现弥补的根本缺陷、或违反安全/合规等硬性约束。必须修复，否则不能 PASS。
- **HIGH**：缺少关键信息或分析不足，显著影响质量。必须全部修复才能 PASS；带 1-2 个 HIGH 可 PASS WITH CONDITIONS。
- **MEDIUM**：表述可更清晰、边界可更完整、建议补充的优化项。
- **LOW**：格式、拼写、minor 文案。

**AI 建议决策**：
- **PASS**：无 CRITICAL 和 HIGH；单文档缺陷密度 ≤ 3.0
- **PASS WITH CONDITIONS**：无 CRITICAL；单文档缺陷密度 > 3.0 但 ≤ 6.0（由 1-2 个 HIGH 或较多 MEDIUM/LOW 导致）
- **REJECT**：存在 CRITICAL；或单文档缺陷密度 > 6.0

### [5] 写入 review.md

主会话按 `../../openspec-schema/schemas/spec-driven-enhanced/templates/review.md` 的章节结构，将合并后的问题清单、缺陷密度、AI 建议决策组装写入 `review.md`。

- 不带 `autofix`：按模板写入单轮报告，「AI Review Rounds」下记录为 **Round 1**
- 带 `autofix`（首轮）：同样写入 **Round 1**；后续循环中在此基础上追加 Round

`Tech Leader 最终决策区` 留空，由 OpenSpec 流程中 Tech Leader 人工填写。

完成后提示用户：review.md 已生成，AI 建议决策已写入报告。后续由 Tech Leader 在「Tech Leader 最终决策区」填写最终决策，OpenSpec 流程会根据该决策决定是否允许进入 tasks 阶段。

---

## autofix 修复循环

本章节仅在带 `autofix` 参数时执行。进入本模式时，`review.md` 必须已经存在（由启动检测阶段保证：不存在时会先执行一次「初次评审模式」）。

### 循环条件

以下两个条件同时满足时继续循环：
1. 当前 `review.md` 的 AI 建议决策是 **REJECT**
2. 已执行的修复轮次 < 3

### 每轮循环步骤

#### 步骤 1：主会话判断是否需要修复

主会话从当前 `review.md` 的 `## Review Conclusion` 部分读取 AI 建议决策（不需要读取完整问题清单）：
- **PASS** 或 **PASS WITH CONDITIONS** → 跳出循环，提示用户 autofix 完成；PASS WITH CONDITIONS 时 Tech Leader 需在最终决策中明确附加条件及闭环时限，附加条件可与 tasks 并行推进，但须在归档前完成
- **REJECT** → 继续本轮修复（说明存在 CRITICAL，或单文档缺陷密度 > 6.0）

#### 步骤 2：串行派遣修复 agent

为避免同一轮内多个修复 agent 并行修改不同文件导致不一致，本轮修复按固定顺序**串行**执行：

1. 先派遣 **`product`（修复 proposal + specs）**：当 `proposal.md` 或 `specs/**/*.md` 存在时派遣；负责修复 location 落在这些文件上的问题，写回后输出本轮修改摘要。
2. 再派遣 **`architect`（修复 design）**：当 `design.md` 存在时派遣；负责修复 location 落在 `design.md` 上的问题。`architect` 执行前必须读取 `product` 本轮的修改摘要，并据此同步调整 design 中对应的 Requirement / Capability / 范围 / 术语表述。

**问题归属规则**：
- location 中文件路径属于 `proposal.md` 或 `specs/**/*.md` 的问题 → 由 `product` 修复
- location 中文件路径属于 `design.md` 的问题 → 由 `architect` 修复
- 一个问题跨多个文件时，各文件由对应 agent 分别修复；agent 读取问题时应自行判断与本职相关的部分

**修复范围**（autofix 每轮保持全新上下文，不以上一轮问题是否关闭作为判断标准）：
- **按优先级修复**：本轮评审中的 CRITICAL → HIGH → MEDIUM → LOW 问题
- **信息不足时保留**：因信息不足无法修复的问题，转入「遗留问题 / 附加条件」，供 Tech Leader 决策时参考

**同轮次一致性上下文**：
- `architect` 修复 design 前，主会话必须将**本轮 `product` 已输出的修改摘要**作为 prompt 上下文传入。
- 若 `product` 不存在（即本轮只改 design），则无同轮次摘要。

#### 步骤 3：agent 修复并写回

修复 agent 按以下要求执行：
1. 读取本轮 `review.md` 中自己负责文件的问题清单
2. 读取对应模板（proposal/spec/design template）确认格式约束
3. 按优先级 CRITICAL → HIGH → MEDIUM → LOW 依次修复；LOW 问题可视修复成本跳过
4. 使用 `Edit` 工具直接修改原文件，禁止重写无关章节
5. 若某个问题因信息不足无法修复，在修改摘要中说明并标记为残留风险
6. 输出修改摘要：修改了哪些文件、修复了哪些问题（含原问题分级）、残留风险

`architect` 额外要求：修复 design 前读取 `product` 本轮修改摘要；若 `product` 的修改改变了 Requirement / Capability / Scenario 的语义，必须同步检查 design.md 中对应表述并一并调整。

#### 步骤 3.5：跨文档一致性同步检查

`architect` 修复 design 写回后，派遣 `product-reviewer（cross-doc）` 做一轮轻量同步检查：

- **只关注本轮修改涉及的内容**：重点检查 `product` 修改 proposal/specs 与 `architect` 修改 design 之间是否出现语义偏差、术语不一致或范围冲突。
- **即时修正**：若同步检查发现问题，直接派遣对应修复 agent 修正，**不增加 autofix 轮次计数**。修正顺序仍遵循 product → architect，确保同轮次一致性闭环。
- **输出**：同步检查摘要（新增不一致 + 已修正项），合并到本轮修复摘要中。

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

以下维度清单用于主会话调度、状态跟踪和计分。**各维度不再追求“找出尽量多问题”，而是按「通过标准」判定：满足通过标准时，不在该维度提出问题；未满足时，按问题分级标准记录 CRITICAL / HIGH / MEDIUM / LOW。**

### 跨文档一致性与格式合规（由 `product-reviewer（cross-doc）` 统一评审）

1. **模板符合性**
   - 通过标准：各文档章节结构、必填项、自检清单与对应 template 一致；缺失章节有合理说明或标注为 N/A。
   - 触发问题：关键必填项缺失、章节顺序严重错乱、未按模板自检清单执行。

2. **内部一致性**
   - 通过标准：Capability、Requirement、Design/Decisions 之间无矛盾；Interface Changes 覆盖 proposal Impact 中识别的接口/协议/数据格式影响方向；Risks / Upgrade Impact 覆盖 specs 中 NFR 的关键风险。
   - 触发问题：同一 Requirement 在 design 中未被覆盖、Impact 与 Interface Changes 范围矛盾、NFR 风险无对应处理。

3. **同一外部行为一致性**
   - 通过标准：同一 Capability / Requirement 对应的外部可见行为在三类文档中的描述一致（正常路径、异常路径、边界条件）。
   - 触发问题：正常/异常/边界行为在不同文档中描述冲突或遗漏。

4. **范围一致性**
   - 通过标准：proposal 的 Capabilities / What Changes / Impact 所表达的范围在 specs 和 design 中得到尊重；design 的 Goals / Non-Goals 与 proposal 的范围一致。
   - 触发问题：design 引入 proposal 未声明的范围、specs 遗漏 proposal 明确承诺的能力。

5. **跨文档叙事连贯性**
   - 通过标准：三类文档组合起来形成清晰、可读的变更故事线；专有名词、术语一致。
   - 触发问题：术语前后不一致、叙事断裂到无法判断变更目的。

6. **写作质量与外部视角**
   - 通过标准：从外部调用方/用户视角描述可见行为；proposal/spec 只承载 **why** 和 **what**，design 承载 **how**；术语准确、长句可理解；文字本身能独立表达方案。
   - 触发问题：proposal/spec 中出现研发视角的内部架构、数据结构、算法、接口实现等 how 细节；关键段落歧义到影响理解、术语错误导致误解。

### Proposal 质量（由 `product-reviewer（proposal + specs）` 评审）

7. **动机合理性**
   - 通过标准：Why 清晰说明问题根因、业务价值、影响范围；核心假设有数据或现状支撑；不只是表面描述。
   - 触发问题：问题根因缺失、业务价值无法量化或无法追溯、影响范围未定义。

8. **方案合理性**
   - 通过标准：Capabilities 从外部调用方/用户视角定义，是可见的行为能力或质量属性承诺；只描述 **what**（外部可见行为），不描述 **how**（实现方案、技术选型、内部架构）；覆盖完整且粒度适当（能独立验收、避免为内部实现动作拆分过细）；命名规范；Acceptance Criteria 可验证；考虑过替代方案。
   - 触发问题：Capabilities 为内部实现动作、包含研发视角的技术方案或架构细节、Acceptance Criteria 不可验证、完全无替代方案分析。

### Specs 质量（由 `product-reviewer（proposal + specs）` 评审）

9. **需求合理性与必要性**
   - 通过标准：每条 Requirement 合理、必要，不过度、不遗漏、不矛盾，能追溯到 proposal 的 Capability。
   - 触发问题：Requirement 与 Capability 无法对应、存在明显过度设计或遗漏核心需求、需求间矛盾。

10. **需求完整性与边界**
    - 通过标准：Requirement 集合从领域视角覆盖问题域，边界明确（不做什么 + 理由）。
    - 触发问题：核心场景缺失、边界未说明导致范围失控。

11. **需求清晰性与可验收性**
    - 通过标准：每条 Requirement 从用户/调用方视角清晰无歧义，只描述 **what**（外部可见行为与预期结果），不描述 **how**（内部实现步骤）；可独立验收；Scenario 使用 WHEN/THEN 表达可验证的预期结果，测试人员能据此推导集成测试用例。
    - 触发问题：Requirement 描述内部实现动作而非外部可见行为、无法验收、Scenario 缺少 THEN 或预期结果模糊。

12. **异常路径与非功能需求**
    - 通过标准：异常路径从业务语义出发；Non-Functional Requirements 覆盖所需维度，指标可量化、可验证并落地到 Requirement。
    - 触发问题：核心异常路径缺失、NFR 指标不可量化或与 Requirement 脱节。

### Design 质量（由 `architect-reviewer` 评审）

13. **方案可行性与合理性**
    - 通过标准：技术方案能满足 specs 的每条 Requirement；关键决策有 trade-off 分析。
    - 触发问题：技术方案无法满足 Requirement、关键决策无任何 trade-off。

14. **方案竞争力**
    - 通过标准：对比业界标准或已知方案，在性能、可扩展性、成本等关键维度有说服力。
    - 触发问题：关键维度完全未与业界对比、明显劣于标准方案却无正当理由。

15. **架构一致性**
    - 通过标准：不违反 `docs/architecture/` 中的架构原则；如有偏差须显式说明原因。
    - 触发问题：违反已声明的架构原则且未说明原因。

16. **设计内部一致性**
    - 通过标准：Decision 之间无矛盾，接口定义与实现方案匹配。
    - 触发问题：Decisions 相互矛盾、接口与实现不匹配。

17. **可维护性与故障处理**
    - 通过标准：复杂度合理、不过度工程化；关键路径的失败模式、降级策略、恢复机制充分。
    - 触发问题：关键路径无失败模式分析、无降级策略、复杂度明显过度。

18. **决策备选方案**
    - 通过标准：有选择空间的决策有备选方案和 trade-off 分析。
    - 触发问题：重大决策无备选方案、无选择理由。

19. **性能与升级影响评估**
    - 通过标准：关键路径延迟和吞吐量有量化分析；Upgrade Impact 识别升级流程风险并对应 spec NFR 目标。
    - 触发问题：关键性能指标无量化、升级风险未识别。

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
- proposal.md 模板：`../../openspec-schema/schemas/spec-driven-enhanced/templates/proposal.md`
- spec 模板：`../../openspec-schema/schemas/spec-driven-enhanced/templates/spec.md`

**review_output_path**：`review.md`（change-dir，多视角合并到同一文件）

**评审维度与标准**（按此逐项评审；具体章节要求以 template 文件为准；**满足「通过标准」的维度不必提出问题，只在未满足时按问题分级标准记录问题**）：

**问题分级标准**：
- **CRITICAL**：事实错误、与上游文档直接矛盾、无法通过实现弥补的根本缺陷、违反安全/合规约束。
- **HIGH**：缺少关键信息或分析不足，显著影响质量。
- **MEDIUM**：表述可更清晰、边界可更完整。
- **LOW**：格式、拼写、minor 文案。

**Proposal 质量**
- **动机合理性**
  - 通过标准：Why 清晰说明问题根因、业务价值、影响范围；核心假设有数据或现状支撑。
  - 触发问题：问题根因缺失、业务价值无法追溯、影响范围未定义。
- **方案合理性**
  - 通过标准：Capabilities 从外部视角定义，只描述 **what**（外部可见行为），不描述 **how**（实现方案、技术选型、内部架构）；可独立验收；Acceptance Criteria 可验证；考虑过替代方案。
  - 触发问题：Capabilities 为内部实现动作、包含研发视角的技术方案或架构细节、Acceptance Criteria 不可验证、完全无替代方案分析。

**Specs 质量**
- **需求合理性与必要性**
  - 通过标准：每条 Requirement 合理、必要、不矛盾，能追溯到 proposal 的 Capability。
  - 触发问题：Requirement 与 Capability 无法对应、明显过度/遗漏核心需求、需求间矛盾。
- **需求完整性与边界**
  - 通过标准：Requirement 集合覆盖问题域，边界明确（不做什么 + 理由）。
  - 触发问题：核心场景缺失、边界未说明导致范围失控。
- **需求清晰性与可验收性**
  - 通过标准：每条 Requirement 从用户/调用方视角清晰无歧义，只描述 **what**（外部可见行为与预期结果），不描述 **how**（内部实现步骤）、可独立验收；Scenario 使用 WHEN/THEN 表达可验证预期。
  - 触发问题：Requirement 描述内部实现动作而非外部可见行为、无法验收、Scenario 缺少 THEN 或预期结果模糊。
- **异常路径与非功能需求**
  - 通过标准：异常路径从业务语义出发；NFR 指标可量化、可验证并落地到 Requirement。
  - 触发问题：核心异常路径缺失、NFR 指标不可量化或与 Requirement 脱节。

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
- design.md 模板：`../../openspec-schema/schemas/spec-driven-enhanced/templates/design.md`

**review_output_path**：`review.md`（change-dir，多视角合并到同一文件）

**评审维度与标准**（按此逐项评审；具体章节要求以 template 文件为准；**满足「通过标准」的维度不必提出问题，只在未满足时按问题分级标准记录问题**）：

**问题分级标准**：
- **CRITICAL**：事实错误、与上游文档直接矛盾、无法通过实现弥补的根本缺陷、违反安全/合规约束。
- **HIGH**：缺少关键信息或分析不足，显著影响质量。
- **MEDIUM**：表述可更清晰、边界可更完整。
- **LOW**：格式、拼写、minor 文案。

**Design 质量**
- **方案可行性与合理性**
  - 通过标准：技术方案能满足 specs 的每条 Requirement；关键决策有 trade-off 分析。
  - 触发问题：技术方案无法满足 Requirement、关键决策无任何 trade-off。
- **方案竞争力**
  - 通过标准：对比业界标准或已知方案，在性能、可扩展性、成本等关键维度有说服力。
  - 触发问题：关键维度完全未与业界对比、明显劣于标准方案却无正当理由。
- **架构一致性**
  - 通过标准：不违反 docs/architecture/ 中的架构原则；如有偏差须显式说明原因。
  - 触发问题：违反已声明的架构原则且未说明原因。
- **设计内部一致性**
  - 通过标准：Decision 之间无矛盾，接口定义与实现方案匹配。
  - 触发问题：Decisions 相互矛盾、接口与实现不匹配。
- **可维护性与故障处理**
  - 通过标准：复杂度合理、不过度工程化；关键路径的失败模式、降级策略、恢复机制充分。
  - 触发问题：关键路径无失败模式分析、无降级策略、复杂度明显过度。
- **决策备选方案**
  - 通过标准：有选择空间的决策有备选方案和 trade-off 分析。
  - 触发问题：重大决策无备选方案、无选择理由。
- **性能与升级影响评估**
  - 通过标准：关键路径延迟和吞吐量有量化分析；Upgrade Impact 识别升级流程风险并对应 spec NFR 目标。
  - 触发问题：关键性能指标无量化、升级风险未识别。

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
- proposal.md 模板：`../../openspec-schema/schemas/spec-driven-enhanced/templates/proposal.md`
- spec 模板：`../../openspec-schema/schemas/spec-driven-enhanced/templates/spec.md`
- design.md 模板：`../../openspec-schema/schemas/spec-driven-enhanced/templates/design.md`

**review_output_path**：`review.md`（change-dir，多视角合并到同一文件）

**评审维度与标准**（按此逐项评审；具体章节要求以 template 文件为准；第 2-5 项需至少两个文档存在时才可检查；**满足「通过标准」的维度不必提出问题，只在未满足时按问题分级标准记录问题**）：

**问题分级标准**：
- **CRITICAL**：事实错误、与上游文档直接矛盾、无法通过实现弥补的根本缺陷、违反安全/合规约束。
- **HIGH**：缺少关键信息或分析不足，显著影响质量。
- **MEDIUM**：表述可更清晰、术语可更统一。
- **LOW**：格式、拼写、minor 文案。

1. **模板符合性**
   - 通过标准：proposal/specs/design 分别遵循对应模板的章节结构、必填项和自检清单；缺失章节有合理说明或标注 N/A。
   - 触发问题：关键必填项缺失、章节顺序严重错乱、未按模板自检清单执行。
2. **内部一致性**
   - 通过标准：Capability、Requirement、Design/Decisions 之间无矛盾；Interface Changes 覆盖 proposal Impact 中识别的接口/协议/数据格式影响方向；Risks / Upgrade Impact 覆盖 specs 中 NFR 的关键风险。
   - 触发问题：同一 Requirement 在 design 中未被覆盖、Impact 与 Interface Changes 范围矛盾、NFR 风险无对应处理。
3. **同一外部行为一致性**
   - 通过标准：同一 Capability / Requirement 对应的外部可见行为在三类文档中的描述一致（正常路径、异常路径、边界条件）。
   - 触发问题：正常/异常/边界行为在不同文档中描述冲突或遗漏。
4. **范围一致性**
   - 通过标准：proposal 的 Capabilities / What Changes / Impact 所表达的范围在 specs 和 design 中得到尊重；design 的 Goals / Non-Goals 与 proposal 的范围一致。
   - 触发问题：design 引入 proposal 未声明的范围、specs 遗漏 proposal 明确承诺的能力。
5. **跨文档叙事连贯性**
   - 通过标准：三类文档组合起来形成清晰、可读的变更故事线；专有名词、术语一致。
   - 触发问题：术语前后不一致、叙事断裂到无法判断变更目的。
6. **写作质量与外部视角**
   - 通过标准：从外部调用方/用户视角描述可见行为；proposal/spec 只承载 **why** 和 **what**，design 承载 **how**；术语准确、长句可理解；文字本身能独立表达方案。
   - 触发问题：proposal/spec 中出现研发视角的内部架构、数据结构、算法、接口实现等 how 细节；关键段落歧义到影响理解、术语错误导致误解。

**输出**：
问题清单（CRITICAL / HIGH / MEDIUM / LOW），每个问题标注 Location（文件:章节）。
```

---

## autofix 修复 agent Prompt 模板

### product agent（autofix 修复 proposal + specs）

```
当前是 review 的 autofix 阶段，负责根据本轮 review.md 中的问题清单修复 proposal.md 和 specs/**/*.md。

**任务**：按优先级 CRITICAL → HIGH → MEDIUM → LOW 修复属于你负责文件的问题，LOW 问题可视修复成本跳过。

**负责修复的文件**：
- proposal.md：<路径>（如存在）
- specs/**/*.md：<路径列表>（如存在）

**参考输入**：
- review.md：<路径>（读取其中 Location 落在上述文件的问题）
- proposal.md 模板：`../../openspec-schema/schemas/spec-driven-enhanced/templates/proposal.md`
- spec 模板：`../../openspec-schema/schemas/spec-driven-enhanced/templates/spec.md`

**修复范围**：
1. **按优先级修复**：本轮 review.md 中 Location 落在负责文件的问题，按 CRITICAL → HIGH → MEDIUM → LOW 顺序处理
2. **LOW 问题**：格式、拼写、minor 文案等 LOW 问题可视修复成本跳过
3. **信息不足时保留**：因信息不足无法修复的问题，在修改摘要中列出并说明原因

**修复规则**：
1. 只修改 Location 落在 proposal.md 或 specs/**/*.md 的问题
2. 修复时必须保持对应模板的章节结构和必填项
3. 禁止为修复一个问题而破坏其他已通过评审的维度
4. 禁止重写无关章节；优先使用 Edit 做局部修改
5. 若某个问题因信息不足无法修复，在修改摘要中说明并标记为残留风险

**输出**：
1. 直接修改原文件（proposal.md / specs/**/*.md）
2. 修改摘要：修复了哪些问题（含原分级）、修改了哪些文件、未修复的问题及原因、残留风险。摘要须清晰说明哪些 Requirement / Capability / Scenario 的语义发生了变化，供后续 `architect` agent 同步 design 时参考。
```

### architect agent（autofix 修复 design）

```
当前是 review 的 autofix 阶段，负责根据本轮 review.md 中的问题清单修复 design.md。

**任务**：按优先级 CRITICAL → HIGH → MEDIUM → LOW 修复属于 design.md 的问题；LOW 问题可视修复成本跳过。

**负责修复的文件**：
- design.md：<路径>（如存在）

**参考输入**：
- review.md：<路径>（读取其中 Location 落在 design.md 的问题）
- 同轮次 `product` 修改摘要：<product 本轮修改摘要>（修复前读取，评估 proposal/specs 的语义变化是否要求 design 同步调整）
- 上游文档（按需读取，确保修复后仍然覆盖 specs 的 Requirement）：
  - proposal.md：<路径>
  - specs/**/*.md：<路径列表>
- design.md 模板：`../../openspec-schema/schemas/spec-driven-enhanced/templates/design.md`

**修复范围**：
1. **按优先级修复**：本轮 review.md 中 Location 落在 design.md 的问题，按 CRITICAL → HIGH → MEDIUM → LOW 顺序处理
2. **同步上游变化**：读取 `product` 本轮修改摘要后，若 Requirement / Capability / Scenario 语义发生变化，必须同步调整 design.md 中的对应 Decision / 接口 / 范围 / 术语表述
3. **LOW 问题**：格式、拼写、minor 文案等 LOW 问题可视修复成本跳过
4. **信息不足时保留**：因信息不足无法修复的问题，在修改摘要中列出并说明原因

**修复规则**：
1. 只修改 Location 落在 design.md 的问题
2. 修复时必须保持 design.md 模板的章节结构和必填项
3. 禁止为修复一个问题而破坏其他已通过评审的维度
4. 禁止重写无关章节；优先使用 Edit 做局部修改
5. 若某个问题因信息不足无法修复，在修改摘要中说明并标记为残留风险

**输出**：
1. 直接修改原文件（design.md）
2. 修改摘要：修复了哪些问题（含原分级）、修改了哪些文件、未修复的问题及原因、残留风险。摘要须清晰说明是否因同步 `product` 修改而调整了 design 中的对应表述。
```

---

## 与其他 skill 的协作

- **上游**：proposal.md + specs/**/*.md + design.md（由 feature-research / feature-define / feature-design 生成）
- **下游**：tasks.md（由主人基于 review.md 的 Tech Leader 决策生成，决策为 PASS 或 PASS WITH CONDITIONS 时才允许进入实现阶段）
- **并行**：无（review 是 tasks 的前置依赖）
