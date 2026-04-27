# 第 2 阶段：Actor-Feature 识别与定稿

**准入条件**：第 1 阶段完成，标杆研究通过评审（≥ 0.80）
**产出文件**：`docs/requirements/product-spec.md`（Actor-Feature 章节定稿）

---

## Step 1：任务解构与 Actor 识别

> **Plan 阶段内联**：第 2 阶段为极高复杂度（核心 Feature / Actor 定义），必须先解构再发散。

**任务解构**：
1. 派遣 **1 个 product-manager agent** 读取 `.claude/templates/req-product-spec.md`
2. 识别各章节的决策权重分布（Actor 定义、Feature 定义、Scenario 设计各占比）
3. 确认切分维度、分配视角约束、列出关键假设、识别评审视角缺口
4. 产出以结构化文本形式在对话中输出，不写入文件

**Actor 识别**：
1. **product-manager** 基于产品定位和标杆研究洞察，识别所有 Actor
2. **并行启动 researcher** 补充竞品 Actor 映射表
3. 每个 Actor 明确：类型、职责、交互方式、关注点
4. **写入文件**

**Step 1 出口标准**：
- [ ] Actor 列表非空，至少识别出 1 个核心 Actor
- [ ] 每个 Actor 已明确：类型、职责、交互方式、关注点
- [ ] 隐性 Actor 检查已完成（安全审计/合规检查/运维值班/第三方集成/监控告警系统）
- [ ] 文档已按模板结构写入 `product-spec.md#actors`
- [ ] 文件已验证存在（`ls`/`wc` 确认）

**Step 1 置信度评分**：

| 维度 | 权重 | 评分标准 |
|------|------|----------|
| Actor 完整性 | 40% | 无遗漏隐性 Actor，核心 Actor 已识别 |
| 职责清晰度 | 30% | 每个 Actor 的类型/职责/交互方式/关注点已明确 |
| 交互关系明确度 | 30% | Actor 间交互关系已初步梳理 |

**进入门槛：≥ 0.80**

---

## Step 2：Feature 识别（多 agent 并行）

**产出文件**：`docs/requirements/product-spec.md`（草稿状态）

1. **并行启动 3 个 product-manager agent**，各自从不同用户场景角度围绕 Actor 核心目标独立推导 Feature 列表
   - 禁止用一个 agent "内部发散多个方案"替代多个 agent 独立产出
   - 视角切分由任务解构的 product-manager agent 确定
   - **3 个 agent 的视角区分**（必须按以下维度区分）：
     - `product-manager`（终端用户场景视角）
     - `product-manager`（运维治理场景视角）
     - `product-manager`（集成扩展场景视角）
2. 主会话整合三个 agent 的 Feature 列表，去重并客观记录冲突
3. 每个 Feature 记录：一句话价值摘要、涉及 Actor、归属特性域、优先级
4. 产出 Feature 间依赖关系矩阵
5. **并行启动 architect** 评估各 Feature 实现复杂度
6. Feature 价值论证必须是推导式，禁止"矩阵后直接给结论"
7. **读取 `.claude/templates/req-product-spec.md` 模板**，写入 `product-spec.md`

**Step 2 出口标准**：
- [ ] Feature 列表非空，覆���所有已识别 Actor 的核心目标
- [ ] 每个 Feature 已记录：一句话价值摘要、涉及 Actor、归属特性域、优先级
- [ ] Feature 间依赖关系矩阵已产出
- [ ] 价值论证为推导式，非直接给结论
- [ ] 文档已按模板结构写入 `product-spec.md`
- [ ] 文档状态标记为"第 2 阶段 Step 2 完成（Feature 已识别，待评审）"

**Step 2 置信度评分**：

| 维度 | 权重 | 评分标准 |
|------|------|----------|
| Feature 覆盖度 | 30% | 覆盖所有已识别 Actor 的核心目标，无遗漏关键路径 |
| 价值论证质量 | 30% | 每个 Feature 有"做什么+为什么"的推导式论证 |
| 依赖关系清晰��� | 20% | Feature 间依赖矩阵完整，无循环依赖 |
| 与标杆对齐度 | 20% | Feature 设计体现标杆研究洞察 |

**进入门槛：≥ 0.85**（Actor-Feature 定义为需求核心，涉及产品边界）

---

## Step 3：独立评审（评审修正循环起点）

**准入条件**：`product-spec.md` 草稿已写入文件

1. **并行启动 `pm-reviewer` 和 `architect-reviewer`** 执行**独立评审**
   - `pm-reviewer` 覆盖 3 个 product-manager agent 的用户场景视角差异
   - `architect-reviewer` 从跨子系统边界和实现可行性视角审视 Feature 列表
2. 质疑点数量要求：按特性域复杂度（简单≥3、中等≥5、复杂≥7）

**Step 3 出口标准**：
- [ ] pm-reviewer 和 architect-reviewer 均完成独立评审
- [ ] 质疑点数量达标
- [ ] 所有质疑点已按 CRITICAL/HIGH/MEDIUM/LOW 分级标注
- [ ] 评审记录章节 ≤ 200 字

---

## Step 4：评审修正定稿

评审完成后**不等待用户确认**，由 product-manager 自动决策并执行修正。

按 `common.md` 标准评审修正循环执行，特殊配置：

- **修正 agent**：product-manager
- **少量修正**（<5 处）：1 个 product-manager agent
- **中量修正**（5-15 处）：2 个 product-manager 分块并行修正 + 主会话整合
- **大量修正**（>15 处）：回退到 Step 2 重新执行多 agent 并行发散

**自动决策规则**：CRITICAL 必须修正 → HIGH 默认修正 → MEDIUM 评估后决定 → LOW 可延期

**Step 4 置信度评分**：

| 维度 | 权重 | 评分标准 |
|------|------|----------|
| CRITICAL 修正完整性 | 40% | 所有 CRITICAL 问题已修正 |
| HIGH 问题处理质量 | 30% | 所有 HIGH 问题已修正或有明确��理方案 |
| 评审回应充分性 | 20% | 所有质疑点有明确回应 |
| 文档一致性 | 10% | 修正后与 product-spec.md 其他章节无冲突 |

**进入门槛：≥ 0.85**

---

## 第 2 阶段出口标准

- [ ] 所有 CRITICAL 问题已修正
- [ ] 所有 HIGH 问题已评估：接受修正 / 接受延期 / 拒绝
- [ ] pm-reviewer 和 architect-reviewer 均给出"通过"或"有条件通过"
- [ ] 各特性域置信度 ≥ 0.85
- [ ] 文档已写入并验证存在
- [ ] 文档状态标记为"第 2 阶段完成（Actor-Feature 已定稿）"

---

## 自动推进规则

- 所有 CRITICAL 已修正 + 所有 HIGH 已修正或有明确处理方案 + 双 reviewer "通过"或"有条件通过" + 置信度 ≥ 0.85 → **确认后推进**
- 置信度 0.75-0.84 → 自动再修正一次
- 置信度 < 0.75 → **等待人工决策**
