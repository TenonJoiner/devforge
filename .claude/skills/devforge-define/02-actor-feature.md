# 第 2 阶段：Actor-Feature 识别与定稿

**准入条件**：第 1 阶段完成，标杆研究通过评审（≥ 0.80）
**产出文件**：`docs/requirements/product-spec.md`（Actor-Feature 章节定稿）

---

## 步骤 1：任务解构与 Actor 识别

> **Plan 阶段内联**：第 2 阶段为极高复杂度（核心 Feature / Actor 定义），必须先解构再发散。

**任务解构**：
1. 派遣 **1 个 product agent** 读取 `.claude/templates/req-product-spec.md`
2. 识别各章节的决策权重分布（Actor 定义、Feature 定义、Scenario 设计各占比）
3. 确认切分维度、分配视角约束、列出关键假设、识别评审视角缺口
4. 产出调度方案：（1）并行产出 agent 配置（角色 + 视角约束 + 负责维度）；（2）评审 agent 配置（基于盲区分析，≥3 个不同角色 reviewer）；（3）整合策略（合并规则 + 冲突处理）
5. 产出以结构化文本形式在对话中输出，不写入文件

**Actor 识别**：
1. **并行启动 3 个 product agent**，各自从不同关注视角独立识别 Actor：
   - product（关注终端用户场景）：分析终端用户的核心业务流程、交互方式、易用性需求，识别面向用户的 Actor
   - product（关注运维治理场景）：分析运维人员的监控、告警、故障恢复、配置管理需求，识别面向运维的 Actor
   - product（关注安全合规场景）：分析安全审计、权限管控、合规认证、数据隐私需求，识别面向安全与合规的 Actor
2. **并行启动 researcher** 补充竞品 Actor 映射表
3. 主会话等待所有 agent 完成后，合并 Actor 列表，去重并记录冲突
4. 每个 Actor 明确：类型、职责、交互方式、关注点
5. **写入文件**

**步骤 1 出口标准**：
- [ ] Actor 列表非空，至少识别出 1 个核心 Actor
- [ ] 每个 Actor 已明确：类型、职责、交互方式、关注点
- [ ] 隐性 Actor 检查已完成（安全审计/合规检查/运维值班/第三方集成/监控告警系统）
- [ ] 文档已按模板结构写入 `product-spec.md#actors`
- [ ] 文件已验证存在（`ls`/`wc` 确认）

**步骤 1 置信度评分**：

| 维度 | 权重 | 评分标准 |
|------|------|----------|
| Actor 完整性 | 40% | 无遗漏隐性 Actor，核心 Actor 已识别 |
| 职责清晰度 | 30% | 每个 Actor 的类型/职责/交互方式/关注点已明确 |
| 交互关系明确度 | 30% | Actor 间交互关系已初步梳理 |

**进入门槛：≥ 0.80**

---

## 步骤 2：Feature 识别（多 agent 并行）

**产出文件**：`docs/requirements/product-spec.md`（草稿状态）

1. **并行启动 ≥5 个 agent**（极高复杂度下限：≥5）：
   - **4 个 product**：各自从不同用户场景角度围绕 Actor 核心目标独立推导 Feature 列表
     - product（关注终端用户场景）：分析终端用户的核心业务流程、交互方式、易用性需求，推导面向用户的 Feature
     - product（关注运维治理场景）：分析运维人员的监控、告警、故障恢复、配置管理需求，推导面向运维的 Feature
     - product（关注集成扩展场景）：分析第三方集成、API 设计、插件机制、扩展性需求，推导面向集成的 Feature
     - product（关注安全合规场景）：分析安全审计、权限管控、合规认证、数据隐私需求，推导面向安全的 Feature
   - **1 个 architect**：同步评估各 Feature 实现复杂度
   - 禁止用一个 agent "内部发散多个方案"替代多个 agent 独立产出
2. 主会话等待所有 5 个 agent 完成后，整合结果
3. 主会话整合五个 agent 的产出：
   - 合并三个 product 的 Feature 列表，去重并客观记录冲突
   - 每个 Feature 记录：一句话价值摘要、涉及 Actor、归属特性域、优先级
   - 产出 Feature 间依赖关系矩阵
   - 整合 architect 的实现复杂度评估
4. Feature 价值论证必须是推导式，禁止"矩阵后直接给结论"
5. **读取 `.claude/templates/req-product-spec.md` 模板**，写入 `product-spec.md`

**步骤 2 出口标准**：
- [ ] Feature 列表非空，覆盖所有已识别 Actor 的核心目标
- [ ] 每个 Feature 已记录：一句话价值摘要、涉及 Actor、归属特性域、优先级
- [ ] Feature 间依赖关系矩阵已产出
- [ ] 价值论证为推导式，非直接给结论
- [ ] 文档已按模板结构写入 `product-spec.md`
- [ ] 文档状态标记为"第 2 阶段 步骤 2 完成（Feature 已识别，待评审）"

**步骤 2 置信度评分**：

| 维度 | 权重 | 评分标准 |
|------|------|----------|
| Feature 覆盖度 | 30% | 覆盖所有已识别 Actor 的核心目标，无遗漏关键路径 |
| 价值论证质量 | 30% | 每个 Feature 有"做什么+为什么"的推导式论证 |
| 依赖关系清晰度 | 20% | Feature 间依赖矩阵完整，无循环依赖 |
| 与标杆对齐度 | 20% | Feature 设计体现标杆研究洞察 |

**进入门槛：≥ 0.85**（Actor-Feature 定义为需求核心，涉及产品边界）

---

## 步骤 3：独立评审（评审修正循环起点）

**准入条件**：`product-spec.md` 草稿已写入文件

1. **并行启动 `product-reviewer`、`architect-reviewer` 和 `project-reviewer`** 执行**独立评审**（极高复杂度 ≥3 reviewer）
   - **主会话职责**：在派遣评审 agent 的 prompt 中必须注入文档的系统上下文——本文档在需求体系中的位置（product-spec.md 总纲中的核心章节，定义产品边界和 Actor 权责）、重要性（影响后续所有 Feature 的优先级和验收标准定义）、可替换性（修正成本评估）
   - `product-reviewer`（关注用户价值与商业合理性）：质疑 Feature 的用户假设、优先级推导、Actor 遗漏、价值论证充分性
   - `architect-reviewer`（关注技术可行性与架构一致性）：质疑跨子系统边界、实现复杂度评估、依赖关系合理性、技术风险
   - `project-reviewer`（关注可交付性与迭代可行性）：质疑 Feature 粒度合理性、跨特性域依赖、与里程碑计划的对齐度
   - **三评审覆盖要求**：合计必须覆盖 Actor 遗漏、Feature 价值、依赖关系、优先级推导、可交付性维度，每个维度至少 1 个质疑，维度-主责映射如下：

     | 维度 | 主责 reviewer | 备责 reviewer |
     |------|-------------|-------------|
     | Actor 遗漏 | product-reviewer | project-reviewer |
     | Feature 价值 | product-reviewer | — |
     | 依赖关系 | architect-reviewer | project-reviewer |
     | 优先级推导 | project-reviewer | product-reviewer |
     | 可交付性 | project-reviewer | — |

     主责 reviewer 必须对该维度产出至少 1 个质疑，备责 reviewer 可补充但非强制。
2. 质疑点数量要求：按特性域复杂度（简单≥3、中等≥5、复杂≥7）

**步骤 3 出口标准**：
- [ ] product-reviewer、architect-reviewer 和 project-reviewer 均完成独立评审
- [ ] 质疑点数量达标
- [ ] 所有质疑点已按 CRITICAL/HIGH/MEDIUM/LOW 分级标注
- [ ] 评审记录章节 ≤ 200 字
- [ ] 三评审覆盖要求已满足（Actor 遗漏、Feature 价值、依赖关系、优先级推导、可交付性各至少 1 个质疑）

---

## 步骤 4：评审修正定稿

评审完成后**不等待用户确认**，由 product 自动决策并执行修正。

按「通用规范」标准评审修正循环执行，特殊配置：

- **修正 agent**：product
- **少量修正**（<10 处）：1 个 product agent
- **中量修正**（10-30 处）：2 个 product 分块并行修正 + 主会话整合
- **大量修正**（>30 处）：回退到 步骤 2 重新执行多 agent 并行发散

**自动决策规则**：CRITICAL 必须修正 → HIGH 默认修正 → MEDIUM 评估后决定 → LOW 可延期

**步骤 4 置信度评分**：

| 维度 | 权重 | 评分标准 |
|------|------|----------|
| CRITICAL 修正完整性 | 40% | 所有 CRITICAL 问题已修正 |
| HIGH 问题处理质量 | 30% | 所有 HIGH 问题已修正或有明确处理方案 |
| 评审回应充分性 | 20% | 所有质疑点有明确回应 |
| 文档一致性 | 10% | 修正后与 product-spec.md 其他章节无冲突 |

**进入门槛：≥ 0.85**

---

## 第 2 阶段出口标准

- [ ] 所有 CRITICAL 问题已修正
- [ ] 所有 HIGH 问题已评估：接受修正 / 接受延期 / 拒绝
- [ ] product-reviewer、architect-reviewer 和 project-reviewer 均给出"通过"或"有条件通过"
- [ ] 各特性域置信度 ≥ 0.85
- [ ] 文档已写入并验证存在
- [ ] 文档状态标记为"第 2 阶段完成（Actor-Feature 已定稿）"

---

## 自动推进规则

- 所有 CRITICAL 已修正 + 所有 HIGH 已修正或有明确处理方案 + 三 reviewer "通过"或"有条件通过" + 置信度 ≥ 0.85 → **确认后推进**
- 置信度 0.75-0.84 → 自动再修正一次
- 置信度 < 0.75 → **等待人工决策**
