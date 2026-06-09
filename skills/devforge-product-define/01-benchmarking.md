# 第 1 阶段：标杆研究

**准入条件**：第 0 阶段完成，`.claude/domain-config.yaml` 已生成
**产出文件**：`docs/requirements/reference/<product>.md`（每个标杆一个文件，至少 2-3 个）
**模板**：`templates/ref-requirements.md`

---

## 步骤1：标杆选择

### 1.1 读取产品定位

主会话读取 `.claude/domain-config.yaml`，整合以下字段形成标杆筛选输入（缺一不可）：

- `system.primary_type` / `system.sub_type` — 决定**标杆品类范围**
- `system.description` — 包含核心痛点、目标用户、Non-Goals，决定**对标用户与场景方向**与**筛选禁区**
- `system.scale`（deployment / data_scale / concurrency） — 决定**对标规模量级**（影响标杆的产品形态匹配）
- `quality_attributes.priorities` — 决定**对标关注的质量维度权重**
- `quality_attributes.targets`（latency_p99 / throughput / availability_sla / consistency_model） — 决定**对标量化指标精度**
- `domain_specific`（如 edge_cloud_topology / data_loss_tolerance 等） — 决定**领域差异化筛选条件**（识别本产品 Actor / Feature 的特异性）

### 1.2 构造搜索查询

**构造搜索查询并执行网络搜索**：

- 搜索查询示例：
  - `"{primary_type} {sub_type} benchmark products 2026"`
  - `"best {primary_type} {sub_type} solutions market leaders"`
  - `"{primary_type} open source vs commercial comparison"`
- 使用 WebSearch 工具搜索，获取最新的行业标杆产品
- 从搜索结果中提取候选标杆（关注：市场份额、技术成熟度、开源/商业、架构特点）

### 1.3 调整选择倾向

基于 `quality_attributes.priorities` 调整选择倾向：

- 一致性优先 → 优先选择强一致性的标杆
- 性能优先 → 优先选择高吞吐/低延迟的标杆
- 可用性优先 → 优先选择高可用架构的标杆

### 1.4 确认标杆

向用户展示候选标杆列表（2-5 个），说明选择理由，确认最终选择：

- 基准：2-3 个标杆
- 复杂系统：3-5 个标杆
- 确保覆盖不同架构流派或技术路线

---

## 步骤2：标杆调研

> **核心原则**：标杆研究是深度思考过程，统一采用多 agent 协作模式，确保研究质量。

### 2.1 主会话决定 agent 配置

标杆选择完成后，主会话读取相关输入并直接决定派遣配置（不委托中间 agent 做任务解构）：

1. 读取 `.claude/domain-config.yaml`，理解系统类型、质量属性优先级、规模特征
2. 读取 `templates/ref-requirements.md`，明确模板章节结构
3. **决定研究策略**：
   - 基于质量属性优先级确定重点对比维度（如一致性优先 → 重点研究一致性协议的权衡）
   - 基于系统规模确定研究深度（如 very-large → 需要研究可扩展性设计）
   - 识别各标杆中需要被显式质疑的关键假设
4. **决定 agent 配置**（动态产出，不预设视角）：
   - **每个标杆的 researcher 数量**：基于标杆复杂度和系统规模动态决定（基线 2，可上调到 3-4）
   - **每个标杆的研究视角切分**：根据当前产品的 `primary_type` / `description` / 标杆特点动态产出 ≥2 个互补视角，在派遣 prompt 中说明切分理由
     - 视角必须互补、独立、不重叠
     - 视角数 = 该标杆的 researcher 数
     - 禁止套用固定视角清单（如固定的"用户角色/使用阶段/分析维度"），必须以本次研究的具体上下文为出发点
   - **确保分析维度完整**：至少覆盖功能与场景、质量属性、运维与集成三个维度
   - **reviewer 配置**：≥2 个，包含至少 product-reviewer + architect-reviewer 各 1 个；同一类型可多实例做交叉验证，数量基于标杆数与复杂度动态决定，横向对比所有标杆

### 2.2 并行启动 researcher（滑动窗口限流）

1. 按 2.1 确定的配置，**每个标杆启动 ≥2 个 researcher agent**：
   - 各自从分配的需求视角独立研究同一标杆
   - **写入文件**：将完整报告写入 `docs/requirements/reference/<product>-draft-{view}.md`
   - **返回摘要**：向主会话返回 ≤10 行轻量摘要（覆盖章节数、关键发现数、异常点）
   - 分析视角：**需求/用户/产品视角**，禁止技术分析
   - 模板约束：使用 `templates/ref-requirements.md`
   - **禁止**多个 researcher 使用同一 prompt 模板、同一分析框架

2. **遵守 SKILL.md「Agent 并发控制」**：若 agent 总数超过 `agent.max_concurrent`，使用滑动窗口策略——初始启动 5 个，每完成一个立即补位下一个。禁止以并发限制为由减少 researcher 数量或合并视角

### 2.3 标杆整合（合并 researcher）

**主会话确认所有 researcher 完成后**，按标杆分组各派一个合并 researcher：

- **输入**：`reference/<product>-draft-*.md`（同一标杆的所有 draft 文件）
- **执行**：读取所有 draft，按以下规则整合为单一文档
  - 按 `templates/ref-requirements.md` 模板组装
  - 在文档开头增加「研究视角」章节，标注各视角的 researcher 归属
  - 同一章节内多视角内容冲突时，保留更具体的描述，标注差异并给出整合理由
- **输出**：`docs/requirements/reference/<product>.md`
- **返回**：向主会话返回摘要（合并后章节数、冲突标注数、各视角覆盖度）

**禁止**：将同一标杆的多个视角保留为多个独立文件（如 `minio.md` + `minio-ops.md`），必须整合为单一文件。

### 2.4 产出完整性检查

合并后的标杆文件写入目录后、进入步骤 3 前，必须执行以下检查：

- [ ] **标杆文件数** = 确认的标杆数（每个标杆恰好 1 个文件）
- [ ] **每个标杆的视角数** ≥ 2（通过「研究视角」章节或文件内标注确认）
- [ ] **所有 researcher agent 状态** = 已完成（成功或最终失败）
- [ ] **三维度分析完整**：每个标杆文件包含功能与场景、质量属性、运维与集成三个维度

**未通过处理**：
- 任一标杆视角数 < 2 → 回退到步骤 2.1，针对该标杆重新分配 researcher，禁止跳过
- researcher agent 仍有运行中 → 等待完成，禁止提前进入步骤 3
- 标杆文件数 ≠ 标杆数 → 检查是否有重复产出未合并或遗漏标杆未产出
- 任一标杆三维度分析不完整 → 该标杆 researcher 重做缺失维度

**主会话确认所有 researcher agent 已完成**（成功或最终失败），且产出完整性检查通过后，**立即执行 draft 清理**（按 SKILL.md「draft 清理约束」）：

```bash
rm docs/requirements/reference/*-draft-*.md
ls docs/requirements/reference/ | grep -- '-draft-' && echo "清理未完成" || echo "清理通过"
```

清理通过后方可进入步骤 3。禁止 draft 文件残留进入评审，禁止在 agent 仍在运行期间提前进入评审。

---

## 步骤3：评审修正循环

> **前置条件**：步骤 2 已完成（所有标杆文件已写入）
> **核心约束**：评审修正循环按 SKILL.md「标准评审修正循环」执行，本文只声明本阶段特有参数和规则，不得重复标准循环内容。

### 3.1 并行评审

**reviewer agent 配置**：

- **基线类型**：≥2 个（至少 product-reviewer + architect-reviewer 各 1 个）
- **同一类型可多实例独立评审**做交叉验证（如复杂标杆可派 2 个 product-reviewer 对比意见）
- **数量由主会话基于标杆数量与复杂度动态决定**（基线 2，可上调到 3-4），禁止默认按"两个分工"派遣

**派遣 prompt 字段**（按 SKILL.md「评审视角（reviewer agent）」一节的「派遣 prompt 必备字段」清单组装，本阶段具体取值如下）：

- **被评审对象路径**：`docs/requirements/reference/<product>.md`（每个标杆一份）
- **被评审 template 路径**：`templates/ref-requirements.md`（视角来源 1：reviewer 从其 mandatory-sections + 深度自检清单提取评审锚点）
- **评审报告产出路径**：`docs/requirements/reference/<product>-review.md`（多 reviewer / 多轮追加同一文件）
- **评审报告格式**：`templates/review-report.md`

**特异性子维度**（视角来源 2：主会话基于本次产品在派遣 prompt 中动态注入，禁止套用固定清单）：

- 基于 `domain_specific` 注入对应领域 Actor / Feature 的检查项（如边云协同 → 要求检查标杆中"边运维""云管理"类 Actor 的识别完整性）
- 基于 `quality_attributes.priorities` 前两项注入重点对比维度的检查深度
- 基于 Non-Goals 注入"标杆中不适合本产品的 Feature"的识别要求

**评审思维风格**（视角来源 3：reviewer agent 人设自带，主会话不重复声明）：

- `product-reviewer`：业务/用户视角，关注标杆对本产品定位的对齐度、Feature 价值与场景覆盖
- `architect-reviewer`：技术/架构视角，关注研究深度、方法论严谨性、结论合理性

> **主会话职责**：在派遣评审 agent 的 prompt 中注入文档的系统上下文——标杆研究报告在需求体系中的位置（作为 Actor-Feature 定义的输入依据）、重要性（错误标杆选择或分析偏差会导致后续需求定义偏离方向）、可替换性（修正成本评估，标杆研究阶段的修正成本远低于 Feature 定义阶段）。

reviewer 需横向对比多个标杆，确保分析深度和质量标准一致。

### 3.2 收集评审结果

每个 reviewer agent：
- 读取标杆最终文件（`reference/<product>.md`）执行评审
- 将评审意见追加到 `reference/<product>-review.md`
- 向主会话返回数字摘要：{issues: N, density: X, critical: Y}

主会话从数字摘要判定通过/修正/回退，不读取完整评审内容。

### 3.3 验证与修正

> 按 SKILL.md「标准评审修正循环」步骤 2-7 执行。本阶段特有参数声明如下：

**前置确认**（主会话执行）：标杆数量 ≥ 2，所有标杆文件已落盘，每个文档末尾已添加状态记录，产出完整性检查已通过（每个标杆 ≥ 2 个研究视角）。

| 参数 | 值 | 说明 |
|------|-----|------|
| 评估对象数 | 标杆数量 | 即 `docs/requirements/reference/` 下的最终文件数 |
| 缺陷密度门槛 | ≤ 2.0 分/标杆 | 见 SKILL.md「缺陷密度门槛标定依据」 |
| 修正 agent | researcher agent | 修正后更新对应标杆的 `reference/<product>.md` |
| 修正后复核路径 | 回到 3.1 重新评审；修正后的每一轮复核都必须重新计算缺陷密度并填入评审记录 | 对应标准循环第 5 步 |
| \> 30 处回退目标 | 回退到步骤 2.1 | 重新决定 agent 配置和视角切分 |

**成功退出条件**（同时满足）：
- 所有 reviewer 均已完成独立评审
- 无 CRITICAL 问题
- 缺陷密度 ≤ 2.0 分/标杆
- 每个标杆文件末尾已写入 `**评审状态**: ✅ PASS` 标记（按 SKILL.md「评审状态标记契约」格式）
- 所有 HIGH 问题已评估：接受修正 / 接受延期 / 拒绝

