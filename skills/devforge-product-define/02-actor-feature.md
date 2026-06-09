# 第 2 阶段：Actor-Feature 识别与定稿

**准入条件**：第 1 阶段已完成并通过出口标准（无 CRITICAL 问题 + 缺陷密度达标）
**产出文件**：`docs/requirements/product-spec.md`（Actor-Feature 章节定稿）

---

## 步骤 1：Actor 识别

主会话按以下固定配置派遣 agent。Actor 严格定义、3 类类型、判定决策树参见 SKILL.md 核心原则 #3 与模板。

### Actor 识别配置

**两路独立并行，互补验证**：

**设计路径**（3-5 个 product agent）：
- **视角必须围绕"外部交互维度"切分，禁止围绕"系统内部分解"切分**
- **合法视角候选清单**（视产品而定，主会话从中选取 3-5 个互补维度）：
  - V-Users：用户角色细分（人类，按职责/技能领域细分）
  - V-Producers：数据生产生态（外部系统，谁向系统送数据）
  - V-Consumers：数据消费生态（外部系统，谁从系统取数据）
  - V-Ops：管理运维生态（外部系统，谁部署/监控/升级系统）
  - V-Compliance：合规与安全生态（外部系统，谁审计/认证/加密对接）
  - V-Time：时间触发源（特殊类型，仅识别驱动独立用例的时间事件）
- **禁止视角**：任何围绕"系统内部分解"的视角（含"内部组件"、"系统组件"、"数据生命周期阶段"、"故障内部处理流程"等字眼），这类视角必然导致内部组件混入 Actor
- 主会话基于 `domain-config.yaml` 选择具体视角组合，在派遣 prompt 中说明每个视角的边界
- **禁止读取标杆研究报告**，确保不因竞品分析而限制设计空间
- **写入文件**：各 product agent 将识别的 Actor 候选写入 `docs/requirements/actors-draft-{view}.md`
- **返回摘要**：向主会话返回 ≤5 行摘要（识别 Actor 数、类型分布、异常点）

**证据路径**（2-3 个 researcher agent）：
- 按竞品分组切分（每组 2-3 个标杆）
- 读取 `docs/requirements/reference/`，仅提取竞品的**外部 Actor 映射表**（人类用户 + 外部系统 + 时间触发源）
- **同样禁止识别内部组件**作为 Actor 证据（即便竞品文档列出了 vminsert/taosd 等，这些是架构组件不是 Actor）
- **不做本产品设计决策**，仅提供证据
- **写入文件**：将外部 Actor 映射表写入 `docs/requirements/actors-evidence-{group}.md`
- **返回摘要**：向主会话返回 ≤5 行摘要（提取 Actor 数、来源标杆、关键发现）

### Agent prompt 必须包含的禁令段（设计路径与证据路径通用）

任何派遣的 agent prompt 必须显式注入以下段落：

```markdown
## Actor 识别禁令（违反则产出无效）

- ❌ 禁止识别"内部组件"作为 Actor 候选（写入网关/查询协调器/存储引擎/副本管理器/选主器/调度器等）
- ❌ 禁止把内部模块（路由器/缓存/消息总线/协议适配层）当 Actor
- ✅ 仅识别 3 类合法 Actor：
  - **人类**：物理存在的人
  - **外部系统**：系统边界外、独立运行的另一个系统/设备
  - **时间触发源**：时间事件 + 驱动了一个有用户价值的独立用例（如 TTL 触发清理、定时降采样）。状态驱动的内部组件（如选主器）不算时间触发源
- 每个 Actor 候选必须能说出：(1) 在哪里存在（外部边界外）；(2) 与系统的交互动作（输入/输出）；(3) 关注的可观测指标
```

### 合并阶段（合并 product agent）

**主会话确认所有 agent 完成后**，派一个合并 product agent：

- **输入**：`actors-draft-*.md`（设计路径）和 `actors-evidence-*.md`（证据路径）
- **执行**：按以下 4 步规则整合

**Step 1 合并并集 + 边界校验**（硬约束）：
- 各路产出取并集；**交集**直接收录；**设计独有**与**证据独有**评估并标注理由；无法调和的差异记入「争议记录」
- 按 SKILL.md 与模板的判定决策树**逐个候选走完全部判定**（含类型判定 + 独立性判定），不通过的剔除

**Step 2 合并 4 法则压缩**：按 SKILL.md「Actor 合并 4 法则」执行；每次合并记录"被合并 Actor 来源 + 合并理由"

**Step 3 质量信号复审**：按 SKILL.md「Actor 数量复审触发条件」检查 4 个信号；信号 C 强制剔除，其余触发对应复审

**Step 4 写入最终文件**：
- 用 Write 工具写入 `docs/requirements/product-spec.md`（Actors 章节），格式遵循 `templates/req-product-spec.md`
- 关系图中**只能画 Actor**（人类 / 外部系统 / 时间触发源），禁止画内部组件

- **输出**：`product-spec.md#Actors`
- **返回**：向主会话返回摘要（合并前候选数、合并后 Actor 数、去重数、争议数）

> **Actor 判定示例库**参见 `templates/req-product-spec.md` Actor 反例表，本文不重复

### 出口标准（由主会话检查）

- [ ] Actor 列表非空，至少识别出 3 个核心 Actor
- [ ] **Actor 类型严格性**：所有 Actor 类型属于 {人类 / 外部系统 / 时间触发源}，无内部组件
- [ ] **独立性判定已通过**：每个 Actor 满足持续直接交互 + 独立 Feature 驱动力
- [ ] **关系图合规**：关系图中无内部组件节点
- [ ] 每个 Actor 已明确：类型、职责、交互方式、关注点
- [ ] 每个时间触发源 Actor 已说明驱动的独立用例
- [ ] 同类 Actor 已按 4 法则合并完成
- [ ] 4 个质量信号已复审，触发的复审已闭环
- [ ] 隐性 Actor 检查已完成（合规检查/运维值班/第三方集成/监控告警系统）
- [ ] 文档已按模板结构写入 `product-spec.md#actors`
- [ ] **draft 已清理**：执行 `rm docs/requirements/actors-draft-*.md docs/requirements/actors-evidence-*.md`，并用 `ls` 确认无残留（按 SKILL.md「draft 清理约束」）
- [ ] 文件已验证存在（`ls`/`wc` 确认）
- [ ] **人工确认已完成**（步骤 1.5）

---

## 步骤 1.5：Actor 人工确认

**执行前提**：步骤 1 Actor 列表已写入 `product-spec.md`

Actor 是 Feature 的输入基础，错误的 Actor 列表会导致 Feature 识别全部浪费。步骤 1 完成后输出汇总表格，等待用户确认后才能进入步骤 2。

---

## 步骤 2：Feature 识别

**执行前提**：步骤 1 Actor 列表已写入 `product-spec.md` 且经过人工确认

### Feature 识别配置

**≥4 个 product agent**（视角切分由主会话根据产品上下文动态决定）：
- 主会话基于 `domain-config.yaml`（`primary_type`、`description`、`priorities`）和已识别的 Actor 列表，产出 ≥4 个互补视角，确保覆盖所有 Actor 核心关注领域和质量属性优先级
- 视角必须在派遣 prompt 中明确，禁止套用固定视角清单（如"终端用户/运维/集成/安全"）
- 视角间必须互补、独立、不重叠

**1 个 architect agent**：
- 负责实现复杂度评估（粗粒度，不要求细化到子系统边界）

### 执行

按"第 1 波 product 并行 → 合并 product agent 整合 → 第 2 波 architect 评估"串行编排，避免 architect agent 在 Feature 列表尚未产出时无输入可读。

**第 1 波：≥4 个 product agent（遵守 SKILL.md「Agent 并发控制」滑动窗口）**
- 各 agent 读取 `product-spec.md#actors` 和分配的用户场景视角，围绕 Actor 核心目标独立推导 Feature 列表
- 禁止用一个 agent "内部发散多个方案"替代多个 agent 独立产出
- **写入文件**：将 Feature 候选写入 `docs/requirements/features-draft-{view}.md`
- **返回摘要**：向主会话返回 ≤5 行摘要（Feature 数、覆盖 Actor、关键争议点）
- 若 agent 数超过 `agent.max_concurrent`，初始启动 5 个，每完成一个立即补位。禁止以并发限制为由减少 agent 数量

**主会话确认第 1 波完成后，派合并 product agent**
- **输入**：`features-draft-*.md`
- **执行**：
  - **对齐分类框架**：基于模板结构确定统一的特性域分类和优先级定义
  - 合并 Feature 列表，去重并客观记录冲突
  - 每个 Feature 记录：一句话价值摘要、涉及 Actor、归属特性域、英文标识（kebab-case，用于文件命名）、优先级
  - 产出 Feature 间依赖关系矩阵
- **输出**：用 Write 写入 `product-spec.md` Feature 章节草稿（复杂度字段先留空）
- **返回**：向主会话返回摘要（合并后 Feature 数、冲突数、特性域分布）

**第 2 波：1 个 architect agent**
- 读取 `product-spec.md`（含合并后的 Feature 列表）和 `.claude/domain-config.yaml`
- 评估各 Feature 实现复杂度（粗粒度，不要求细化到子系统边界）
- 用 Edit 将复杂度评估回填到 `product-spec.md` 对应 Feature 字段
- 返回摘要（高/中/低复杂度分布）

**写作约束**
- Feature 价值论证必须是推导式，禁止"矩阵后直接给结论"
- 文档结构遵循 `templates/req-product-spec.md`

**出口标准**（由主会话检查）：
- [ ] Feature 数量 ≥ 核心 Actor 数量 × 2，且总数 ≥ 5（复杂系统下限）
- [ ] Feature 覆盖所有已识别 Actor 的核心目标，每个核心 Actor 至少对应 2 个 Feature
- [ ] 每个 Feature 已记录：一句话价值摘要、涉及 Actor、归属特性域、优先级
- [ ] Feature 间依赖关系矩阵已产出
- [ ] 价值论证为推导式，非直接给结论
- [ ] 文档已按模板结构写入 `product-spec.md`
- [ ] **draft 已清理**：执行 `rm docs/requirements/features-draft-*.md`，并用 `ls` 确认无残留（按 SKILL.md「draft 清理约束」）

---

## 步骤 3：评审修正循环

> **准入条件**：`product-spec.md` 草稿已写入文件（步骤 1 + 步骤 2 均已完成）
> **核心约束**：按 SKILL.md「标准评审修正循环」执行，本文只声明本阶段特有参数和规则。

### 3.1 评审配置

**reviewer agent 配置**：

- **基线类型**：≥3 个 reviewer（至少 product-reviewer × 2 + architect-reviewer × 1）
- **同一类型可多实例独立评审**——product-reviewer × 2 是本阶段固有的稳定切分（见下方"本阶段稳定切分"），但主会话也可基于复杂度上调（如再加 1 个 architect-reviewer 对技术幻想做交叉验证）
- **数量由主会话基于 Actor / Feature 数量与产品复杂度动态决定**（基线 3，可上调到 4-5），禁止默认按"3 个分工"派遣

**派遣 prompt 字段**（按 SKILL.md「评审视角（reviewer agent）」一节的「派遣 prompt 必备字段」清单组装，本阶段具体取值如下）：

- **被评审对象路径**：`docs/requirements/product-spec.md`
- **被评审 template 路径**：`templates/req-product-spec.md`（视角来源 1：reviewer 从其 mandatory-sections + 自检清单提取评审锚点）
- **评审报告产出路径**：`docs/requirements/product-spec-review.md`（多 reviewer / 多轮追加同一文件）
- **评审报告格式**：`templates/review-report.md`

**本阶段稳定切分**（不是动态特异性子维度，是本阶段固有的 reviewer 实例切分方式）：

- 派遣 2 个 product-reviewer 实例，分别在派遣 prompt 中注入侧重指引：
  - 实例 A：**用户价值与商业合理性**侧重——Feature 的用户假设、优先级推导、价值论证充分性
  - 实例 B：**Actor 完备性与覆盖度**侧重——Actor 遗漏（含隐性 Actor）、Feature 对 Actor 核心目标的覆盖度、特性域分类合理性
- 派遣 1 个 architect-reviewer 实例，在派遣 prompt 中**明确评审范围约束**：
  - **允许评审**：技术可行性粗判（拦截 Feature 中的技术幻想，如"零延迟全球同步"等不可实现承诺）、步骤 2 architect agent 给出的实现复杂度评估是否过度乐观
  - **明确禁评**：跨子系统边界、架构一致性、依赖关系合理性 — 这些维度依赖 design.md 细化到 Feature 粒度，本阶段不具备评审材料，硬评易产生伪 CRITICAL

**特异性子维度**（视角来源 2：主会话基于本次产品在派遣 prompt 中动态注入，禁止套用固定清单）：

- 基于 `domain_specific` 注入对应领域的 Actor / Feature 检查项（如边云协同 → 要求 product-reviewer 实例 B 重点检查"边运维""云管理"类 Actor 的识别完整性）
- 基于 `quality_attributes.priorities` 前两项注入 Feature 优先级合理性的检查深度
- 基于 Non-Goals 注入"Feature 是否越界涉及本产品明确不做的范围"的识别要求

**评审思维风格**（视角来源 3：reviewer agent 人设自带，主会话不重复声明）：

- `product-reviewer`：业务/用户视角
- `architect-reviewer`：技术/架构视角（本阶段范围受限，见上方"评审范围约束"）

### 3.2 独立评审

**并行派遣 reviewer，各 reviewer**：
- 读取 `product-spec.md` 执行评审
- 将评审意见追加到 `product-spec-review.md`
- 向主会话返回数字摘要：{issues: N, density: X, critical: Y}

主会话从数字摘要判定通过/修正/回退，不读取完整评审内容。

### 3.3 验证与修正

> 按 SKILL.md「标准评审修正循环」步骤 2-7 执行。本阶段特有参数声明如下：

| 参数 | 值 | 说明 |
|------|-----|------|
| 评估对象数 | Actor 数量 / Feature 数量 | 按步骤分别计算密度，**任一维度超标即进入修正** |
| 缺陷密度门槛 | 步骤1 ≤ 1.5 分/Actor；步骤2 ≤ 1.5 分/Feature | 见 SKILL.md「缺陷密度门槛标定依据」 |
| 修正 agent | product agent | 修正后更新 `product-spec.md` |
| 修正后复核路径 | 回到 3.2 独立评审；修正后的每一轮复核都必须重新计算缺陷密度并填入评审记录 | |
| \> 30 处回退目标 | 步骤1高 → 步骤1；步骤2高 → 步骤2；两者均高 → 步骤1 | Actor 是 Feature 的基础 |

**成功退出条件**（同时满足）：
- 所有 reviewer 均已完成独立评审
- 无 CRITICAL 问题
- 步骤 1 缺陷密度 ≤ 1.5 分/Actor，步骤 2 缺陷密度 ≤ 1.5 分/Feature
- 文档 `docs/requirements/product-spec.md` 已写入并验证存在
- `product-spec.md` 末尾已写入 `**评审状态**: ✅ PASS` 标记（按 SKILL.md「评审状态标记契约」格式）
- 所有 HIGH 问题已评估：接受修正 / 接受延期 / 拒绝
