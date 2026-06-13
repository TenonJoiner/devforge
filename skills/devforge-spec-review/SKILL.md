---
name: devforge-spec-review
description: 文档评审 skill，单轮全维度扫描 + 人工决策门禁。评审 proposal/specs/design 三类文档，输出问题清单（CRITICAL/HIGH/MEDIUM/LOW）+ AI 建议决策。不做修复。用于特性级 workflow 的 review artifact 生成或手动临时体检。
allowed-tools: [Read, Write, Edit, Bash, Grep, Glob, Agent]
---

# devforge-spec-review — 文档评审

## 概述

文档评审是 design 完成后、实现前的质量体检 + 人工门槛。本 skill 产出 review.md，包含两部分：
1. **AI 评审报告**：单轮扫描，输出问题清单（按 CRITICAL/HIGH/MEDIUM/LOW 分级）+ AI 建议决策。**不做修复**
2. **Tech Leader 最终决策**：留空，等人工填写

**与 skill 内化评审的关系**：
- feature-research / feature-define / feature-design 三个 skill 内部已经做过深度评审循环（最多 3 轮自修），保证基础质量
- 本 skill 是「质量体检 + 人工门槛」：单轮扫描 23 项维度，发现问题不修复，输出清单交人决策

**核心原则**：
1. **单轮扫描**：不做修复循环，只输出问题清单
2. **23 项维度**：跨文档一致性（3 项）+ Proposal 质量（3 项）+ Specs 质量（8 项）+ Design 质量（12 项）
3. **人工门禁**：AI 建议仅供参考，最终决策权在 Tech Leader
4. **双模式触发**：workflow 自动触发 + 手动临时体检

---

## 工作目录约定

skill 在 **change-dir**（默认当前工作目录）查找输入文件、输出产出文件：
- **change-dir**：由 `--change-dir <path>` 参数指定，无参数时默认当前工作目录
- **输入**：`proposal.md`、`specs/*.md`、`design.md`
- **输出**：`review.md`
- **报告模板**：`templates/review.md`（review.md 格式模板）

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

读取以下输入（路径均相对于 change-dir）：
1. **proposal.md**：本特性的动机、范围、Capabilities
2. **specs/*.md**：Requirement + Scenario（Delta 格式）
3. **design.md**：Context + Goals/Non-Goals + Solution Overview + Architecture + Key Flows + Decisions + Interface Changes + Risks + Upgrade Impact + Open Questions
4. **产品级文档**（按需）：`docs/requirements/` 和 `docs/architecture/` 下相关文档
5. **review.md template**：`templates/review.md`

### [2] 并行评审

并行派遣 2 个 reviewer agent：
- **product-reviewer**：跨文档一致性（产品视角）+ Proposal 质量（3 项）+ Specs 质量（8 项）
- **architect-reviewer**：跨文档一致性（架构视角）+ Design 质量（12 项）

每个 reviewer 产出问题清单（CRITICAL / HIGH / MEDIUM / LOW）。

### [3] 汇总计分

主会话收集两个 agent 的评审结果，合并问题清单，去重后分别计算：
- proposal.md 的缺陷总分
- specs/ 中每个 spec 文件的缺陷总分
- design.md 的缺陷总分

**缺陷密度计算公式**：
```
单文档缺陷密度 = 该文档的问题分数之和 / 1
全局缺陷密度 = 所有文档的问题分数之和 / 文档总数
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

写入 review.md：
- **Review Scope**：proposal / specs / design 文件路径
- **AI Review Rounds**：问题清单表格（# / Severity / Location / Issue / Fix Applied）
- **Review Conclusion**：AI 建议决策 + 建议理由 + 遗留问题
- **Tech Leader 最终决策**：留空（等人工填写）

### [6] STOP

提示用户：review.md 已生成，请组织交叉评审并由 Tech Leader 在「人工评审决策」区域填写最终决策。

---

## 重新评审模式

删除现有 review.md，重新执行「初次评审」模式。

---

## 评审标准（23 项）

以下为评审的单一权威标准。

**跨文档一致性**（横切关注点，贯穿所有评审维度）：
- proposal/specs/design 三者是否一致——Capability、Requirement、Decision 之间无矛盾
- 与产品级文档（docs/requirements/、docs/architecture/）是否一致
- 追溯链完整：产品级需求 → proposal Capability → specs Requirement → design Decision

**Proposal 质量（3 项）**：
- **动机合理性**：Why 是否清晰说明了问题或机会，有根因分析而非表面描述；问题是否值得解决（业务价值、影响范围）
- **方案合理性**：提出的 Capabilities 是否是解决该问题的合理方案，有无更优替代方案未考虑
- **范围完整性**：Capabilities 是否完整覆盖变更范围，粒度是否合理

**Specs 质量（8 项）**：
- **需求合理性**：每条 Requirement 本身是否合理——不过度（镀金）、不遗漏（关键场景缺失）、不矛盾（需求间冲突）
- **需求必要性**：每条 Requirement 是否必要——能否追溯到 proposal 的 Capability 或产品级需求，无凭空增加的需求
- **需求完整性**：Requirement 集合是否完整覆盖问题域——不只是"支撑 proposal"，而是从领域视角审视是否有遗漏
- **需求清晰性**：每条 Requirement 是否清晰无歧义——读完能明确判断"通过"还是"不通过"
- **需求可验收性**：每条 Requirement 是否可独立验收——不依赖其他 Requirement 的上下文就能理解和测试
- **异常路径质量**：每条 Requirement 的异常路径 Scenario 是否从业务语义出发（如权限、配额、冲突等）
- **安全覆盖**：安全相关的行为是否有对应 Requirement 覆盖
- **非功能需求覆盖**：`## Non-Functional Requirements` 是否强制覆盖 Performance / Reliability / Compatibility / Observability / Upgrade Compatibility——不涉及项是否已显式标注原因，量化指标是否可验证

**Design 质量（12 项）**：
- **方案可行性**：技术方案是否可行——能否满足 specs 的每条 Requirement，有无技术风险未评估
- **方案竞争力**：方案是否具备竞争力——对比业界标准或已知方案，在性能、可扩展性、成本等关键维度是否有说服力
- **方案合理性**：技术决策是否合理——trade-off 权衡是否得当（不只是列出备选，而是选择合理）
- **架构一致性**：是否违反架构设计原则——对照 docs/architecture/ 检查，如有偏差须显式说明原因
- **设计内部一致性**：设计内部是否一致——Decision 之间无矛盾，接口定义与实现方案匹配
- **可维护性**：设计复杂度是否合理，是否过度工程化，是否便于后续演进
- **故障处理**：故障场景是否充分考虑——关键路径的失败模式、降级策略、恢复机制
- **决策备选方案**：有选择空间的决策是否有备选方案和 trade-off 分析
- **并发模型**：涉及并发交互的决策是否声明了并发模型（锁类型、粒度、获取顺序）
- **状态机表达**：涉及多状态组件是否有状态转换表
- **性能评估**：性能影响评估是否充分——关键路径延迟和吞吐量是否有量化分析
- **升级影响评估**：`## Upgrade Impact` 是否充分识别了对系统升级流程的风险，以及升级模块需要做什么工作

---

## Agent 派遣 Prompt 模板

### product-reviewer agent

```
当前是 review 阶段，评审 proposal/specs/design 三类文档。

**任务**：从产品视角评审。

**被评审对象**：
- proposal.md：<路径>
- specs/*.md：<路径列表>
- design.md：<路径>

**被评审 template 路径**（评审锚点来源 1：章节结构、必填项、自检清单）：
- proposal.md 模板：`templates/proposal.md`
- spec 模板：`templates/spec.md`
- design.md 模板：`templates/design.md`

**review_output_path**：`review.md`（change-dir，多视角合并到同一文件）
**report_template_path**：`templates/review-report.md`（如存在）
**复杂度档位**：复杂（≥7 个质疑点）

**评审维度**：
1. 模板符合性：proposal/specs/design 是否分别遵循对应模板的章节结构、必填项和自检清单
2. 跨文档一致性（产品视角）：Capability → Requirement 是否对齐、与 docs/requirements/ 的一致性、产品级追溯链
3. Proposal 质量（3 项）：动机合理性、方案合理性、范围完整性
4. Specs 质量（8 项）：需求合理性、必要性、完整性、清晰性、可验收性、异常路径质量、安全覆盖、非功能需求覆盖

**输出**：
问题清单（CRITICAL / HIGH / MEDIUM / LOW），每个问题标注 Location（文件:章节）。
```

### architect-reviewer agent

```
当前是 review 阶段，评审 proposal/specs/design 三类文档。

**任务**：从架构视角评审。

**被评审对象**：
- proposal.md：<路径>
- specs/*.md：<路径列表>
- design.md：<路径>

**被评审 template 路径**（评审锚点来源 1：章节结构、必填项、自检清单）：
- proposal.md 模板：`templates/proposal.md`
- spec 模板：`templates/spec.md`
- design.md 模板：`templates/design.md`

**review_output_path**：`review.md`（change-dir，多视角合并到同一文件）
**report_template_path**：`templates/review-report.md`（如存在）
**复杂度档位**：复杂（≥7 个质疑点）

**评审维度**：
1. 模板符合性：proposal/specs/design 是否分别遵循对应模板的章节结构、必填项和自检清单
2. 跨文档一致性（架构视角）：Requirement → Decision 是否对齐、与 docs/architecture/ 的一致性、架构追溯链
3. Design 质量（12 项）：方案可行性、方案竞争力、方案合理性、架构一致性、设计内部一致性、可维护性、故障处理、决策备选方案、并发模型、状态机表达、性能评估、升级影响评估

**输出**：
问题清单（CRITICAL / HIGH / MEDIUM / LOW），每个问题标注 Location（文件:章节）。
```

---

## 与其他 skill 的协作

- **上游**：proposal.md + specs/*.md + design.md（由 feature-research / feature-define / feature-design 生成）
- **下游**：tasks.md（由主人基于 review.md 的 Tech Leader 决策生成，决策为 PASS 或 PASS WITH CONDITIONS 时才允许进入实现阶段）
- **并行**：无（review 是 tasks 的前置依赖）
