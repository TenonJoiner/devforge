# 第 0 阶段：产品定位确认

**准入条件**：无
**产出文件**：`.claude/domain-config.yaml`

---

## 核心原则

在启动标杆研究之前，必须先完成轻量级产品定位确认。如果产品边界不清，标杆研究可能选错对象，导致后续全部返工。

**交互原则**：
- 通过交互式提问逐层深入理解产品定位，禁止一次性抛出所有问题
- 每个问题等待用户回答后再提出下一个问题
- 根据用户回答动态调整后续问题

---

## 执行方式

第 0 阶段为交互式产品定位确认，由**主会话直接执行**。

### 步骤 1：检查 domain-config.yaml

主会话首先检查 `.claude/domain-config.yaml` 是否存在：

**场景 A：文件不存在**（首次执行）
- 执行完整的领域信息收集（步骤 2）
- 生成新的 domain-config.yaml

**场景 B：文件已存在**（/df:design 或 /df:define 先前已执行过）
- 读取现有配置，向用户展示
- 询问："这些信息是否仍然准确？需求视角下是否有需要调整的？"
- 如果准确：跳过步骤 2 中已有字段的提问
- 如果需要修正：逐项确认需要修改的字段

### 步骤 2：产品定位信息收集（主题驱动对话）

> **执行原则**：主会话围绕主题清单与用户进行交互式对话，**对话顺序、问法、追问深度由主会话动态决定**。文档不预写问题脚本，仅约束「必须收敛到的目标」和「下游依赖的锚点枚举」。

#### 2.0 主题清单

围绕"产品定位"必须逐个收敛的主题（顺序由主会话根据对话进展决定，可交错进行）：

| 编号 | 主题 | 闭合标志 | 锚点 | 下游用途 |
|------|------|---------|------|---------|
| T1 | 系统在技术分类树上的定位 | primary_type 已落到枚举 + sub_type（如适用） | `primary_type`、`sub_type` 枚举 | 第 1 阶段标杆筛选、`/df:design` 架构模式预选 |
| T2 | 目标用户与核心痛点 | 核心痛点收敛到一句话 + 主要用户类型已确认 | 自由文本（汇入 description） | 第 2 阶段 Actor 识别基线 |
| T3 | 系统规模的量级表征 | 部署/数据/并发三档位均已落到枚举；条件性的并发拆分按系统类型完成 | `deployment`、`data_scale`、`concurrency.peak`（+ 条件性拆分字段）枚举 | 第 1 阶段标杆筛选、`/df:design` 规模约束 |
| T4 | 质量属性优先级 | 5 项（consistency/performance/availability/maintainability/cost）已排序 + 排序原因已说明 | `priorities` 1-5 排序 | 标杆研究权重、架构权衡 |
| T5 | 明确的边界约束 | ≥2 个"不做的事"已列出 | 自由文本（汇入 description） | 第 2 阶段 Feature 识别的禁区 |

#### 2.1 锚点字段（最终值必须落到模板枚举）

下游分支决策依赖以下字段，主会话**必须**将收集到的信息收敛到受控枚举值写入 yaml，不接受自由文本：

- **T1**：`system.primary_type`；`system.sub_type` 为可选追问，主会话根据系统类型和对话上下文自行判断是否需要
- **T3**：`system.scale.deployment`、`system.scale.data_scale`、`system.scale.concurrency.peak`
- **T4**：`quality_attributes.priorities` 5 项（各填 1-5 整数，无重复）

**T3 条件性追问**：主会话根据 T1 系统类型判断是否追问 concurrency 拆分字段（如读写拆分、produce/consume、task_count 等）。具体字段-系统类型映射见模板 `.claude/templates/domain-config.yaml` 中各 concurrency 字段注释。

**工具约束**：`AskUserQuestion` 最多 4 个选项。当锚点取值数 > 4 时（如 `primary_type` 有 10 个值、`concurrency.peak` 有 5 个值），主会话先通过开放式对话或粗分类将候选集缩至 ≤ 4 个，再用 `AskUserQuestion` 收口。多值排序如 priorities 5 项可直接用文本对话收集，主会话解析后回填。**手段不限，但结果必须是模板枚举值。**

> **枚举值的单一信息源**：所有锚点字段的具体取值范围见 `.claude/templates/domain-config.yaml` 各字段注释。本 skill 不再列举枚举内容。

#### 2.2 闭合度自检（出对话前主会话自检）

对话过程中主会话持续维护一份"主题闭合表"，每个主题有 3 种状态：未启动 / 进行中 / 已闭合。**所有主题进入"已闭合"才能进入步骤 3**。

**闭合判定标准**：
- T1：primary_type 已落到枚举值；sub_type 为可选，由主会话判断是否追问
- T2：用户已说出明确的核心痛点（不是"性能更好""体验更好"这种空话）+ 主要用户类型已确认
- T3：deployment / data_scale / concurrency.peak 均已落到枚举值；条件性拆分字段按 T1 类型规则补齐
- T4：5 项质量属性已排序（无并列、无遗漏）+ 用户给出了排序原因
- T5：≥2 个具体的"不做的事"已列出（不是"不做无关的事"这种空话）

**禁止行为**：
- 🚩 一次性把所有主题的问题列出来等用户回答
- 🚩 用预写脚本式提问（如"对每个场景问 X"），而不是根据用户已说的内容动态判断
- 🚩 没有触发追问就跳到下一主题（用户回答含糊时主会话有责任追问澄清）
- 🚩 在锚点字段上接受自由文本写入 yaml（如用户说"挺多并发"，主会话有责任引导其落到 `concurrency.peak` 的 5 档枚举值之一）

### 步骤 3：生成 domain-config.yaml

主会话将 T1-T5 收集到的信息按 2.0 主题清单与 2.1 锚点字段定义的对应关系填入 `.claude/templates/domain-config.yaml` 模板：

- 锚点字段：直接填入对应枚举值（取值见模板字段注释）
- T2 + T5 自由文本：综合为 `system.description` 一段（不做结构化拆分）
- 条件性 concurrency 拆分字段：不属于当前系统类型的直接删除，不留空
- `metadata.created_at` 填当前日期，`metadata.contributors` 填 `["/df:define"]`

写入 `.claude/domain-config.yaml`，用 `ls` 验证文件存在。

> **职责边界**：本文件由 /df:define 和 /df:design 共同维护。define 只填充 `system` 和 `quality_attributes` 两节，其他字段（`languages`、`benchmarks` 等）由 design 填充。标杆研究后可能需回溯修正 `description` 字段。

---

## 出口标准

### 准入检查清单

写入 `domain-config.yaml` 前必须确认（主题闭合度）：

- [ ] **T1 闭合**：`primary_type` 已落到枚举值；`sub_type` 视情况追问，不强制
- [ ] **T2 闭合**：核心痛点已收敛为一句话描述（非空话）+ 主要用户类型已确认
- [ ] **T3 闭合**：`deployment` / `data_scale` / `concurrency.peak` 均已落到枚举值；条件性拆分字段按 T1 类型规则全部补齐
- [ ] **T4 闭合**：5 项质量属性优先级已排序（1-5，无重复）+ 排序原因已说明
- [ ] **T5 闭合**：≥2 个明确的"不做的事"已列出（非空话）

写入后必须确认：

- [ ] **domain-config.yaml 已生成并落盘**（用 `ls` 验证文件存在）

**进入第 1 阶段条件**：准入检查清单全部通过

---