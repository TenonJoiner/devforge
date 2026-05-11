# 第 1 阶段：标杆研究

**准入条件**：第 0 阶段完成（`domain-config.yaml` 已生成）
**产出文件**：`docs/architecture/reference/<product>.md`（每个标杆一个文件，至少 2-3 个）
**模板**：`.claude/templates/ref-architecture.md`

---

## 步骤 1：标杆选择

### 1.1 读取产品定位

主会话读取 `domain-config.yaml`：
- `system.primary_type` / `system.sub_type`
- `quality_attributes.priorities`
- `benchmarks`（第 0 阶段已有候选）

### 1.2 候选确认

主会话基于第 0 阶段确认的标杆候选 + 必要的补充搜索（WebSearch），向用户展示候选列表（2-5 个），说明选择理由，确认最终选择：

- 基准：2-3 个标杆
- 复杂系统：3-5 个标杆
- 确保覆盖不同架构流派或技术路线

---

## 步骤 2：标杆调研

> **核心原则**：标杆研究是深度思考过程，统一采用多 agent 协作模式，确保研究质量。

### 2.1 主会话决定 agent 配置

标杆选择完成后，主会话直接决策派遣配置（不委托中间 agent 做任务解构）：

1. 读取 `.claude/domain-config.yaml`，理解系统类型、质量属性优先级、规模特征
2. 读取 `.claude/templates/ref-architecture.md`，明确模板章节结构
3. **决定研究策略**：
   - 基于质量属性优先级确定重点对比维度（如一致性优先 → 重点研究一致性协议的权衡）
   - 基于系统规模确定研究深度（如 very-large → 需要研究可扩展性设计）
   - 识别各标杆中需要被显式质疑的关键假设
4. **决定 agent 配置**（动态产出，不预设视角）：
   - **每个标杆的 researcher 数量**：基于标杆复杂度和系统规模动态决定（基线 2，可上调到 3-4）
   - **每个标杆的研究视角切分**：根据当前产品的 `primary_type` / `description` / 标杆特点动态产出 ≥2 个互补视角，在派遣 prompt 中说明切分理由
     - 视角数 = 该标杆的 researcher 数
     - 视角切分遵循 SKILL.md「视角切分原则」
   - **确保分析维度完整**：至少覆盖原理层、设计层、优化层三层拆解
   - **reviewer 配置**：≥2 个（architect-reviewer + product-reviewer 或更多），横向对比所有标杆

### 2.2 并行启动 researcher（滑动窗口限流）

1. 按 2.1 确定的配置，**每个标杆启动 ≥2 个 researcher agent**：
   - 各自从分配的架构视角独立研究同一标杆
   - **写入文件**：将完整报告写入 `docs/architecture/reference/<product>-draft-{view}.md`
   - **返回摘要**：向主会话返回 ≤5 行轻量摘要（覆盖章节数、关键发现数、异常点）
   - 模板约束：使用 `.claude/templates/ref-architecture.md`
   - 必须完成"原理层→设计层→优化层"三层拆解
   - 必须给出"对我方架构的启示"
   - **禁止**多个 researcher 使用同一 prompt 模板、同一分析框架

2. **遵守 SKILL.md「Agent 并发控制」**：若 agent 总数超过 `agent.max_concurrent`，使用滑动窗口策略——初始启动 5 个，每完成一个立即补位下一个。禁止以并发限制为由减少 researcher 数量或合并视角

### 2.3 标杆整合（合并 researcher）

**主会话确认所有 researcher 完成后**，按标杆分组各派一个合并 researcher：

- **输入**：`reference/<product>-draft-*.md`（同一标杆的所有 draft 文件）
- **执行**：读取所有 draft，按以下规则整合为单一文档
  - 按 `.claude/templates/ref-architecture.md` 模板组装
  - 在文档开头增加「研究视角」章节，标注各视角的 researcher 归属
  - 同一章节内多视角内容冲突时，保留更具体的描述，标注差异并给出整合理由
- **输出**：`docs/architecture/reference/<product>.md`
- **返回**：向主会话返回摘要（合并后章节数、冲突标注数、各视角覆盖度）

**禁止**：将同一标杆的多个视角保留为多个独立文件（如 `etcd.md` + `etcd-ops.md`），必须整合为单一文件。

### 2.4 产出完整性检查

合并后的标杆文件写入目录后、进入步骤 3 前，必须执行以下检查：

- [ ] **标杆文件数** = 确认的标杆数（每个标杆恰好 1 个文件）
- [ ] **每个标杆的视角数** ≥ 2（通过「研究视角」章节或文件内标注确认）
- [ ] **所有 researcher agent 状态** = 已完成（成功或最终失败）
- [ ] **三层拆解完整**：每个标杆文件包含原理层、设计层、优化层

**未通过处理**：
- 任一标杆视角数 < 2 → 回退到步骤 2.1，针对该标杆重新分配 researcher，禁止跳过
- researcher agent 仍有运行中 → 等待完成，禁止提前进入步骤 3
- 标杆文件数 ≠ 标杆数 → 检查是否有重复产出未合并或遗漏标杆未产出

主会话确认所有 researcher agent 已完成且产出完整性检查通过后，方可进入步骤 3。禁止在 agent 仍在运行期间提前进入评审。

---

## 步骤 3：评审修正循环

> **前置条件**：步骤 2 已完成（所有标杆文件已写入并通过完整性检查）
> **核心约束**：评审修正循环按 SKILL.md「标准评审修正循环」执行，本文只声明本阶段特有参数和规则，不得重复标准循环内容。

### 3.1 评审配置

**≥2 个 reviewer，并行独立评审**所有标杆报告：

- `architect-reviewer`：研究深度、方法论严谨性、Trade-off 分析的客观性、与产品定位的匹配度
- `product-reviewer`：架构启示与需求场景的匹配度、量化指标合理性

> **主会话职责**：在派遣评审 agent 的 prompt 中注入文档的系统上下文——标杆研究报告在架构体系中的位置（作为后续方案发散和决策的输入依据）、重要性（错误标杆选择或分析偏差会导致后续架构设计偏离方向）、可替换性（修正成本评估，标杆研究阶段的修正成本远低于决策定稿阶段）。

reviewer 需横向对比多个标杆，确保分析深度和质量标准一致。

### 3.2 独立评审

每个 reviewer agent：
- 读取所有标杆最终文件（`reference/<product>.md`）执行评审
- 将评审意见追加到 `reference/<product>-review.md`
- 向主会话返回数字摘要：{issues: N, density: X, critical: Y}

主会话从数字摘要判定通过/修正/回退，不读取完整评审内容。

### 3.3 验证与修正

> 按 SKILL.md「标准评审修正循环」步骤 2-7 执行。本阶段特有参数声明如下：

| 参数 | 值 | 说明 |
|------|-----|------|
| 评估对象数 | 标杆数量 | 即 `docs/architecture/reference/` 下的最终文件数 |
| 缺陷密度门槛 | ≤ 2.0 分/标杆 | 见 SKILL.md「缺陷密度门槛标定依据」 |
| 修正 agent | researcher agent | 修正后更新对应标杆的 `reference/<product>.md` |
| \> 30 处回退目标 | 回退到步骤 2.1 | 重新决定 agent 配置和视角切分 |

**成功退出条件**（同时满足）：
- 所有 reviewer 均已完成独立评审
- 无 CRITICAL 问题
- 缺陷密度 ≤ 2.0 分/标杆
- 每个标杆文件末尾已写入 `**评审状态**: ✅ PASS` 标记（按 SKILL.md「评审纪要写作规范」格式）
- 所有 HIGH 问题已评估：接受修正 / 接受延期 / 拒绝
