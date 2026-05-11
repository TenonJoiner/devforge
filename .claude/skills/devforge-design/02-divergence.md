# 第 2 阶段：方案发散

**准入条件**：第 1 阶段所有标杆文件通过评审（无 CRITICAL + 缺陷密度 ≤ 2.0/标杆）
**产出文件**：`docs/architecture/decisions/decision-overall.md` + `docs/architecture/decisions/decision-<维度>.md`

---

## 步骤 1：整体架构发散

**复杂度**：极高（系统级架构方案）
**产出文件**：`docs/architecture/decisions/decision-overall.md`

### 1.1 主会话决定 agent 配置

主会话直接决策派遣配置（不委托 plan agent 做任务解构）：

1. 读取 `.claude/domain-config.yaml`，理解系统类型、质量属性优先级、规模特征
2. 读取 `docs/architecture/reference/` 标杆研究报告，理解已研究的架构模式
3. 读取 `.claude/templates/arch-system.md`，明确模板章节结构
4. **决定 agent 配置**（动态产出，不预设视角）：
   - **architect 数量**：极高复杂度下限 ≥5（阶段总 agent 数）
   - **视角切分**：基于产品上下文动态产出 ≥5 个互补视角，在派遣 prompt 中说明切分理由
     - 视角切分遵循 SKILL.md「视角切分原则」
   - **reviewer 配置**：≥3 个（极高复杂度下限），角色组合由主会话基于域特征动态决定

### 1.2 并行启动 architect（滑动窗口限流）

1. 按 1.1 确定的配置，**并行启动 ≥5 个 architect agent**（遵守 SKILL.md「Agent 并发控制」滑动窗口）：
   - 各自从分配的架构视角独立发散，产出 ≥2 个整体架构备选方案
   - **写入文件**：将方案写入 `docs/architecture/decisions/decision-overall-draft-{view}.md`
   - **返回摘要**：向主会话返回 ≤5 行轻量摘要（备选方案数、子系统边界、关键 Trade-off）
   - **禁止**用一个 agent "内部发散多个方案"替代多个 agent 独立产出
   - 方案聚焦设计决策和 rationale，**禁止讨论具体代码实现**

2. 若 agent 数超过 `agent.max_concurrent`，初始启动 5 个，每完成一个立即补位。禁止以并发限制为由减少 architect 数量

### 1.3 合并 architect

**主会话确认所有 architect 完成后**，派一个合并 architect：

- **输入**：`decision-overall-draft-*.md`
- **执行**：
  - 读取所有 draft，按 `.claude/templates/arch-system.md` 模板结构整合
  - 在文档开头增加「研究视角」章节，标注各视角的 architect 归属
  - 合并备选方案，保留有实质差异的方案（≥2 个），客观记录冲突和分歧
  - 各子系统职责边界定义、数据流正常路径 + 错误传播路径定义
- **输出**：用 Write 写入 `docs/architecture/decisions/decision-overall.md`
- **返回**：向主会话返回摘要（合并后方案数、子系统数、冲突数）

**步骤 1 出口标准**（由主会话检查）：
- [ ] 整体架构备选方案 ≥ 2 个
- [ ] 各子系统职责边界已定义
- [ ] 数据流正常路径 + 错误传播路径已定义
- [ ] 文档已按模板结构写入 `decision-overall.md`
- [ ] 文件已验证存在（`ls`/`wc` 确认）

### 1.4 评审修正循环

> **准入条件**：步骤 1 出口标准已通过
> **核心约束**：按 SKILL.md「标准评审修正循环」执行，本文只声明本阶段特有参数和规则。

**评审配置**：

≥3 个 reviewer，并行独立评审：

- 主会话基于域特征动态决定 reviewer 角色组合（如 architect-reviewer × 2 + product-reviewer × 1，或 architect-reviewer + product-reviewer + project-reviewer 等），确保视角差异化
- 评审维度必须覆盖：架构合理性、需求对齐、可实现性
- **主会话职责**：在派遣评审 agent 的 prompt 中注入文档的系统上下文——本文档在架构体系中的位置（整体架构方案文档，定义子系统边界和全局数据流）、重要性（影响后续所有维度的方案发散和子系统设计）、可替换性（修正成本评估）

| 参数 | 值 | 说明 |
|------|-----|------|
| 评估对象数 | 备选方案数 | decision-overall.md 中的方案数 |
| 缺陷密度门槛 | ≤ 2.0 分/方案 | 见 SKILL.md「缺陷密度门槛标定依据」 |
| \> 30 处回退目标 | 回退到步骤 1.1 | 重新决定 agent 配置和视角切分 |

**成功退出条件**（同时满足）：
- 所有 reviewer 均已完成独立评审
- 无 CRITICAL 问题
- 缺陷密度 ≤ 2.0 分/方案
- `decision-overall.md` 末尾已写入 `**评审状态**: ✅ PASS` 标记
- 所有 HIGH 问题已评估：接受修正 / 接受延期 / 拒绝

---

## 步骤 2：维度划分

**执行前提**：步骤 1 评审通过（`decision-overall.md` 有 ✅ PASS 标记）

> **职责归属**：维度识别属于「内容判断」（基于已评审通过的整体方案，提炼需要独立决策的技术维度），按 SKILL.md「主会话职责边界」应由 architect agent 产出，主会话只做调度与确认。这是轻量识别任务（单 agent 即可），不需要多 agent 并行发散。

派一个 architect agent 执行维度划分：

- **输入**：`docs/architecture/decisions/decision-overall.md`（已 PASS）
- **任务**：
  - 识别整体方案中需要独立决策的技术维度（如数据流、一致性、存储、网络、故障处理等），维度选择由产品上下文驱动，不预设清单
  - 每个维度给出明确的决策边界说明（与其他维度无重叠）
  - 验证各维度与 decision-overall.md 的子系统划分一致
- **输出**：将「维度划分」章节追加到 `decision-overall.md`
- **返回**：向主会话返回维度清单（数量 + 名称）和 ≤3 行划分理由

主会话职责：
- 检查维度清单是否合理（数量、命名、边界），如有疑虑要求 agent 调整
- 验证 `decision-overall.md` 已追加维度章节并通过出口标准

**步骤 2 出口标准**：
- [ ] 维度清单已明确（≥3 个维度，覆盖关键决策点）
- [ ] 每个维度有明确的决策边界说明（不与其他维度重叠）
- [ ] 各维度与 decision-overall.md 的子系统划分一致
- [ ] 维度划分方案已追加到 decision-overall.md 并验证存在

---

## 步骤 3：维度方案发散

**复杂度**：高（按维度）
**产出文件**：`docs/architecture/decisions/decision-<维度>.md`

### 3.1 主会话决定 agent 配置

主会话直接决策派遣配置：

1. 基于步骤 2 确认的维度清单和 `domain-config.yaml`，对每个维度独立评估研究需求
2. **researcher 配置**：每个维度 2 个 researcher，从不同视角研究标杆方案在该维度的设计选择
   - 视角切分遵循 SKILL.md「视角切分原则」
3. **architect 配置**：每个维度 ≥3 个 architect（高复杂度下限）
   - 视角切分遵循 SKILL.md「视角切分原则」
4. **reviewer 配置**：每个维度 ≥2 个 reviewer

### 3.2 维度内串行编排（researcher → 合并 → architect → 合并）

每个维度内部按"researcher 调研 → 合并 → architect 发散 → 合并"串行编排：

**第 1 波：每个维度 2 个 researcher 并行**
- 各自从分配的视角研究标杆方案在该维度的设计选择
- **写入文件**：`docs/architecture/decisions/<维度>-research-draft-{view}.md`
- **返回摘要**：向主会话返回 ≤5 行轻量摘要（标杆方案数、关键发现、对我方启示）

**合并 researcher**：每个维度各派一个合并 researcher
- 读取 `<维度>-research-draft-*.md`，整合为维度调研摘要
- **输出**：`docs/architecture/decisions/<维度>-research.md`

**第 2 波：每个维度 ≥3 个 architect 并行**
- 基于维度调研摘要，进行该维度的架构方案发散，每个 architect 产出 ≥2 个备选方案
- **写入文件**：`docs/architecture/decisions/decision-<维度>-draft-{view}.md`
- **返回摘要**：向主会话返回 ≤5 行轻量摘要（备选方案数、关键 Trade-off、与整体架构一致性）

**合并 architect**：每个维度各派一个合并 architect
- 读取 `decision-<维度>-draft-*.md`，整合为维度决策文档
- **输出**：用 Write 写入 `docs/architecture/decisions/decision-<维度>.md`

### 3.3 并发规则

- 无依赖的维度可并行处理，汇总所有维度的 agent 总数
- 若超过 `agent.max_concurrent`，使用滑动窗口策略（初始启动 5 个，每完成一个立即补位）
- **维度内 researcher → architect 有依赖**，必须串行；维度间无依赖，可并行
- 禁止以并发限制为由减少维度数或降低复杂度判定

**步骤 3 出口标准**（每个维度文档）：
- [ ] 每个维度有 ≥2 个备选方案
- [ ] 每个方案有明确的 Trade-off 分析
- [ ] 各维度方案与 decision-overall.md 不冲突
- [ ] 文档已按模板结构写入 `decision-<维度>.md`
- [ ] 文件已验证存在

### 3.4 评审修正循环

> **准入条件**：步骤 3 出口标准已通过（所有维度文档已写入并验证存在）
> **核心约束**：按 SKILL.md「标准评审修正循环」执行，本文只声明本阶段特有参数和规则。

**评审配置**（按维度分别配置）：

每个维度 ≥2 个 reviewer，并行独立评审：
- 主会话基于域特征动态决定 reviewer 角色组合
- 评审维度必须包含：**跨维度一致性**（检查该维度方案与其他维度是否存在冲突）
- **主会话职责**：在派遣评审 agent 的 prompt 中注入文档的系统上下文

| 参数 | 值 | 说明 |
|------|-----|------|
| 评估对象数 | 备选方案数 | 各维度 decision-<维度>.md 中的方案数 |
| 缺陷密度门槛 | ≤ 1.5 分/方案 | 见 SKILL.md「缺陷密度门槛标定依据」 |
| \> 30 处回退目标 | 仅该维度回退到步骤 3.1 | 重新决定 agent 配置，其他维度不受影响 |

**成功退出条件**（同时满足）：
- 所有维度均已通过独立评审
- 各维度无 CRITICAL 问题
- 各维度缺陷密度 ≤ 1.5 分/方案
- 各 `decision-<维度>.md` 末尾已写入 `**评审状态**: ✅ PASS` 标记
- 所有 HIGH 问题已评估：接受修正 / 接受延期 / 拒绝
- **跨维度一致性已验证**（无冲突、接口契约一致、上游输出与下游输入匹配）

---

## 第 2 阶段出口标准

- [ ] 步骤 1 出口标准已通过（整体架构方案 + 评审通过）
- [ ] 步骤 2 出口标准已通过（维度划分明确）
- [ ] 步骤 3 出口标准已通过（各维度方案 + 评审通过）
- [ ] 所有 CRITICAL 问题已修正
- [ ] 所有 HIGH 问题已评估
- [ ] 各文档末尾已写入 `✅ PASS` 标记

> 出口条件全部满足后，向用户汇报各步骤缺陷密度和问题处理摘要，等待确认后进入第 3 阶段。
