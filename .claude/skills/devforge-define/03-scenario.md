# 第 3 阶段：Scenario 挖掘与特性域定稿

**准入条件**：第 2 阶段已通过出口标准（Actor-Feature 已定稿，无 CRITICAL 问题 + 缺陷密度达标）
**产出文件**：`docs/requirements/<feature-domain>.md`（各特性域文档）

---

## 步骤 1：Scenario 挖掘（分域并行）

**Scenario 挖掘**：
1. 主会话读取 `product-spec.md`（Actor-Feature 终稿）作为统一输入源
2. 按 `product-spec.md#Feature 总览` 中"归属特性域"字段对 Feature 分组（每个特性域 = 一个 domain，对应一个 `docs/requirements/<feature-domain>.md` 产出文件），无依赖的 domain 并行处理
3. **按 domain 分别判定复杂度，并行启动 product agent**（遵守 SKILL.md「Agent 并发控制」滑动窗口）：
   - 主会话对每个 domain 独立判定复杂度（综合评估以下因素，非二维布尔）：
     - 涉及 Actor 数量与权限复杂度
     - Feature 间的依赖关系密度
     - `domain-config.yaml` 中的系统规模与并发模式
     - 质量属性优先级是否将该 domain 放在关键路径上
     - 判定结果：**中等**（常规 Scenario 挖掘）或 **高**（需多视角并行深度展开）
   - 中等复杂度 domain：1-2 个 product agent，由主会话按需分工
   - 高复杂度 domain：≥3 个 product agent，视角切分由主会话根据该 domain 的**实际性质**动态决定（如按正常/故障/运维维度、按 Actor 角色维度、按时间阶段维度等），在派遣 prompt 中说明切分理由，禁止套用固定视角清单
   - **并发规则**：汇总所有 domain 的 agent 总数，若超 `agent.max_concurrent`，初始启动 5 个，每完成一个立即从待启动队列中补位下一个。禁止以并发限制为由减少 domain 数或降低复杂度判定
4. 每个 agent 基于定稿的 Actor-Feature 挖掘 Scenario
5. **所有内容结构严格遵循 `.claude/templates/req-feature.md` 模板**
6. 量化非功能需求
7. 主会话收集各 agent 产出，按模板整合为统一 domain 文档，写入 `docs/requirements/<feature-domain>.md`

**主会话职责**（步骤 1）：
- 读取 `product-spec.md`，按"归属特性域"字段对 Feature 分组，确定 domain 列表
- 对每个 domain 独立判定复杂度（综合评估 Actor 数量、依赖密度、规模与并发、质量关键路径等因素，非二维布尔）
- 按 domain 复杂度派遣 product agent，注入对应的视角约束
- 收集各 agent 产出，整合去重、处理冲突，按模板写入对应 domain 文件

**步骤 1 出口标准**（每个 domain 文档）：
- [ ] 文档已按 `req-feature.md` 模板结构写入
- [ ] 每个 Scenario 有明确的触发条件、执行步骤、预期结果
- [ ] 每个 Scenario 的验收标准可量化、可独立验证
- [ ] 非功能需求有量化指标（具体数字 + 验收方法）
- [ ] 文档已写入 `docs/requirements/<feature-domain>.md`

---

## 步骤 2：评审修正循环

> **准入条件**：步骤 1 出口标准已通过（所有 domain 文档已写入并验证存在）
> **核心约束**：按 SKILL.md「标准评审修正循环」执行，本文只声明本阶段特有参数和规则。

### 2.1 评审配置

**按 domain 分别配置 reviewer**（沿用步骤 1 已判定的复杂度）：

- 中等复杂度 domain：≥1 个 reviewer，以 product-reviewer 为主，architect-reviewer 可选辅助
- 高复杂度 domain：product-reviewer（主责）+ architect-reviewer（辅助）并行评审
- **主会话职责**：在派遣评审 agent 的 prompt 中注入文档的系统上下文——本文档在需求体系中的位置（特性域 Scenario 规格，基于 product-spec.md 中的 Feature 展开）、重要性（定义验收标准和具体用例，直接影响开发和测试）、可替换性（修正成本评估）

### 2.2 独立评审

主会话按评审配置派遣 reviewer（遵守 SKILL.md「Agent 并发控制」滑动窗口）。若所有 domain 的 reviewer 总数超过 `agent.max_concurrent`，初始启动 5 个，每完成一个立即补位下一个。

- **评审纪要写作规范**：参见 SKILL.md「评审纪要写作规范」

### 2.3 验证与修正

> 按 SKILL.md「标准评审修正循环」步骤 2-7 执行。**按 domain 分别判定**：每个 domain 独立走判断→修正→复核循环，状态互不影响。

| 参数 | 值 | 说明 |
|------|-----|------|
| 评估对象数 | Feature 数量 | 按 domain 内 Feature 数计算，各 domain 独立 |
| 缺陷密度门槛 | ≤ 1.5 分/Feature | 见 SKILL.md「缺陷密度门槛标定依据」 |
| 修正 agent | product agent | 修正后更新对应 domain 文档 |
| 修正后复核路径 | 回到 2.2 独立评审 | |
| \> 30 处回退目标 | 仅该 domain 回退到步骤 1 | 重新执行多 agent 并行发散，其他 domain 不受影响 |

**成功退出条件**（同时满足）：
- 所有 domain 均已通过独立评审
- 各 domain 无 CRITICAL 问题
- 各 domain 缺陷密度 ≤ 1.5 分/Feature
- 各特性域文档末尾已写入 `**评审状态**: ✅ PASS` 标记（按 SKILL.md「评审纪要写作规范」格式）
- 各 domain 所有 HIGH 问题已评估：接受修正 / 接受延期 / 拒绝

---

## 第 3 阶段出口标准

- [ ] 所有 domain 文档通过步骤 1 出口标准（文档内容完整性）
- [ ] 所有 domain 文档通过步骤 2 出口标准（评审质量达标）
- [ ] 文档中无子系统内部模块名，纯用户视角

> 出口条件全部满足后，向用户汇报各 domain 缺陷密度和问题处理摘要，等待确认后进入第 4 阶段。
