# 第 3 阶段：Scenario 挖掘与特性域定稿

**准入条件**：第 2 阶段完成，Actor-Feature 已定稿（无 CRITICAL 问题 + 缺陷密度 ≤ 1.5 分/Feature）
**产出文件**：`docs/requirements/<feature-domain>.md`（各特性域文档）

---

## 步骤 1：任务解构与 Scenario 挖掘（分域并行）

> **Plan 阶段内联**：第 3 阶段命中上调条件时为「高」复杂度，需先解构再发散。未命中时按「中等」复杂度执行，跳过 Plan 阶段，主会话直接派遣 1-2 个 product agent。

**任务解构**（仅命中上调条件时执行）：
1. 派遣 **1 个 product agent** 读取 `.claude/templates/req-feature.md`，识别各章节的决策权重分布
2. 分析系统上下文（该特性域在产品中的位置、与 product-spec.md 的依赖关系、可替换性）
3. 决定 agent 数量（基于高复杂度下限，≥3；按分析类型切分：正常路径/故障异常路径/运维扩展路径）
4. 设计切分维度，分配视角约束、列出关键假设、识别评审视角缺口
5. 产出调度方案（并行产出 agent 配置 + 评审 agent 配置 + 整合策略）
6. 产出以结构化文本形式在对话中输出

**Plan 禁止事项**：
- 不产出深度分析内容
- 不预设最终结论或倾向性方案

**主会话职责**：原样执行 product 的调度方案，不做修改。若对方案有疑问，与用户确认或重新派遣 plan agent。

**Scenario 挖掘**：
1. 主会话读取 `product-spec.md`（Actor-Feature 终稿）作为统一输入源
2. 按 domain 拆分，无依赖的 domain 并行处理
3. **每个 domain 并行启动 product agent**：
   - 未命中上调条件（中等）：1-2 个 product agent，按正常路径和故障路径分工
   - 命中上调条件（高）：≥3 个 product agent，按分析类型切分：
     - product（关注正常路径）：分析用户核心业务流程、happy path
     - product（关注故障/异常路径）：分析错误处理、边界条件、降级策略
     - product（关注运维/扩展路径）：分析配置变更、升级、监控、集成
4. 每个 agent 基于定稿的 Actor-Feature 挖掘 Scenario
5. **所有内容结构严格遵循 `.claude/templates/req-feature.md` 模板**
6. 量化非功能需求

**步骤 1 出口标准**（每个 domain 文档）：
- [ ] 文档已按 `req-feature.md` 模板结构写入
- [ ] 每个 Scenario 有明确的触发条件、执行步骤、预期结果
- [ ] 每个 Scenario 的验收标准可量化、可独立验证
- [ ] 非功能需求有量化指标（具体数字 + 验收方法）
- [ ] 文档已写入 `docs/requirements/<feature-domain>.md`

**步骤 1 缺陷密度评审**（按 domain）：

主会话基于步骤 2 评审结果计算缺陷密度。

```
缺陷密度 = 所有问题的分数之和 / Feature 数量
问题分值：CRITICAL=10分, HIGH=3分, MEDIUM=1分, LOW=0.1分
```

**进入门槛**：
- 无 CRITICAL 问题
- 缺陷密度 ≤ 2.0 分/Feature

---

## 步骤 2：独立评审（评审修正循环起点）

**准入条件**：特性域文档初稿已写入文件

1. **并行启动 reviewer** 执行**独立评审**：
   - 未命中上调条件（中等）：≥1 个 reviewer（product-reviewer 或 architect-reviewer）
   - 命中上调条件（高）：product-reviewer + architect-reviewer 并行评审
   - **主会话职责**：在派遣评审 agent 的 prompt 中必须注入文档的系统上下文——本文档在需求体系中的位置（特性域 Scenario 规格，基于 product-spec.md 中的 Feature 展开）、重要性（定义验收标准和具体用例，直接影响开发和测试）、可替换性（修正成本评估）
2. 质疑点数量要求：按特性域复杂度（简单≥3、中等≥5、复杂≥7）

**步骤 2 出口标准**：
- [ ] product-reviewer 和 architect-reviewer 均完成独立评审
- [ ] 质疑点数量达标
- [ ] 所有质疑点已按 CRITICAL/HIGH/MEDIUM/LOW 分级标注

**评审纪要写作规范**（由主会话执行，写入文档时遵守）：
- 评审记录章节 ≤ 200 字
- 仅保留 reviewer 名称、结论、遗留问题数及分类
- 详细评审意见留存对话上下文，不写入正式文档

---

## 步骤 3：评审修正定稿

按 domain 分别评分。按「通用规范」标准评审修正循环执行，特殊配置：

- **修正 agent**：product
- **复核**：修正后重新启动独立评审（product-reviewer + architect-reviewer）
- **特殊终止条件**：所有 CRITICAL 已修正 + 所有 HIGH 已修正或有明确处理方案 + 双 reviewer 均已完成独立评审 + 各特性域缺陷密度 ≤ 1.5 分/Feature

**步骤 3 缺陷密度评审**（按 domain）：

主会话基于步骤 2 评审结果计算缺陷密度。

```
缺陷密度 = 所有问题的分数之和 / Feature 数量
问题分值：CRITICAL=10分, HIGH=3分, MEDIUM=1分, LOW=0.1分
```

**进入门槛**：
- 无 CRITICAL 问题
- 缺陷密度 ≤ 1.5 分/Feature

---

## 第 3 阶段出口标准

- [ ] 所有 CRITICAL 问题已修正
- [ ] 所有 HIGH 问题已评估：接受修正 / 接受延期 / 拒绝
- [ ] product-reviewer 和 architect-reviewer 均已完成独立评审
- [ ] 各特性域缺陷密度 ≤ 1.5 分/Feature
- [ ] 验收标准可量化、可独立验证
- [ ] 非功能需求有量化指标
- [ ] 文档已写入并验证存在
- [ ] 文档中无子系统内部模块名，纯用户视角

---

## 自动推进规则

- 各特性域缺陷密度 ≤ 1.5 分/Feature → **确认后推进**（向用户汇报结果摘要，等待用户确认后进入第 4 阶段）
- 缺陷密度 1.5-2.5 分/Feature → 自动再修正一次
- 缺陷密度 > 2.5 分/Feature 或有 CRITICAL 问题 → 等待人工决策
