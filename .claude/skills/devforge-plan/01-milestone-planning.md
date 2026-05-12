# 第 1 阶段：里程碑规划 + Backlog

**目标**：建立里程碑计划文件 `docs/iteration-plan/milestone-plan.md`。

---

## 步骤 1：项目背景收集（强制，不可跳过）

派遣 `project` 通过交互式提问向用户收集项目背景信息。**禁止自行假设任何团队/时间参数**。收集完成后，主会话执行信息充分性检查清单确认信息充分性。

> **豁免说明**：本步骤为纯交互式信息收集阶段，无正式文档产出，不适用出口标准与评审修正循环。

**信息充分性检查清单**（确认所有必收集项已回答或已显式标注为假设值）：

| 必收集项 | 说明 |
|---------|------|
| 团队规模 | 全职/兼职人数 |
| 全职/兼职比例 | 实际可用人力 |
| 预期时间跨度 | 项目总周期 |
| 迭代周期偏好 | 1 周 / 2 周 / 其他 |
| 历史 Velocity | 如有历史数据 |
| 外部约束 | 依赖、假期、里程碑等 |

---

## 步骤 2：多 agent 并行产出

第 1 阶段复杂度为「极高」（结构化规划 + 跨子系统依赖 + 不可逆决策），主会话直接决定派遣配置。

### 2.1 主会话决定 agent 配置

1. 读取 `.claude/templates/plan-milestone.md`，识别各章节的决策权重分布
2. 读取 `docs/architecture/` 和 `docs/requirements/` 的上游文档，理解系统上下文
3. 读取已收集的项目背景信息
4. **决定 agent 配置**（动态产出，不预设视角）：
   - **并行产出 agent 数量**：基于极高复杂度下限，**≥5** 个
   - **角色类型**：project / architect / product / researcher（按需选择，不预设固定组合）
   - **视角切分**：主会话基于本次产品的 `primary_type` / `description` / `quality_attributes.priorities` / 里程碑上下文，产出 ≥5 个互补视角，在派遣 prompt 中说明切分理由
     - 视角必须互补、独立、不重叠
     - 视角数 = 并行产出 agent 数
     - 禁止套用固定视角清单（如"结构/依赖/价值/数据/容量"）
   - **关键假设类型**：团队容量与 Velocity 假设、跨子系统接口就绪假设、外部依赖交付假设
5. **并发控制**：遵守 SKILL.md「Agent 并发控制」，若总数超 `agent.max_concurrent`，使用滑动窗口策略。禁止以并发限制为由减少 agent 数量

### 2.2 并行启动产出 agent

按 2.1 确定的配置，**并行启动 ≥5 个 agent**（不同角色，差异化视角）：

- 各 agent 从分配的视角独立产出其负责的维度
- **写入文件**：将完整产出写入 `-draft-` 标记的中间文件，如 `milestone-draft-{role}-{view}.md`
- **返回摘要**：向主会话返回 ≤10 行结构化摘要（产出文件路径、核心 proposal 数、关键发现数、异常点、编排提示）
- **模板约束**：使用 `.claude/templates/plan-milestone.md`
- **禁止**多个 agent 使用同一 prompt 模板、同一分析框架

### 2.3 整合产出（合并 agent）

**主会话确认所有产出 agent 完成后**，派一个合并 project agent：

- **输入**：所有 `milestone-draft-*.md` 文件
- **执行**：
  - 按 `.claude/templates/plan-milestone.md` 模板组装
  - 冲突按职能裁决：技术依赖以 architect 为准，价值优先级以 product 为准，容量估算以 project 为准
  - 去重并客观记录冲突
- **输出**：`docs/iteration-plan/milestone-plan.md`
- **返回**：向主会话返回摘要（合并后里程碑数、proposal 数、冲突标注数、各视角覆盖度）

### 2.4 产出完整性检查

合并后的文件写入后、进入步骤 3 前，必须执行：

- [ ] **文件已验证存在**（`ls`/`wc` 确认）
- [ ] **所有产出 agent 状态** = 已完成（成功或最终失败）
- [ ] **里程碑划分**符合技术依赖顺序和产品目标
- [ ] **Backlog 覆盖**所有已知 Feature，无遗漏关键路径
- [ ] **故事点与团队 Velocity 匹配**
- [ ] **已标注关键风险及缓解策略**
- [ ] **文档头部**已标注状态为"待评审"

**未通过处理**：
- 任一 checklist 项未通过 → 回退到 2.1，重新决定 agent 配置
- agent 仍有运行中 → 等待完成，禁止提前进入步骤 3

**主会话确认所有产出 agent 已完成**（成功或最终失败），且产出完整性检查通过后，方可进入步骤 3。禁止在 agent 仍在运行期间提前进入评审。

---

## 步骤 3：评审修正循环

> **准入条件**：步骤 2 已完成（milestone-plan.md 已写入并通过产出完整性检查）
> **核心约束**：按 SKILL.md「标准评审修正循环」执行。本文只声明本阶段特有参数和规则，不得重复标准循环内容。

### 3.1 评审配置

| 参数 | 值 | 说明 |
|------|-----|------|
| 评估对象数 | Backlog proposal 数量 | milestone-plan.md 中列出的所有 proposal |
| 缺陷密度门槛 | ≤ 0.3 分/proposal | 里程碑划分为不可逆决策，从严，见 SKILL.md「缺陷密度门槛标定依据」 |
| 修正 agent | project agent（计划编排类）/ architect agent（技术依赖类）/ researcher agent（数据校准类） | 按问题类型分配 |
| 修正后复核路径 | 回到 3.1 重新评审；修正后的每一轮复核都必须重新计算缺陷密度并填入评审记录 | 对应标准循环第 5 步 |
| > 30 处回退目标 | 回退到步骤 2.1 | 重新决定 agent 配置和视角切分 |
| reviewer 基线 | ≥3 个 | 至少 architect-reviewer + product-reviewer + project-reviewer 各 1 |

### 通用职责模板（派遣 prompt 起点）

- `architect-reviewer`：技术依赖准确性、关键路径识别、接口冻结点合理性、与架构文档的一致性
- `product-reviewer`：价值对齐、优先级排序合理性、验收标准映射、Backlog 覆盖度
- `project-reviewer`：里程碑划分逻辑、团队容量匹配、Velocity 合理性、可交付性、风险缓冲充分性

### 特异性子维度（主会话动态注入）

- 基于 `quality_attributes.priorities` 前两项注入关键路径检查深度
- 基于系统规模（`domain-config.yaml` 中的 deployment / data_scale / concurrency）注入容量估算合理性检查项
- 基于 Non-Goals 注入"Backlog 是否越界涉及明确不做的范围"的识别要求

> **主会话职责**：在派遣评审 agent 的 prompt 中注入文档的系统上下文——本文档在项目规划中的位置（里程碑计划，定义整体迭代节奏和 Backlog 优先级）、重要性（影响后续所有迭代的执行计划、资源分配和团队承诺）、可替换性（修正成本评估）。

### 3.2 独立评审

**并行派遣 reviewer**，各 reviewer：
- 读取 `milestone-plan.md` 执行评审
- 将评审意见追加到 `docs/iteration-plan/milestone-plan-review.md`
- 向主会话返回数字摘要：{issues: N, density: X, critical: Y}

主会话从数字摘要判定通过/修正/回退，不读取完整评审内容。

### 3.3 验证与修正

> 按 SKILL.md「标准评审修正循环」步骤 2-7 执行。

**成功退出条件**（同时满足）：
- 所有 reviewer 均已完成独立评审
- 无 CRITICAL 问题
- 缺陷密度 ≤ 0.3 分/proposal
- 文档末尾已写入 `**评审状态**: ✅ PASS` 标记（按 SKILL.md「评审状态标记契约」格式）
- 所有 HIGH 问题已评估：接受修正 / 接受延期 / 拒绝
- MEDIUM/LOW 问题记录但不阻塞推进，纳入后续迭代跟踪

---
