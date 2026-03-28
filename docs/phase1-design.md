# Phase 1 设计文档：基础设施 — OpenSpec 集成 + 特性级 Schema

## 目标

安装 OpenSpec，创建 `spec-driven-enhanced` 自定义 schema，在默认 `spec-driven` 基础上新增 `review` artifact、增强 `tasks` 模板支持 TDD 粒度任务分解，并为每个 artifact 设计面向 C 语言 / 分布式存储场景的质量 instruction，提升各环节输出质量。

## 前置依赖

无。Phase 1 是整个体系的起点。

---

## 交付物设计

### 1.1 安装 OpenSpec

**做法**：项目本地安装，避免全局污染。

```bash
npm install openspec    # 项目级依赖
```

### 1.2 spec-driven-enhanced schema 定义

**文件**：`openspec/schemas/spec-driven-enhanced/schema.yaml`

**设计思路**：Fork 默认 `spec-driven` schema，做两处关键扩展：

1. **新增 `review` artifact** — 在 `design` 之后、`tasks` 之前插入评审环节，解决 P6（缺少文档评审能力）
2. **增强 `tasks` 的 instruction** — 注入 TDD 和并行开发要求，解决 P2（输出质量不足）

依赖链变为：

```
            ┌→ specs ───┐
proposal ──┤            ├→ review → tasks → apply
            └→ design ──┘
```

schema.yaml 核心结构：

```yaml
name: spec-driven-enhanced
version: 1
description: 增强版规范驱动工作流 — 新增评审环节 + TDD 粒度任务分解

artifacts:
  - id: proposal
    generates: proposal.md
    template: proposal.md
    instruction: |
      # 见 1.3 节 instruction 设计
    requires: []

  - id: specs
    generates: "specs/**/*.md"
    template: spec.md
    instruction: |
      # 见 1.4 节 instruction 设计
    requires: [proposal]

  - id: design
    generates: design.md
    template: design.md
    instruction: |
      # 见 1.5 节 instruction 设计
    requires: [proposal]

  - id: review          # 新增：设计评审
    generates: review.md
    template: review.md
    instruction: |
      # 见 1.6 节 instruction 设计
    requires: [specs, design]

  - id: tasks
    generates: tasks.md
    template: tasks.md
    instruction: |
      # 见 1.7 节 instruction 设计
    requires: [review]   # 评审通过后才生成任务

apply:
  requires: [tasks]
  tracks: tasks.md
  instruction: |
    读取前序 artifact（proposal.md、specs/*.md、design.md、review.md）了解需求和设计方案。
    按 tasks.md 中的任务清单执行，尊重并行标记：independent 任务可并行调度，
    depends-on 任务按依赖顺序串行。完成后标记 checkbox。
    遇到阻塞或需要澄清时暂停并报告。
```

**为什么 review 在 tasks 之前？** 评审应发生在设计定稿之后、任务分解之前。先审后拆，避免基于有缺陷的设计生成任务清单。

### 1.3 proposal 模板

**文件**：`openspec/schemas/spec-driven-enhanced/templates/proposal.md`

**模板结构**：在默认模板基础上增加"产品级追溯"部分：

```markdown
## 产品级追溯

- 所属迭代计划：<!-- 关联 docs/iteration-plan.md 中的具体条目 -->
- 关联需求文档：<!-- 关联 docs/requirements/ 下的具体文件 -->
```

其余部分（Why / What Changes / Capabilities / Impact）保持默认。

> **设计决策**：不在 proposal 中声明涉及的子系统代码仓。跨子系统的协调是产品级 plan 的职责，接口变更在 design 模板中声明（见 1.5 节）。proposal 聚焦于当前子代码仓的特性范围。

**instruction 设计**（schema.yaml 中 proposal artifact 的 instruction 字段）：

> 自定义 instruction 完全替换默认值，因此必须包含默认 instruction 中的关键机制。

```yaml
instruction: |
  创建 proposal 文档，确立本次变更的动机和范围。

  ## 各部分要求

  **Why**：
  - 1-2 句话说明问题或机会。分析根因，而非描述表面现象
  - 量化影响：用数据说明严重程度（如性能下降百分比、故障频率）
  - 如果无法量化，说明定性影响和不解决的后果

  **What Changes**：
  - 变更清单，具体说明新增、修改或移除的能力
  - 破坏性变更标记 **BREAKING**

  **Capabilities**（关键：这是 proposal 与 specs 之间的契约）：
  - **New Capabilities**：新增能力列表。每个 Capability 生成 `specs/<name>/spec.md`，
    使用 kebab-case 命名（如 `range-query`、`fault-recovery`）
  - **Modified Capabilities**：已有能力的行为变更（非纯实现优化）。
    使用 `openspec/specs/` 中的已有 spec 名称。无需求变更则留空
  - 填写前先研究已有 specs，避免重复或遗漏
  - 每个 Capability 必须描述可验证的行为变化，而非实现细节
  - 粒度把控：一个 Capability 对应一个可独立验证的功能单元

  **产品级追溯**：
  - 有对应产品级文档时，关联 docs/iteration-plan.md 条目和 docs/requirements/ 需求文档
  - 无对应产品级文档时（如 bugfix、重构、技术债务清理），填写"不适用"并在 Why 部分
    充分说明变更动机，不阻塞流程

  **Impact**：列出受影响的代码、API、依赖和系统。

  保持简洁（1-2 页）。聚焦"为什么"而非"怎么做"——实现细节属于 design.md。
  proposal 是整个流程的基石，specs、design、tasks 都建立在此基础上。

  ## 反模式检查
  - 🚩 Why 只说"需要这个功能"而没有解释为什么需要
  - 🚩 Capability 描述的是实现方案（如"使用 B+ 树索引"）而非行为（如"支持范围查询"）
  - 🚩 产品级追溯留空（应填写关联文档或"不适用 + 原因"）
```

### 1.4 spec 模板

**文件**：`openspec/schemas/spec-driven-enhanced/templates/spec.md`

**模板结构**：在默认 Delta 规范格式基础上增加需求追溯字段：

```markdown
### Requirement: <!-- 需求名称 -->

**追溯**：`docs/requirements/<文件>#<条目>` 或 `不适用：<原因>`

<!-- 需求正文，必须包含 SHALL 或 MUST -->

#### Scenario: <!-- 场景名称 -->
- **WHEN** <!-- 条件 -->
- **THEN** <!-- 预期结果 -->
```

**instruction 设计**（schema.yaml 中 specs artifact 的 instruction 字段）：

> 自定义 instruction 完全替换默认值，因此必须包含 Delta 规范格式、heading 层级等 OpenSpec 核心机制。

```yaml
instruction: |
  创建规范文件，定义系统应该做什么（WHAT），而非怎么做（HOW）。

  ## 文件组织

  按 proposal 的 Capabilities 部分，每个 Capability 一个 spec 文件：
  - New capabilities：使用 proposal 中的 kebab-case 名称（specs/<capability>/spec.md）
  - Modified capabilities：使用 openspec/specs/<capability>/ 中的已有名称

  ## Delta 规范格式（使用 ## headers）

  - **ADDED Requirements**：新增能力
  - **MODIFIED Requirements**：行为变更——MUST 包含完整更新内容
  - **REMOVED Requirements**：废弃功能——MUST 包含 **Reason** 和 **Migration**
  - **RENAMED Requirements**：仅改名——使用 FROM:/TO: 格式

  MODIFIED 工作流：
  1. 在 openspec/specs/<capability>/spec.md 中定位已有 Requirement
  2. 复制 ENTIRE requirement block（从 `### Requirement:` 到所有 Scenario）
  3. 粘贴到 `## MODIFIED Requirements` 下并修改
  4. 确保 header 文本精确匹配（不区分空白）
  常见陷阱：MODIFIED 只写部分内容会导致 archive 时丢失细节。
  如果是新增关注点而非改变已有行为，用 ADDED 而非 MODIFIED。

  ## Requirement 格式

  - 每条：`### Requirement: <name>` + 描述
  - 使用 SHALL/MUST 表达规范性要求（禁止 should/may/可以/建议）
  - 每条 Scenario：`#### Scenario: <name>` + WHEN/THEN
  - **CRITICAL**：Scenario 必须使用 4 个 hashtag（`####`），3 个 hashtag 或 bullet 会静默失败
  - 每条 Requirement 至少一个 Scenario
  - 每条 Requirement 必须填写追溯字段：有对应产品级需求时关联 docs/requirements/ 下的具体条目，无对应需求时（如 bugfix、重构、技术债务清理）填写"不适用"并说明原因

  ## 质量要求

  **Requirement 编写**：
  - 必须可测试：读完能明确判断"通过"还是"不通过"
  - 一条 Requirement 只描述一个行为。用"和"连接了两个行为则拆成两条
  - 描述可观测的外部行为，不涉及内部实现

  **Scenario 编写**：
  - 每条 Requirement 至少一个正常路径 + 一个异常路径 Scenario
  - WHEN 描述具体的前置状态和触发动作（如"当并发连接数超过 1000"而非"当系统负载较高"）
  - THEN 描述可验证的预期结果（如"返回错误码 ENOMEM"而非"返回错误"）
  - 异常路径应聚焦业务语义层面，从需求本身的业务逻辑出发思考可能的失败场景和预期反馈（如权限不足、配额超限、前置条件不满足、冲突等），而非罗列通用的系统级异常（内存/网络/并发等实现细节留给 design 阶段处理）

  ## 反模式检查
  - 🚩 Requirement 使用了"应该"/"建议"等非强制性词汇
  - 🚩 Requirement 描述了实现方式而非行为
  - 🚩 Scenario 只有正常路径，没有异常路径
  - 🚩 THEN 的预期结果不可判断（如"系统正常工作"）
  - 🚩 追溯字段为空（应填写关联需求或"不适用 + 原因"）
```

### 1.5 design 模板

**文件**：`openspec/schemas/spec-driven-enhanced/templates/design.md`

**模板结构**：在默认模板基础上增加架构追溯和接口变更：

```markdown
## 架构追溯

- 关联架构文档：<!-- docs/architecture/ 下的具体文件 -->

## 接口变更

<!-- 如涉及跨子系统接口，列出变更的接口定义及影响 -->
```

其余部分（Context / Goals / Non-Goals / Decisions / Risks）保持默认。

**instruction 设计**（schema.yaml 中 design artifact 的 instruction 字段）：

> 自定义 instruction 完全替换默认值，因此必须包含默认的章节结构和创建条件。

```yaml
instruction: |
  创建设计文档，说明如何（HOW）实现 specs 中定义的需求。

  ## 各部分要求

  - **Context**：背景、现状、约束、利益相关方
  - **Goals / Non-Goals**：本设计要达成什么、明确排除什么
  - **Decisions**：关键技术选择及理由（为什么选 X 而非 Y？），每个决策列出备选方案
  - **Risks / Trade-offs**：已知风险和权衡。格式：[风险] → [缓解措施] → [残余风险]
  - **Migration Plan**：部署步骤、回滚策略（如适用）
  - **Open Questions**：待解决的决策或未知项
  - **架构追溯**：关联 docs/architecture/ 下的具体文档
  - **接口变更**：涉及跨子系统接口时列出变更定义及影响

  聚焦架构和方案，而非逐行实现。引用 proposal 了解动机，引用 specs 了解需求。

  ## 质量要求

  **Decisions（核心）**：
  - 每个技术决策必须列出至少 2 个备选方案，并逐项比较 trade-off
  - 比较维度至少包含：复杂度、性能影响、可维护性、与现有代码的一致性
  - 明确写出"选择 X 因为 Y"，而非只列出方案不给结论
  - 决策应聚焦架构层面的方案选择（如数据结构/算法选型、一致性模型、模块交互方式、性能与可靠性权衡等），而非 C 语言编码细节（内存管理、锁实现等留给代码级阶段处理）

  **Risks / Trade-offs**：
  - 每个 Risk 必须有对应的 Mitigation，不能只列风险不给方案

  **架构追溯**：
  - 有对应架构文档时关联 docs/architecture/ 下的具体文件，无对应文档时（如新领域、局部优化等）填写"不适用"并说明原因
  - 设计方案不得与产品级架构决策矛盾，如有偏差须显式标注并说明原因

  **接口变更**：
  - 涉及跨子系统接口时，列出变更的函数签名、数据结构、协议格式
  - 标注兼容性：向前兼容 / 向后兼容 / 破坏性变更

  ## 反模式检查
  - 🚩 只有一个方案没有备选（除非真的只有一条路，须说明原因）
  - 🚩 Decisions 没有 trade-off 分析，只说"使用 X"
  - 🚩 Risk 没有 Mitigation
  - 🚩 架构追溯为空（应填写关联文档或"不适用 + 原因"）
```

### 1.6 review 模板（新增 artifact）

**文件**：`openspec/schemas/spec-driven-enhanced/templates/review.md`

**模板结构**：

```markdown
## 评审对象

- Proposal：<!-- 文件路径 -->
- Specs：<!-- 文件路径列表 -->
- Design：<!-- 文件路径 -->

## 评审清单

### 产品级一致性
- [ ] proposal/specs/design 与产品级文档（docs/requirements/、docs/architecture/、docs/interfaces/）无矛盾
- [ ] 涉及的需求追溯链完整（产品级需求 → proposal → specs → design）

### 需求质量（specs）
- [ ] 每条 Requirement 清晰无歧义，可独立验收
- [ ] Requirement 整体能完整支撑 proposal 的目的（无遗漏、无超出）
- [ ] 每条 Requirement 至少有正常路径和异常路径 Scenario

### 设计质量（design）
- [ ] 方案设计合理可行，技术决策不与 specs 矛盾
- [ ] 不违反产品级架构设计原则
- [ ] 方案具备竞争力（性能、可扩展性、可维护性等关键维度有说服力）
- [ ] 所有跨子系统接口变更已声明

## 评审结论

- **决策**：<!-- PASS / PASS WITH CONDITIONS / REJECT —— 由评审人填写 -->
- **决策人**：<!-- 评审人姓名 -->
- **决策理由**：<!-- 简要说明 -->
- **遗留问题**：<!-- 需在 tasks 阶段解决的问题 -->
```

**为什么需要这个 artifact？** 默认 schema 从 design 直接到 tasks，没有质量关卡。review 在任务分解前做一次结构化检查，提前拦截设计缺陷。

**instruction 设计**（schema.yaml 中 review artifact 的 instruction 字段）：

```yaml
instruction: |
  对 proposal、specs、design 三个文档进行结构化评审，同时检查与产品级文档的一致性，生成评审报告。

  ## 评审方法

  **不是机械打勾**。对每个检查项，必须：
  1. 实际对照文档内容逐项验证
  2. 通过则打勾并简要说明验证依据
  3. 未通过则标注问题，引用具体文档位置和内容

  **产品级一致性检查**：
  - 对照 docs/requirements/、docs/architecture/、docs/interfaces/ 等产品级文档
  - 检查 proposal/specs/design 是否与产品级文档存在矛盾或偏离
  - 验证需求追溯链完整：产品级需求 → proposal Capability → specs Requirement → design Decision

  **需求质量评审（specs）**：
  - 每条 Requirement 是否清晰无歧义——读完能明确判断"通过"还是"不通过"
  - 每条 Requirement 是否可独立验收——不依赖其他 Requirement 的上下文就能理解和测试
  - Requirement 整体是否完整支撑 proposal 的目的——遍历 proposal 的每个 Capability，确认 specs 中无遗漏、无超出
  - 每条 Requirement 的异常路径 Scenario 是否从业务语义出发（如权限、配额、冲突等）

  **设计质量评审（design）**：
  - 方案是否合理可行——技术决策是否与 specs 的 Requirement 一致，有无矛盾
  - 是否违反架构设计原则——对照 docs/architecture/ 检查，如有偏差须显式说明原因
  - 方案是否具备竞争力——在性能、可扩展性、可维护性等关键维度是否有说服力，备选方案的 trade-off 分析是否充分

  **评审结论**：
  - AI 输出评审报告（问题清单、风险项）并给出建议结论（PASS / PASS WITH CONDITIONS / REJECT）
  - 最终决策权归评审人，评审人可修改 AI 的建议结论
  - AI 的结论不阻塞流程——即使 AI 建议 REJECT，评审人仍可决定放行进入下一步
```

### 1.7 tasks 模板（TDD 粒度增强）

**文件**：`openspec/schemas/spec-driven-enhanced/templates/tasks.md`

**模板结构**：

```markdown
## N. <!-- 任务组名称 -->

**并行标记**：<!-- independent / depends-on:X.Y -->

- [ ] N.1 <!-- 任务描述 -->
  - [ ] N.1.1 RED：编写失败测试 — <!-- 测试文件路径和测试意图 -->
  - [ ] N.1.2 GREEN：最小实现通过测试
  - [ ] N.1.3 REFACTOR：重构简化
- [ ] N.2 <!-- 任务描述 -->
  - [ ] N.2.1 RED：...
  - [ ] N.2.2 GREEN：...
  - [ ] N.2.3 REFACTOR：...
```

**instruction 设计**（schema.yaml 中 tasks artifact 的 instruction 字段）：

> 自定义 instruction 完全替换默认值，因此必须包含 checkbox 格式要求（apply phase 依赖此格式解析进度）。

```yaml
instruction: |
  将 specs 和 design 分解为可执行的任务清单。
  引用 specs 了解要实现什么，引用 design 了解如何实现。

  ## 格式要求（IMPORTANT：apply phase 依赖此格式跟踪进度）

  - 相关任务按 ## 编号分组
  - 每个任务必须是 checkbox：`- [ ] X.Y 任务描述`
  - 未使用 `- [ ]` 的任务不会被 apply phase 跟踪
  - 按依赖顺序排列（先做的排前面）
  - 每个任务必须可验证——完成时能明确判断"做完了"

  ## 任务粒度

  每个任务必须是"比特大小"（bite-sized）——一个 Agent 在一次会话中可完成：
  - 任务描述必须具体到文件路径和函数名，禁止模糊描述（如"实现数据处理"）
  - RED 步骤必须写明测试文件路径、测试函数名、测试意图
  - GREEN 步骤必须写明要修改的源文件路径
  - 如果一个任务需要修改超过 3 个文件，说明粒度太大，应继续拆分

  ## TDD 三步骤

  每个实现任务强制拆为：
  1. RED：编写一个会失败的测试。测试应直接验证 specs 中对应 Scenario 的 WHEN/THEN
  2. GREEN：编写最小实现让测试通过。不追求完美，只追求通过
  3. REFACTOR：在测试保护下重构——消除重复、改善命名、简化结构

  **无测试不实现**：如果一个任务不写测试（如纯配置变更、文档更新），不需要 TDD 三步骤，
  但必须说明为什么不需要测试。

  ## Mock 纪律

  - 子系统内部模块之间禁止 mock，测试必须走真实的内部调用链
  - 只允许 mock 子系统外部边界（外部 RPC、外部服务依赖、外部存储介质模拟）
  - 每个 mock 必须注释说明：mock 了什么、为什么必须 mock、mock 行为与真实行为的差异
  - 🚩 如果发现需要 mock 内部模块才能写测试，说明模块耦合过紧，应先重构解耦

  ## 并行标记

  - 修改不同文件的任务标记为 independent
  - 修改同一文件的任务标记为 depends-on:X.Y
  - 有数据依赖（如任务 B 的测试数据由任务 A 的代码生成）也标记为 depends-on
  - 同一个任务组内的任务默认串行，跨任务组默认可并行

  ## 反模式检查
  - 🚩 任务描述无具体文件路径（如"实现存储模块"）
  - 🚩 RED 步骤没有写明测试文件路径和测试意图
  - 🚩 任务粒度过大（修改超过 3 个文件、实现超过 200 行代码）
  - 🚩 所有任务都标记为 depends-on 导致完全串行（应重新审视是否可以拆出独立任务）
  - 🚩 specs 中的某个 Requirement/Scenario 在 tasks 中没有对应任务
```

### 1.8 config.yaml 模板

**文件**：`openspec/config.yaml.template`

**设计思路**：提供团队统一的 OpenSpec 配置模板，各子系统代码仓复制后按需修改。`schema: spec-driven-enhanced` 设为默认，`/opsx:propose` 时无需指定 `--schema` 参数：

```yaml
schema: spec-driven-enhanced

context: |
  语言：C
  构建系统：make / cmake
  平台：Linux
  领域：分布式存储
  编码规范：参见 .claude/rules/coding-style.md
  测试框架：<!-- 子系统指定 -->

rules:
  proposal:
    - 有对应产品级文档时须关联 iteration-plan 条目，无则填写"不适用"并说明动机
  specs:
    - 每个 Requirement 必须包含 SHALL 或 MUST
  design:
    - 涉及跨子系统接口时必须列出接口变更
    - 涉及并发或分布式一致性时，须声明并发模型、一致性保证和故障语义
  review:
    - 评审未通过不得生成 tasks
  tasks:
    - 每个任务必须包含 TDD 三步骤（RED/GREEN/REFACTOR）
    - 可并行任务必须标注 independent
    - 禁止随意 mock：子系统内部禁止 mock，只允许 mock 外部边界，每个 mock 必须注释理由
```

---

## 验证计划

1. `openspec schema validate spec-driven-enhanced` — 验证 schema 合法
2. 在 teamskills 仓库执行 `/opsx:propose test-change`，然后 `/opsx:continue` 逐步推进，验证 5 个 artifact（proposal → specs → design → review → tasks）均可正常生成
3. 检查 review artifact 的依赖关系正确触发（必须在 specs 和 design 之后）
4. 检查 tasks 输出包含 TDD 子步骤结构
5. **instruction 质量验证**：检查各 artifact 输出是否符合 instruction 中的质量要求：
   - proposal：Why 是否分析了根因、Capability 是否描述行为而非实现、产品级追溯是否非空
   - specs：Requirement 是否使用 SHALL/MUST、是否同时有正常和异常 Scenario、THEN 是否可判断
   - design：Decisions 是否列出备选方案和 trade-off、Risk 是否有 Mitigation、架构追溯是否非空
   - review：是否逐项对照验证（而非机械打勾）、评审结论是否有依据
   - tasks：是否有具体文件路径、粒度是否足够小、mock 使用是否合规
