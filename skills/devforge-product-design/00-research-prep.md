# 第 0 阶段：前置调研与定位确认

**准入条件**：无
**产出文件**：`.claude/domain-config.yaml`

> **豁免说明**：第 0 阶段为交互式信息收集，豁免完整多 agent 评审修正循环，但需通过准入检查清单确认信息充分性。

---

## 核心原则

不调研清楚背景和约束就开始标杆研究，标杆选择可能偏离方向。通过**交互式提问**逐层深入，禁止一次性抛出所有问题。

> **两 skill 协作**：/df:product-define 和 /df:product-design 共用 T1-T6 主题清单。define 主导 T1-T5，design 主导 T6，双方互相校验。场景 B 时 design 跳过已闭合的 T1-T5，执行 T6 并从架构视角校验。

---

## 步骤 1：检查 domain-config.yaml

交互式前置调研由**主会话直接执行**，不派遣 agent。主会话首先检查 `.claude/domain-config.yaml` 是否存在：

**场景 A：文件不存在**（首次执行，/df:product-define 未执行）
- 执行完整的领域信息收集（所有主题）
- 最终由主会话生成新的 domain-config.yaml

**场景 B：文件已存在**（/df:product-define 已执行过）
- 主会话读取现有配置，向用户展示
- 询问："这些信息是否仍然准确？架构视角下是否有需要调整的？"
- 如果准确：跳过已有字段对应的主题，只收集 design 负责的 T6
- 如果需要修正：逐项确认需要修改的字段

**场景 C：文件已存在**（/df:product-design 先前已执行过）
- 读取现有配置，向用户展示
- 从架构视角校验已填的 T1-T6：
  - T1-T5：目标用户是否准确？痛点表述是否到位？规模量级是否合理？边界是否完整？
  - T6：targets 量化目标是否反映了真实业务需求？数字是否合理？
  - 校验动作：评估 targets 与 T4 priorities 的自洽性（如 consistency 优先级低但 targets 要求 strong，矛盾）
- 询问："这些信息从架构视角看是否仍然准确？是否有需要调整或补充的？"
- 如果准确：跳过步骤 2 中已有字段的提问
- 如果需要修正：逐项确认需要修改的字段

---

## 步骤 2：前置调研信息收集（主题驱动对话）

> **执行原则**：主会话围绕主题清单与用户进行交互式对话，**对话顺序、问法、追问深度由主会话动态决定**。文档不预写问题脚本，仅约束「必须收敛到的目标」和「下游依赖的锚点枚举」。

### 2.0 主题清单

围绕"前置调研"必须逐个收敛的主题（顺序由主会话根据对话进展决定，可交错进行）：

| 编号 | 主题 | 闭合标志 | 锚点 | 下游用途 |
|------|------|---------|------|---------|
| T1 | 系统类型与定位 | primary_type 已落到枚举 + sub_type 视情况追问 | `primary_type`、`sub_type` 枚举 | 第 1 阶段标杆筛选、架构模式预选 |
| T2 | 目标用户与核心痛点 | 核心痛点收敛到一句话 + 主要用户类型已确认 | 自由文本（汇入 description） | 第 2 阶段 Actor 识别基线 |
| T3 | 系统规模的量级表征 | 部署/数据/并发三档位均已落到枚举；条件性的并发拆分按系统类型完成 | `deployment`、`data_scale`、`concurrency.peak`（+ 条件性拆分字段）枚举 | 第 1 阶段标杆筛选、/df:product-design 规模约束 |
| T4 | 质量属性优先级 | 5 项已排序 + 排序原因已说明 | `quality_attributes.priorities` 1-5 排序 | 标杆研究权重、架构权衡 |
| T5 | 明确的边界约束 | >=2 个"不做的事"已列出 | 自由文本（汇入 description） | 第 2 阶段 Feature 识别的禁区 |
| T6 | 质量属性量化目标 | 量化指标已明确（latency/throughput/SLA/consistency_model） | `quality_attributes.targets` | 第 2-3 阶段架构设计约束 |

### 2.1 锚点字段（最终值必须落到模板枚举）

下游分支决策依赖以下字段，主会话**必须**将收集到的信息收敛到受控枚举值写入 yaml，不接受自由文本：

- **T1**：`system.primary_type`（10 值枚举）；`system.sub_type` 为可选追问，主会话根据系统类型和对话上下文自行判断是否需要
- **T3**：`system.scale.deployment`（4 值枚举）、`system.scale.data_scale`（4 值枚举）、`system.scale.concurrency.peak`（5 值枚举）
- **T4**：`quality_attributes.priorities` 5 项（各填 1-5 整数，无重复）
- **T6**：`quality_attributes.targets.consistency_model`（3 值枚举：strong / eventual / causal）

**T3 条件性追问**：主会话根据 T1 系统类型判断是否追问 concurrency 拆分字段（如读写拆分、produce/consume、task_count 等）。具体字段-系统类型映射见模板 `templates/domain-config.yaml` 中各 concurrency 字段注释。

**工具约束**：`AskUserQuestion` 最多 4 个选项。当锚点取值数 > 4 时（如 `primary_type` 有 10 个值），主会话先通过开放式对话或粗分类将候选集缩至 <= 4 个，再用 `AskUserQuestion` 收口。**手段不限，但结果必须是模板枚举值。**

> **枚举值的单一信息源**：所有锚点字段的具体取值范围见 `templates/domain-config.yaml` 各字段注释。本 skill 不再列举枚举内容。

### 2.2 闭合度自检（出对话前主会话自检）

对话过程中主会话持续维护一份"主题闭合表"，每个主题有 3 种状态：未启动 / 进行中 / 已闭合。**所有主题进入"已闭合"才能进入步骤 3**。

**闭合判定标准**：
- T1：primary_type 已落到枚举值；sub_type 为可选，由主会话判断是否追问
- T2：用户已说出明确的核心痛点（不是"性能更好""体验更好"这种空话）+ 主要用户类型已确认
- T3：deployment / data_scale / concurrency.peak 均已落到枚举值；条件性拆分字段按 T1 类型规则补齐
- T4：5 项质量属性已排序（无并列、无遗漏）+ 用户给出了排序原因
- T5：>=2 个具体的"不做的事"已列出（不是"不做无关的事"这种空话）
- T6：量化目标已明确（至少 consistency_model 已落到枚举 + latency_p99 / throughput / availability_sla 有具体数值或范围）

**禁止行为**：
- 一次性把所有主题的问题列出来等用户回答
- 用预写脚本式提问（如"对每个场景问 X"），而不是根据用户已说的内容动态判断
- 没有触发追问就跳到下一主题（用户回答含糊时主会话有责任追问澄清）
- 在锚点字段上接受自由文本写入 yaml（如用户说"挺多并发"，主会话有责任引导其落到 `concurrency.peak` 的 5 档枚举值之一）

---

## 步骤 3：生成/更新 domain-config.yaml

主会话将 T1-T6 收集到的信息按 2.0 主题清单与 2.1 锚点字段定义的对应关系填入 `templates/domain-config.yaml` 模板：

- 锚点字段：直接填入对应枚举值（取值见模板字段注释）
- T2 + T5 自由文本：综合为 `system.description` 一段（不做结构化拆分）
- 条件性 concurrency 拆分字段：不属于当前系统类型的直接删除，不留空
- 场景 B/C：仅更新 design 负责的 T6 字段（保留 define 已生成字段）
- 场景 A：`metadata.created_at` 填当前日期，`metadata.contributors` 填 `["/df:product-design"]`
- 场景 B/C：`metadata.contributors` 追加 `"/df:product-design"`（如尚未包含），`metadata.last_updated` 填当前日期

写入 `.claude/domain-config.yaml`，用 `ls` 验证文件存在。

> **职责边界**：本文件由 /df:product-define 和 /df:product-design 共同维护。define 主导 T1-T5（`system` 全部 + `quality_attributes.priorities`），design 主导 T6（`quality_attributes.targets`）。`system` 和 `quality_attributes` 中 design 需要补充的字段由 design 更新，但不覆盖 define 已填充的值。实现细节（languages / architecture / tech_stack / development / benchmarks）不写入本文件，由 ADR 和后续阶段产出维护。

---

## 出口标准

### 准入检查清单

- [ ] **T1 闭合**：`primary_type` 已落到枚举值；`sub_type` 视情况追问
- [ ] **T2 闭合**：核心痛点已收敛为一句话描述（非空话）+ 主要用户类型已确认
- [ ] **T3 闭合**：`deployment` / `data_scale` / `concurrency.peak` 均已落到枚举值
- [ ] **T4 闭合**：`quality_attributes.priorities` 已排序
- [ ] **T5 闭合**：>=2 个明确的"不做的事"已列出（非空话）
- [ ] **T6 闭合**：量化目标已明确（consistency_model 已落到枚举 + 至少一项具体数值）
- [ ] **domain-config.yaml 已落盘**（用 `ls` 验证文件存在）

全部通过 -> 可进入第 1 阶段（标杆研究）。
