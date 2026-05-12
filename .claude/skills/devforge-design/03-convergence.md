# 第 3 阶段：评估收敛与文档定稿

**准入条件**：第 2 阶段所有决策文档通过评审（无 CRITICAL + 缺陷密度达标）
**产出文件**：
- `docs/architecture/adr.md`（ADR 索引）
- `docs/architecture/design.md`（系统总纲，定稿）
- `docs/architecture/<subsystem-en>/design.md`（各子系统架构）

---

## 步骤 1：ADR 收敛

**复杂度**：极高（不可逆决策记录）
**产出文件**：`docs/architecture/adr.md`

### 1.1 主会话决定 agent 配置

主会话直接决策派遣配置（不委托 plan agent 做任务解构）：

1. 读取 `docs/architecture/decisions/` 下所有决策文档（仅 ✅ PASS 文件）
2. 读取 `.claude/templates/arch-adr.md`，明确模板章节结构
3. **决定 agent 配置**：
   - **architect 数量**：极高复杂度下限 ≥5（阶段总 agent 数）
   - **视角切分**：基于第 2 阶段决策文档的分歧点和不可逆决策点动态产出 ≥5 个互补视角
     - 视角切分遵循 SKILL.md「视角切分原则」
   - **reviewer 配置**：≥3 个（极高复杂度下限），角色组合由主会话动态决定

### 1.2 并行启动 architect

1. **并行启动 ≥5 个 architect agent**（遵守 SKILL.md「Agent 并发控制」滑动窗口）：
   - 各自从分配的视角独立提炼 ADR（基于第 2 阶段决策文档）
   - 重点识别**不可逆决策**和**高成本决策**，确保 ADR 完整性
   - **写入文件**：`docs/architecture/adr-draft-{view}.md`
   - **返回摘要**：向主会话返回 ≤5 行轻量摘要（识别 ADR 数、不可逆决策数、关键 rationale 要点）

2. 若 agent 数超过 `agent.max_concurrent`，使用滑动窗口策略

### 1.3 合并 architect

**主会话确认所有 architect 完成后**，派一个合并 architect：

- **输入**：`adr-draft-*.md`
- **执行**：
  - 读取所有 draft，按 `.claude/templates/arch-adr.md` 模板结构整合
  - 合并各视角识别的 ADR，去重并按 ADR 编号组织
  - 每个 ADR 标注：决策标题、状态（Accepted/Proposed/Superseded）、是否不可逆、决策 rationale、与决策文档的追溯关系
  - 在文档开头增加「ADR 索引摘要」章节，按子系统/技术域分组
- **输出**：用 Write 写入 `docs/architecture/adr.md`
- **返回**：向主会话返回摘要（合并后 ADR 数、不可逆决策数、与决策文档对应关系）

**步骤 1 出口标准**：
- [ ] 所有关键决策均已记录为 ADR
- [ ] 每个 ADR 有明确的 rationale（"为什么"论证）
- [ ] 不可逆决策已显式标注
- [ ] ADR 与第 2 阶段决策文档无冲突
- [ ] 文档已写入 `docs/architecture/adr.md` 并验证存在
- [ ] **draft 已清理**：执行 `rm docs/architecture/adr-draft-*.md`，并用 `ls` 确认无残留（按 SKILL.md「draft 清理约束」）

### 1.4 评审修正循环

> **前置条件**：步骤 1 出口标准已通过（adr.md 已写入并通过完整性检查）
> **核心约束**：评审修正循环按 SKILL.md「标准评审修正循环」执行，本文只声明本阶段特有参数和规则，不得重复标准循环内容。

### 1.4.1 评审配置

**≥3 个 reviewer，并行独立评审** ADR 索引（同一类型可多实例做交叉验证）：

- 主会话基于 ADR 涉及的技术域动态决定 reviewer 角色组合
- 评审维度必须覆盖：技术可行性、决策一致性、ADR 完整性
- **特异性子维度由主会话基于本次产品的 `domain_specific` / `quality_attributes.priorities` 前两项 / Non-Goals 与 ADR 涉及的不可逆决策动态注入到派遣 prompt**，详见 SKILL.md「视角切分原则 - 评审视角」三层结构

> **主会话职责**：在派遣评审 agent 的 prompt 中注入文档的系统上下文——本文档在架构体系中的位置（ADR 索引，记录所有关键架构决策及其依据）、重要性（ADR 是架构决策的最终记录，影响所有子系统的实现方向，部分 ADR 涉及不可逆决策）、可替换性（修正成本评估，ADR 修正成本极高，部分决策不可逆）。

### 1.4.2 独立评审

每个 reviewer agent：
- 读取 `docs/architecture/adr.md` 执行评审
- 将评审意见追加到 `docs/architecture/adr-review.md`
- 向主会话返回数字摘要：{issues: N, density: X, critical: Y}

主会话从数字摘要判定通过/修正/回退，不读取完整评审内容。

### 1.4.3 验证与修正

> 按 SKILL.md「标准评审修正循环」步骤 2-7 执行。本阶段特有参数声明如下：

| 参数 | 值 | 说明 |
|------|-----|------|
| 评估对象数 | ADR 条目数 | adr.md 中的 ADR 数量 |
| 缺陷密度门槛 | **≤ 0.5 分/ADR** | 不可逆决策从严：见 SKILL.md「缺陷密度门槛标定依据」 |
| 修正 agent | architect agent | 修正后更新 `docs/architecture/adr.md` |
| \> 30 处回退目标 | 回退到步骤 1.1 | 重新决定 agent 配置和视角切分 |

**成功退出条件**（同时满足）：
- 所有 reviewer 均已完成独立评审
- 无 CRITICAL 问题
- 缺陷密度 ≤ 0.5 分/ADR
- `adr.md` 末尾已写入 `**评审状态**: ✅ PASS` 标记（按 SKILL.md「评审状态标记契约」格式）
- 所有 HIGH 问题已评估：接受修正 / 接受延期 / 拒绝

---

## 步骤 2：系统架构总纲定稿

**复杂度**：极高（系统级架构定稿）
**产出文件**：`docs/architecture/design.md`（首次定稿）

### 2.1 主会话决定 agent 配置

主会话直接决策派遣配置：

1. 读取 `docs/architecture/decisions/` 所有决策文档、`docs/architecture/adr.md`
2. 读取 `.claude/templates/arch-system.md`，明确模板章节结构
3. **决定 agent 配置**：
   - **architect 数量**：极高复杂度下限 ≥5（阶段总 agent 数）
   - **视角切分**：基于产品上下文动态产出 ≥5 个互补视角，遵循 SKILL.md「视角切分原则」
   - **reviewer 配置**：≥3 个（极高复杂度下限）

### 2.2 并行启动 architect

1. **并行启动 ≥5 个 architect agent**（遵守 SKILL.md「Agent 并发控制」）：
   - 各自从分配的视角独立定稿系统总纲
   - **写入文件**：`docs/architecture/design-draft-{view}.md`
   - **返回摘要**：向主会话返回 ≤5 行轻量摘要（章节覆盖度、子系统数、关键决策映射）

### 2.3 合并 architect

派一个合并 architect：
- **输入**：`design-draft-*.md`
- **执行**：
  - 读取所有 draft，按 `.claude/templates/arch-system.md` 模板结构整合
  - 确保各子系统职责明确无重叠或遗漏
  - 数据流正常路径 + 错误传播路径完整定义
  - 与 `adr.md` 各 ADR 决策一致
  - 故障处理覆盖：故障模式、降级策略、恢复流程已定义
- **输出**：用 Write 写入（覆盖）`docs/architecture/design.md`
- **返回**：向主会话返回摘要（章节数、子系统数、与 ADR 对应关系数）

**步骤 2 出口标准**：
- [ ] 各子系统职责明确，无重叠或遗漏
- [ ] 数据流正常路径 + 错误传播路径已定义
- [ ] 与 `adr.md` 决策一致
- [ ] 故障模式、降级策略、恢复流程已定义
- [ ] 文档已写入 `docs/architecture/design.md` 并验证存在
- [ ] **draft 已清理**：执行 `rm docs/architecture/design-draft-*.md`，并用 `ls` 确认无残留（按 SKILL.md「draft 清理约束」）

### 2.4 评审修正循环

> **前置条件**：步骤 2 出口标准已通过（design.md 已写入并通过完整性检查）
> **核心约束**：评审修正循环按 SKILL.md「标准评审修正循环」执行，本文只声明本阶段特有参数和规则，不得重复标准循环内容。

### 2.4.1 评审配置

**≥3 个 reviewer，并行独立评审**系统架构总纲（同一类型可多实例做交叉验证）：

- 主会话基于产品上下文动态决定 reviewer 角色组合
- 评审维度必须覆盖：子系统边界、数据流完整性、与 ADR 一致性、故障处理覆盖度
- **特异性子维度由主会话基于本次产品的 `domain_specific` / `quality_attributes.priorities` 前两项 / Non-Goals 动态注入到派遣 prompt**，详见 SKILL.md「视角切分原则 - 评审视角」三层结构

> **主会话职责**：在派遣评审 agent 的 prompt 中注入文档的系统上下文——本文档在架构体系中的位置（系统架构总纲，定义全局子系统划分、接口契约和数据流）、重要性（是后续所有子系统设计和实现的最高层级参照）、可替换性（修正成本评估，架构总纲变更影响所有子系统）。

### 2.4.2 独立评审

每个 reviewer agent：
- 读取 `docs/architecture/design.md` 执行评审
- 将评审意见追加到 `docs/architecture/design-review.md`
- 向主会话返回数字摘要：{issues: N, density: X, critical: Y}

主会话从数字摘要判定通过/修正/回退，不读取完整评审内容。

### 2.4.3 验证与修正

> 按 SKILL.md「标准评审修正循环」步骤 2-7 执行。本阶段特有参数声明如下：

| 参数 | 值 | 说明 |
|------|-----|------|
| 评估对象数 | 子系统数 + 全局章节数 | design.md 中子系统定义章节 + 跨子系统全局章节（数据流/一致性/部署拓扑等） |
| 缺陷密度门槛 | ≤ 1.5 分/评估对象 | 见 SKILL.md「缺陷密度门槛标定依据」 |
| 修正 agent | architect agent | 修正后更新 `docs/architecture/design.md` |
| \> 30 处回退目标 | 回退到步骤 2.1 | 重新决定 agent 配置和视角切分 |

**成功退出条件**（同时满足）：
- 所有 reviewer 均已完成独立评审
- 无 CRITICAL 问题
- 缺陷密度 ≤ 1.5 分/评估对象
- `design.md` 末尾已写入 `**评审状态**: ✅ PASS` 标记（按 SKILL.md「评审状态标记契约」格式）
- 所有 HIGH 问题已评估：接受修正 / 接受延期 / 拒绝

---

## 步骤 3：子系统架构定稿

**复杂度**：高（按子系统）
**产出文件**：`docs/architecture/<subsystem-en>/design.md`（每个子系统一个目录，kebab-case 英文目录名）

### 3.1 主会话决定 agent 配置

主会话直接决策派遣配置：

1. 读取 `docs/architecture/design.md`（系统总纲，已定稿）的子系统列表
2. 主会话从 `design.md#子系统列表`确定每个子系统的「英文标识」（kebab-case，如 `storage-engine`、`metadata-service`）
3. 读取 `.claude/templates/arch-subsystem.md`，明确模板章节结构
4. **决定 agent 配置**：
   - **每个子系统的 architect 数量**：高复杂度下限 ≥3
   - **视角切分**：基于该子系统的具体性质动态决定，遵循 SKILL.md「视角切分原则」
   - **reviewer 配置**：每个子系统 ≥2 个 reviewer

### 3.2 子系统并行处理

1. 按子系统拆分，无依赖的子系统并行处理
2. **每个子系统并行启动 ≥3 个 architect agent**（遵守 SKILL.md「Agent 并发控制」）：
   - 各自从分配的视角独立设计该子系统
   - **写入文件**：`docs/architecture/<subsystem-en>/design-draft-{view}.md`
   - **返回摘要**：向主会话返回 ≤5 行轻量摘要（功能路径数、故障模式数、接口契约数）

3. 若汇总所有子系统的 agent 总数超过 `agent.max_concurrent`，使用滑动窗口策略

### 3.3 合并 architect

每个子系统各派一个合并 architect：
- **输入**：对应子系统的 `<subsystem-en>/design-draft-*.md`
- **执行**：
  - 读取所有 draft，按 `.claude/templates/arch-subsystem.md` 模板结构整合
  - 核心数据流、状态转换、接口契约完整
  - 故障模式、降级策略、恢复流程已定义
  - 边界条件覆盖（输入边界、资源边界、并发边界）
  - 与系统总纲接口契约和 ADR 技术决策一致
  - 运维接口、监控点、日志规范已定义
- **输出**：用 Write 写入 `docs/architecture/<subsystem-en>/design.md`
- **返回**：向主会话返回摘要（章节数、接口契约数、故障模式数）

**步骤 3 出口标准**（每个子系统文档）：
- [ ] 核心数据流、状态转换、接口契约完整
- [ ] 故障模式、降级策略、恢复流程已定义
- [ ] 边界条件已覆盖
- [ ] 与系统总纲、ADR 一致
- [ ] 运维接口、监控点、日志规范已定义
- [ ] 文档已写入 `docs/architecture/<subsystem-en>/design.md` 并验证存在
- [ ] **draft 已清理**：执行 `rm docs/architecture/<subsystem-en>/design-draft-*.md`，并用 `ls` 确认无残留（按 SKILL.md「draft 清理约束」）

### 3.4 评审修正循环

> **前置条件**：步骤 3 出口标准已通过（所有子系统文档已写入并通过完整性检查）
> **核心约束**：评审修正循环按 SKILL.md「标准评审修正循环」执行，本文只声明本阶段特有参数和规则，不得重复标准循环内容。**按子系统分别判定**：每个子系统独立走判断→修正→复核循环，状态互不影响。

### 3.4.1 评审配置（按子系统分别配置）

每个子系统 **≥2 个 reviewer，并行独立评审**（同一类型可多实例做交叉验证）：
- 主会话基于该子系统的性质动态决定 reviewer 角色组合
- 评审维度必须覆盖：功能完整性、故障处理、与总纲/ADR 一致性
- **特异性子维度由主会话基于该子系统对应的 `domain_specific` 约束 / `quality_attributes.priorities` 前两项 / Non-Goals 与该子系统的具体性质动态注入到派遣 prompt**，详见 SKILL.md「视角切分原则 - 评审视角」三层结构

> **主会话职责**：在派遣评审 agent 的 prompt 中注入文档的系统上下文——本文档在架构体系中的位置（子系统架构文档，定义单一子系统内部设计）、重要性（子系统可独立重构，但接口契约变更可能影响其他子系统）、可替换性（修正成本评估，子系统内部设计修正成本相对可控）。

### 3.4.2 独立评审

每个 reviewer agent：
- 读取对应子系统 `<subsystem-en>/design.md` 执行评审
- 将评审意见追加到 `<subsystem-en>/design-review.md`
- 向主会话返回数字摘要：{issues: N, density: X, critical: Y}

主会话从数字摘要判定通过/修正/回退，不读取完整评审内容。

### 3.4.3 验证与修正

> 按 SKILL.md「标准评审修正循环」步骤 2-7 执行。本阶段特有参数声明如下：

| 参数 | 值 | 说明 |
|------|-----|------|
| 评估对象数 | 子系统内章节数 | 每个 `<subsystem-en>/design.md` 中的章节数（功能流/故障/接口/运维等） |
| 缺陷密度门槛 | ≤ 1.5 分/章节 | 见 SKILL.md「缺陷密度门槛标定依据」 |
| 修正 agent | architect agent | 修正后更新对应 `<subsystem-en>/design.md` |
| \> 30 处回退目标 | 仅该子系统回退到步骤 3.1 | 重新决定 agent 配置，其他子系统不受影响 |

**并发规则**：若所有子系统的 reviewer 总数超过 `agent.max_concurrent`，使用滑动窗口策略。

**成功退出条件**（同时满足）：
- 所有子系统均已通过独立评审
- 各子系统无 CRITICAL 问题
- 各子系统缺陷密度 ≤ 1.5 分/章节
- 各 `<subsystem-en>/design.md` 末尾已写入 `**评审状态**: ✅ PASS` 标记（按 SKILL.md「评审状态标记契约」格式）
- 所有 HIGH 问题已评估：接受修正 / 接受延期 / 拒绝

---

## 第 3 阶段出口标准

- [ ] 步骤 1 出口标准已通过（ADR 收敛 + 评审通过，缺陷密度 ≤ 0.5/ADR）
- [ ] 步骤 2 出口标准已通过（系统总纲定稿 + 评审通过，缺陷密度 ≤ 1.5/子系统）
- [ ] 步骤 3 出口标准已通过（所有子系统定稿 + 评审通过，缺陷密度 ≤ 1.5/章节）
- [ ] 所有 CRITICAL 问题已修正
- [ ] 所有 HIGH 问题已评估
- [ ] `adr.md`、`design.md`、各子系统文档末尾均有 `✅ PASS` 标记

> 出口条件全部满足后，向用户汇报各步骤缺陷密度和问题处理摘要，等待确认后进入第 4 阶段（维护模式）。
