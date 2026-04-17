# /ky:arch

探索产品架构方案、竞品分析、子系统分解。采用多 agent 深度思考模式，强调标杆研究先行、长时间迭代。

## 何时使用

- 系统架构设计（长期迭代，非一次对话完成）
- 重大技术决策
- 竞品分析和方案对比
- 架构重构评估
- 子系统分解调整
- **继续完善已有架构文档**（螺旋式迭代）

## 核心原则

1. **标杆先行**：不研究业界方案，不允许提出自研方案
2. **深度对比**：至少 3 个候选方案，明确取舍分析
3. **长时间迭代**：架构需 5-20 轮迭代，禁止一次对话定架构
4. **方案 > 代码**：聚焦设计决策和 rationale，不讨论代码实现
5. **多 agent 协作**：researcher 标杆研究，architect 方案发散与决策，architect-reviewer 独立质疑验证
6. **产出必须落盘**：每轮产出必须写入项目文件，禁止仅在对话中输出
7. **模板即法源**：所有正式文档的内容结构以 `.claude/templates/*.md` 为准

## 执行流程（多轮迭代）

### 第 0 步：状态检测

1. 检测现有文档状态（reference/、decisions/、adr.md、design.md、子系统文档）
2. 汇报当前状态：已完成标杆数、当前轮次、置信度

### 第 1 轮：标杆研究（强制，不可跳过）

**产出文件**：`docs/architecture/reference/<product>.md`（每个标杆一个文件）
**模板**：`.claude/templates/ref-architecture.md`

**执行方式**：
- 读取模板，确认深度要求
- 并行启动 researcher 研究标杆
- researcher 完成后，**主会话将内容写入文件**
- **architect 验收研究深度**（按模板自检清单逐项确认）
- 验收不达标时，**明确反馈 researcher 补充分析**，循环优化
- **未通过验收，禁止进入下一轮**

### 第 2 轮：方案发散（分层展开，多 Agent 协作）

**Step 1：整体架构发散**
- 产出文件：`docs/architecture/decisions/decision-overall.md`

**Step 2：关键技术维度确认 + 并行发散**
- 与用户确认关键技术维度
- 并行启动 researcher 做补充调研（每个维度一个 researcher agent）
- 并行启动 architect 产出方案对比矩阵（每个维度一个 architect agent，禁止串行）
- 每个维度一个文件：`docs/architecture/decisions/decision-<维度>.md`

**验收标准**：
- [ ] 整体架构探索笔记**已写入文件**
- [ ] 关键技术维度已识别并与用户确认
- [ ] 每个维度的探索笔记**已写入文件**
- [ ] 每个探索笔记：≥3个候选方案、有参考来源、有优缺点、有可量化对比

### 第 3 轮：评估收敛与文档定稿（三阶段多 Agent 协作）

**收敛顺序**：先 ADR 决策 → 再系统总纲 → 最后子系统文档

#### Step 1：ADR 收敛（三阶段）

1. **architect 初评**：读取 `arch-adr.md` 模板 → 五维评估 → ADR 初稿
2. **architect-reviewer 质疑**：读取模板 → 独立评审 → 按复杂度分级质疑（单一技术 ADR ≥5 个，复杂演进式 ADR ≥8 个）
3. **architect 修正定稿**：回应质疑 → ADR 终稿

**产出文件**：
- 低置信度（<70%）：更新各决策文档
- 中置信度（70%-80%）：`docs/architecture/adr.md`（ADR 草稿 + Reviewer 质疑意见）
- 高置信度（>80%）：`docs/architecture/adr.md`（正式 ADR + Reviewer 回应）

#### Step 2：系统架构总纲定稿（强制三阶段）

**输入**：ADR 终稿。

1. **architect 发散**：读取 `arch-system.md` 模板 → 发散 ≥2 个总纲结构备选，产出 `docs/architecture/design.md` 初稿
2. **architect-reviewer 质疑**：读取模板 → 至少 5 个质疑点
3. **architect 修正定稿**：产出 `design.md` 终稿

**关键纪律**：**`design.md` 未产出前，禁止产出任何子系统文档。**

#### Step 3：子系统架构文档定稿（强制，每个子系统独立三阶段）

**输入**：ADR 终稿 + `design.md` 总纲。

1. **architect 子系统方案发散**：读取 `arch-subsystem.md` 模板 → 识别 ≥2 个候选实现方案，产出 `<subsystem>/design.md` 初稿
2. **architect-reviewer 独立质疑**：读取模板 → 至少 5 个质疑点
3. **architect 修正定稿**：回应质疑后产出终稿

**验收标准**（每个 `docs/architecture/<subsystem>/design.md` 独立验收）：
- [ ] 对应维度 ADR 置信度 **> 80%（高）**
- [ ] **子系统文档经过"发散→质疑→修正"三阶段**
- [ ] **符合 `.claude/templates/arch-subsystem.md` 模板要求**
- [ ] 包含 ≥2 个备选实现方案的**推导式对比**
- [ ] **包含模块关系图/数据流图/时序图等动态视图（ASCII 形式）**
- [ ] 设计 rationale 有充分论证
- [ ] **architect-reviewer 对子系统初稿质疑已完成，至少 5 个质疑点已回应**
- [ ] 与周边子系统的边界和接口定义清晰
- [ ] 文中无具体代码实现（类/函数/可编译语法），但允许高层伪代码和算法思想描述

### 第 4 轮：架构维护与扩展（用户驱动）

**核心定位**：前 3 轮完成后，架构文档已进入"可用状态"。第 4 轮是**用户在后续开发过程中，按需调用 `/ky:arch` 来修正、补充或调整架构设计**。

**触发原因**：
1. 实现验证后发现设计缺陷
2. 新需求或范围变更
3. 补充新的标杆研究或技术调研
4. 整合子系统实现中发现的不一致

**交互模式**：
- 状态自检（只呈现信息）
- 用户明确指定任务
- 执行（支持快速通道和第 1/2/3 轮局部子流程）

**快速通道**：
- 文档一致性修正
- 假设验证状态更新
- 单篇标杆补充

## 禁止事项

- ❌ 单次对话内完成"研究→方案→文档"
- ❌ 标杆研究 < 2 个即提出方案
- ❌ 只有 1 个候选方案
- ❌ 方案描述中代码细节 > 设计 rationale
- ❌ 不明确的置信度评估
- ❌ **Agent 产出内容仅存在于对话中，未写入项目文件**
- ❌ **汇报"本轮完成"但对应文件未落盘**
- ❌ **主会话一次性批量产出多个子系统架构文档**
- ❌ **子系统架构文档未经 architect-reviewer 质疑直接定稿**
- ❌ **`design.md` 总纲未产出前就产子系统文档**
- ❌ **产出正式文档前未读取对应模板**

## 参数

无参数。交互式引导。

## 使用示例

```
/ky:arch

=== 状态汇报 ===
已完成标杆研究：2/3（LMCache ✓, InfiniStore ✓, MoonCake ⏳）
当前轮次：第 1 轮（标杆研究）
当前置信度：低（研究不充分）

=== 本次重点 ===
继续完成 MoonCake 深度分析
预计时间：15 分钟

=== 产出 ===
docs/architecture/reference/product-mooncake.md

确认开始？（是/调整重点）
```

```
/ky:arch

=== 状态汇报 ===
已完成标杆研究：3/3 ✓
当前轮次：第 3 轮（评估收敛）
当前置信度：中（方案对比清晰，有假设待验证）

=== 本次重点 ===
产出 ADR-001 草稿，标注待验证假设
建议：后续通过原型验证关键假设

确认开始？（是/继续完善方案）
```

```
/ky:arch

=== 状态汇报 ===
已完成标杆研究：3/3 ✓
当前轮次：第 4 轮（架构维护）
当前状态：ADR-005 假设验证已过期，design.md 与 storage/design.md 存在接口命名不一致

=== 您本次希望做什么？ ===
1. 修正接口命名不一致
2. 更新 ADR-005 假设验证状态
3. 补充新标杆调研
4. 其他（请描述）
```

## 输出物

- `docs/architecture/reference/*.md` — 标杆分析（第 1 轮产出）
- `docs/architecture/decisions/decision-*.md` — 决策过程文档（第 2 轮正式交付物）
- `docs/architecture/decisions/decision-*.research.md` — researcher 原材料（第 2 轮支撑材料）
- `docs/architecture/adr.md` — 架构决策记录（第 3 轮产出）
- `docs/architecture/adr.md#草稿区` — ADR 草稿（中置信度时）
- `docs/architecture/design.md` — 系统架构总纲（第 3 轮产出）
- `docs/architecture/<subsystem>/design.md` — 子系统架构主文档（子目录组织，支持拆分）

## 文档结构

```
docs/
├── architecture/
│   ├── README.md              # 目录导航 + 当前轮次看板
│   ├── adr.md                 # 架构决策记录（第 3 轮产出）
│   ├── design.md              # 系统架构总纲（第 3 轮+）
│   ├── storage/               # 子系统：存储
│   │   └── design.md
│   ├── transport/             # 子系统：传输
│   │   └── design.md
│   ├── metadata/              # 子系统：元数据
│   │   ├── design.md
│   │   └── distributed-index.md   # 可选：模块拆分
│   ├── scheduler/             # 子系统：调度
│   │   └── design.md
│   ├── connector/             # 子系统：连接器
│   │   └── design.md
│   ├── decisions/             # 第 1-2 轮：决策过程文档
│   │   ├── README.md
│   │   ├── decision-overall.md
│   │   ├── decision-indexing.md
│   │   ├── decision-indexing.research.md
│   │   └── ...
│   └── reference/             # 第 1 轮：标杆分析
│       ├── product-lmcache.md
│       ├── product-infinistore.md
│       ├── product-mooncake.md
│       └── paper-pagedattention.md
├── requirements/              # 产品级需求
└── interfaces/                # 接口规格（后续产出）
    └── *.md
```

## 关联

- Skill: `product/architect`
- Agent: `researcher` (标杆研究), `architect` (架构决策), `architect-reviewer` (独立质疑)
- Rules: `workflow`
