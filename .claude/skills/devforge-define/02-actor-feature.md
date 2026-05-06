# 第 2 阶段：Actor-Feature 识别与定稿

**准入条件**：第 1 阶段已完成并通过出口标准（无 CRITICAL 问题 + 缺陷密度达标）
**产出文件**：`docs/requirements/product-spec.md`（Actor-Feature 章节定稿）

---

## 步骤 1：Actor 识别

主会话按以下固定配置派遣 agent。

### Actor 识别配置

**两路独立并行，互补验证**：

**设计路径**（3-5 个 product）：
- **视角切分由主会话根据 domain-config.yaml 动态决定**：主会话读取 `primary_type`、`description`、已确认的标杆列表后，产出 ≥3 个互补的 Actor 识别视角，在派遣 prompt 中说明切分理由
  - 禁止套用固定视角清单（如"终端用户/运维/安全"），必须以本产品的实际特征为出发点
- 基于领域知识独立识别本产品 Actor
- **禁止读取标杆研究报告**，确保不因竞品分析而限制设计空间

**证据路径**（2-3 个 researcher）：
- 按竞品或角色维度切分（具体切分由主会话根据标杆列表动态决定）
- 读取 `docs/requirements/reference/`，提取竞品 Actor 映射表
- **不做本产品设计决策**，仅提供证据

### 合并规则

各路产出取并集，对比差异并标注理由：
- **交集确认**：多路同时命中的 Actor 直接收录
- **设计独有**：设计路径提出但证据路径未覆盖的 Actor，标注潜在遗漏理由（可能竞品未设计、架构不同、真实盲区）
- **证据独有**：证据路径发现但设计路径未提出的 Actor，评估是否属于本产品范围内角色（可能竞品多角色场景、竞品已有成熟模式）
- 无法调和的差异记录到「争议记录」

### 执行

1. **并行产出（滑动窗口限流）**：同时启动各路 agent（遵守 SKILL.md「Agent 并发控制」），每路独立注入对应输入和视角分配。若总数超限，初始启动 5 个，每完成一个立即补位
2. **合并**：主会话按上述规则合并产出
3. 每个 Actor 明确：类型、职责、交互方式、关注点
4. 写入 `docs/requirements/product-spec.md`（Actor 章节），格式遵循 `.claude/templates/req-product-spec.md`

**出口标准**（由主会话检查）：
- [ ] Actor 列表非空，至少识别出 3 个核心 Actor（覆盖至少两个不同角色类型）
- [ ] 每个 Actor 已明确：类型、职责、交互方式、关注点
- [ ] 隐性 Actor 检查已完成（安全审计/合规检查/运维值班/第三方集成/监控告警系统）
- [ ] 文档已按模板结构写入 `product-spec.md#actors`
- [ ] 文件已验证存在（`ls`/`wc` 确认）

---

## 步骤 2：Feature 识别

**执行前提**：步骤 1 Actor 列表已写入 `product-spec.md`

### Feature 识别配置

**≥4 个 product agent**（视角切分由主会话根据产品上下文动态决定）：
- 主会话基于 `domain-config.yaml`（`primary_type`、`description`、`priorities`）和已识别的 Actor 列表，产出 ≥4 个互补视角，确保覆盖所有 Actor 核心关注领域和质量属性优先级
- 视角必须在派遣 prompt 中明确，禁止套用固定视角清单（如"终端用户/运维/集成/安全"）
- 视角间必须互补、独立、不重叠

**1 个 architect agent**：
- 负责实现复杂度评估（粗粒度，不要求细化到子系统边界）

### 执行

按"第 1 波 product 并行 → 主会话整合 → 第 2 波 architect 评估"串行编排，避免 architect agent 在 Feature 列表尚未产出时无输入可读。

**第 1 波：≥4 个 product agent（遵守 SKILL.md「Agent 并发控制」滑动窗口）**
- 各 agent 读取 `product-spec.md#actors` 和分配的用户场景视角，围绕 Actor 核心目标独立推导 Feature 列表
- 禁止用一个 agent "内部发散多个方案"替代多个 agent 独立产出
- 若 agent 数超过 `agent.max_concurrent`，初始启动 5 个，每完成一个立即补位。禁止以并发限制为由减少 agent 数量

**主会话整合（第 1 波完成后）**
- **对齐分类框架**：基于模板结构确定统一的特性域分类和优先级定义，确保各 agent 产出在同一坐标下比较
- 在此框架下合并 product 的 Feature 列表，去重并客观记录冲突
- 每个 Feature 记录：一句话价值摘要、涉及 Actor、归属特性域、优先级
- 产出 Feature 间依赖关系矩阵
- 写入 `product-spec.md` Feature 章节草稿（复杂度字段先留空）

**第 2 波：1 个 architect agent**
- 读取 `product-spec.md`（含合并后的 Feature 列表）和 `.claude/domain-config.yaml`
- 评估各 Feature 实现复杂度（粗粒度，不要求细化到子系统边界）
- 主会话将复杂度评估回填到 `product-spec.md` 对应 Feature 字段

**写作约束**
- Feature 价值论证必须是推导式，禁止"矩阵后直接给结论"
- 文档结构遵循 `.claude/templates/req-product-spec.md`

**出口标准**（由主会话检查）：
- [ ] Feature 数量 ≥ 核心 Actor 数量 × 2，且总数 ≥ 5（复杂系统下限）
- [ ] Feature 覆盖所有已识别 Actor 的核心目标，每个核心 Actor 至少对应 2 个 Feature
- [ ] 每个 Feature 已记录：一句话价值摘要、涉及 Actor、归属特性域、优先级
- [ ] Feature 间依赖关系矩阵已产出
- [ ] 价值论证为推导式，非直接给结论
- [ ] 文档已按模板结构写入 `product-spec.md`

---

## 步骤 3：评审修正循环

> **准入条件**：`product-spec.md` 草稿已写入文件（步骤 1 + 步骤 2 均已完成）
> **核心约束**：按 SKILL.md「标准评审修正循环」执行，本文只声明本阶段特有参数和规则。

### 3.1 评审配置

**3 个 reviewer，并行独立评审**：

- `product-reviewer` × 2，视角切分（避免重复评审、各有侧重）：
  - **用户价值与商业合理性**：质疑 Feature 的用户假设、优先级推导、价值论证充分性
  - **Actor 完备性与覆盖度**：质疑 Actor 遗漏（含隐性 Actor）、Feature 对 Actor 核心目标的覆盖度、特性域分类合理性
- `architect-reviewer` × 1（维度收窄至本阶段已具备的判断材料）：
  - **评审维度**：技术可行性粗判（拦截 Feature 中的技术幻想，如"零延迟全球同步"等不可实现承诺）、步骤 2 architect agent 给出的实现复杂度评估是否过度乐观
  - **明确禁评**：跨子系统边界、架构一致性、依赖关系合理性 — 这些维度依赖 design.md 细化到 Feature 粒度，本阶段不具备评审材料，硬评易产生伪 CRITICAL

### 3.2 独立评审

主会话按评审配置并行派遣 reviewer。

- **主会话职责**：在派遣评审 agent 的 prompt 中注入文档的系统上下文（product-spec.md 总纲地位、Actor-Feature 对各后续阶段的连锁影响）和修正成本评估
- **评审纪要写作规范**：参见 SKILL.md「评审纪要写作规范」

### 3.3 验证与修正

> 按 SKILL.md「标准评审修正循环」步骤 2-7 执行。本阶段特有参数声明如下：

| 参数 | 值 | 说明 |
|------|-----|------|
| 评估对象数 | Actor 数量 / Feature 数量 | 按步骤分别计算密度，**任一维度超标即进入修正** |
| 缺陷密度门槛 | 步骤1 ≤ 1.5 分/Actor；步骤2 ≤ 1.5 分/Feature | 见 SKILL.md「缺陷密度门槛标定依据」 |
| 修正 agent | product agent | 修正后更新 `product-spec.md` |
| 修正后复核路径 | 回到 3.2 独立评审 | |
| \> 30 处回退目标 | 步骤1高 → 步骤1；步骤2高 → 步骤2；两者均高 → 步骤1 | Actor 是 Feature 的基础 |

**成功退出条件**（同时满足）：
- 所有 reviewer 均已完成独立评审
- 无 CRITICAL 问题
- 步骤 1 缺陷密度 ≤ 1.5 分/Actor，步骤 2 缺陷密度 ≤ 1.5 分/Feature
- 文档 `docs/requirements/product-spec.md` 已写入并验证存在
- `product-spec.md` 末尾已写入 `**评审状态**: ✅ PASS` 标记（按 SKILL.md「评审纪要写作规范」格式）
- 所有 HIGH 问题已评估：接受修正 / 接受延期 / 拒绝
