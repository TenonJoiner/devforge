# 第 2 阶段：迭代执行计划

**目标**：为当前迭代（如 M1-I1）建立 `iteration-m1-i1.md`

> **一次一迭代**：本次执行只产出当前迭代的执行计划文件。下一迭代在本迭代评审通过后，下次执行 `/df:plan` 时再生成。

---

## 步骤 1：迭代上下文收集（强制，不可跳过）

**由主会话直接通过 `AskUserQuestion` 向用户确认本迭代的实际投入和约束**，禁止派遣 agent（纯交互式信息收集无需经 agent 转发）。**禁止直接沿用 milestone-plan.md 的默认值**。收集完成后，主会话执行信息充分性检查清单确认信息充分性。

> **豁免说明**：本步骤为纯交互式信息收集阶段，无正式文档产出，不适用出口标准与评审修正循环。

**信息充分性检查清单**：以下 4 类**契约项**是下游 agent 产出本迭代执行计划时硬依赖的最小输入，每类必须有 ≥1 项实质内容（或显式标注为"无变化，沿用 milestone-plan.md"并说明判断依据）。**具体问什么由主会话基于本迭代上下文动态构造**，禁止机械套用固定问题。

| 契约项 | 下游用途 | 动态提问指南 |
|---------|---------|-----------|
| 本迭代实际可用人力 | 容量裁定 | 折算成等效人天；视情况追问：请假/差旅、新人加入、跨项目分担、临时调岗 |
| 本迭代周期 | 任务粒度 | 实际起止日期或周数；含节假日时单独标注 |
| 上轮历史校准 | Velocity 修正（I2 起强制，I1 跳过） | 上轮实际 Velocity vs 计划差异、遗留任务清单及原因 |
| 本迭代特殊约束 | 排期硬约束 | 视情况追问：外部依赖交付节点、合同里程碑、跨团队评审窗口、不可推迟的对外承诺 |

> **反模式**：直接沿用 milestone-plan.md 默认值（即使无变化也必须显式确认）、对 I1 强问历史校准、跳过追问导致契约项为空。

---

## 步骤 2：多 agent 并行产出

第 2 阶段复杂度为「高」（关键路径编排 + 多角色交叉验证），主会话直接决定派遣配置。

### 2.1 主会话决定 agent 配置

1. 读取 `templates/plan-iteration.md`，识别各章节的决策权重分布
2. 读取 `milestone-plan.md` 中的当前迭代相关 Backlog
3. 读取已收集的迭代上下文
4. **决定 agent 配置**（动态产出，不预设视角）：
   - **并行产出 agent 数量**：基于高复杂度下限，**≥3** 个
   - **角色类型**：project / architect / product（按需选择）
   - **视角切分**：主会话基于本次迭代的具体 Backlog 内容、依赖关系、关键路径特征，产出 ≥3 个互补视角，在派遣 prompt 中说明切分理由
     - 视角必须互补、独立、不重叠
     - 视角数 = 并行产出 agent 数
   - **关键假设类型**：迭代预算假设、依赖就绪假设、外部交付假设
5. **并发控制**：遵守 SKILL.md「Agent 并发控制」。禁止以并发限制为由减少 agent 数量

### 2.2 并行启动产出 agent

按 2.1 确定的配置，**并行启动 ≥3 个 agent**（不同角色，差异化视角）：

- 各 agent 从分配的视角独立产出其负责的维度
- **写入文件**：将完整产出写入 `-draft-` 标记的中间文件，如 `iteration-{m}-{i}-draft-{role}-{view}.md`
- **返回摘要**：向主会话返回 ≤10 行结构化摘要（产出文件路径、Wave 数、proposal 数、关键发现数、异常点）
- **模板约束**：使用 `templates/plan-iteration.md`
- **禁止**多个 agent 使用同一 prompt 模板、同一分析框架

### 2.3 整合产出（合并 agent）

**主会话确认所有产出 agent 完成后**，派一个合并 project agent：

- **输入**：所有 `iteration-{m}-{i}-draft-*.md` 文件
- **执行**：
  - 按 `templates/plan-iteration.md` 模板组装
  - 冲突按职能裁决：技术依赖冲突以 architect 为准；优先级冲突以 product 为准；容量冲突以 project 为准
  - 去重并客观记录冲突
- **输出**：`docs/iteration-plan/iteration-m<x>-i<y>.md`
- **返回**：向主会话返回摘要（合并后 Wave 数、proposal 数、冲突标注数）

### 2.4 产出完整性检查

合并后的文件写入后、进入步骤 3 前，必须执行：

- [ ] **文件已验证存在**（`ls`/`wc` 确认）
- [ ] **所有产出 agent 状态** = 已完成（成功或最终失败）
- [ ] **总点数 ≤ 迭代预算**，任务分布合理
- [ ] **Wave 并行分组反映真实依赖关系**
- [ ] **预留 ≥ 20% 缓冲容量**
- [ ] **每个 proposal 可追溯到 milestone-plan.md Backlog**
- [ ] **文档头部**已标注状态为"待评审"

**未通过处理**：
- 任一 checklist 项未通过 → 回退到 2.1，重新决定 agent 配置
- agent 仍有运行中 → 等待完成，禁止提前进入步骤 3

**主会话确认所有产出 agent 已完成**（成功或最终失败），且产出完整性检查通过后，**立即执行 draft 清理**（按 SKILL.md「draft 清理约束」）：

```bash
rm docs/iteration-plan/iteration-*-draft-*.md
ls docs/iteration-plan/ | grep 'iteration.*draft' && echo "清理未完成" || echo "清理通过"
```

清理通过后方可进入步骤 3。禁止 draft 文件残留进入评审。

---

## 步骤 3：评审修正循环

> **准入条件**：步骤 2 已完成（iteration-m<x>-i<y>.md 已写入并通过产出完整性检查）
> **核心约束**：按 SKILL.md「标准评审修正循环」执行。本文只声明本阶段特有参数和规则，不得重复标准循环内容。

### 3.1 评审配置

| 参数 | 值 | 说明 |
|------|-----|------|
| 评估对象数 | 本迭代 proposal 数量 | iteration-m<x>-i<y>.md 中列出的所有 proposal |
| 缺陷密度门槛 | ≤ 0.5 分/proposal | 单迭代范围，关键路径编排重要但可调整，见 SKILL.md「缺陷密度门槛」 |
| 修正 agent | project agent（Wave/容量类）/ architect agent（依赖类） | 按问题类型分配 |
| 修正后复核路径 | 回到 3.1 重新评审；修正后的每一轮复核都必须重新计算缺陷密度并填入评审记录 | 对应标准循环第 5 步 |
| > 30 处回退目标 | 回退到步骤 2.1 | 重新决定 agent 配置和视角切分 |
| reviewer 基线 | ≥3 个 | 至少 architect-reviewer + product-reviewer + project-reviewer 各 1 |

### 派遣 prompt 字段

按 SKILL.md「评审视角（reviewer agent）」一节的「派遣 prompt 必备字段」清单组装，本阶段具体取值如下：

- **被评审对象路径**：`docs/iteration-plan/iteration-m<x>-i<y>.md`
- **被评审 template 路径**：`templates/plan-iteration.md`（视角来源 1：reviewer 从其 mandatory-sections + 合理性检查清单提取评审锚点）
- **评审报告产出路径**：`docs/iteration-plan/iteration-{m}-{i}-review.md`（多 reviewer / 多轮追加同一文件）
- **评审报告格式**：`templates/review-report.md`

### 特异性子维度（视角来源 2：主会话动态注入）

- 基于本迭代包含的 proposal 技术特征注入特定检查项（如涉及一致性协议 → 检查依赖链中协议初始化是否前置）
- 基于 `quality_attributes.priorities` 注入关键路径上的质量属性检查深度
- 基于上次迭代的遗留任务注入"遗留任务影响评估"检查项

### 评审思维风格（视角来源 3：reviewer agent 人设自带，主会话不重复声明）

- `architect-reviewer`：技术/架构视角
- `product-reviewer`：业务/用户视角
- `project-reviewer`：进度/资源视角

> **主会话职责**：在派遣评审 agent 的 prompt 中注入文档的系统上下文——本文档在项目规划中的位置（迭代执行计划，定义本迭代具体任务编排和资源分配）、重要性（直接影响本迭代的开发执行和团队承诺）、可替换性（修正成本评估）。

### 3.2 独立评审

**并行派遣 reviewer**，各 reviewer：
- 读取 `iteration-m<x>-i<y>.md` 执行评审
- 将评审意见追加到 `docs/iteration-plan/iteration-{m}-{i}-review.md`
- 向主会话返回数字摘要：{issues: N, density: X, critical: Y}

主会话从数字摘要判定通过/修正/回退，不读取完整评审内容。

### 3.3 验证与修正

> 按 SKILL.md「标准评审修正循环」步骤 2-7 执行。

**成功退出条件**（同时满足）：
- 所有 reviewer 均已完成独立评审
- 无 CRITICAL 问题
- 缺陷密度 ≤ 0.5 分/proposal
- Wave 分组正确反映迭代内 proposal 间的依赖关系
- 总点数 ≤ 迭代预算，高风险任务 ≤ 50%
- 文档末尾已写入 `**评审状态**: ✅ PASS` 标记（按 SKILL.md「评审状态标记契约」格式）
- 所有 HIGH 问题已评估：接受修正 / 接受延期 / 拒绝
- MEDIUM/LOW 问题记录但不阻塞推进，纳入后续迭代跟踪

---
