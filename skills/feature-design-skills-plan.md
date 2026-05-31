# 特性级 Design/Define Skills 改造方案

> **文档性质**：方法论级别的落地方案，沉淀历次讨论结论，作为后续 skill 实现的基线。
>
> **覆盖范围**：特性级（feature-level）的需求与设计 skill 设计；产品级（product-level）skill 仅涉及命名调整，逻辑不动。

---

## 一、背景与动机

### 1.1 现状问题

主人的产品形态以**增量特性开发**为主，从头开发系统的机会稀缺。当前已建设的产品级 skill（design / define）打磨成熟（多 agent 标杆研究 → 发散 → 评审 → 修正），但落地频率低，价值未充分释放。

与此同时，OpenSpec workflow 直接生成的特性级交付件（proposal / spec / design）存在以下质量短板：

1. **设计深度不足**：每个 Decision 往往不到 50 字，没有候选对比、约束过滤链路、演进性表态、取舍代价
2. **Scenario 信息密度低**：每个 Scenario 两三句话，前置状态、动作路径、多维度断言、与基线的对比都缺失
3. **可读性差**：表格泛滥、列表堆砌、缺乏叙述性段落、基本没有图（结构图、时序图、状态机图）
4. **方法论缺位**：缺少标杆研究环节，缺少"基于本项目约束过滤候选方案"的思考链路
5. **变更追溯弱**：与产品级文档（架构、需求、ADR）的关联标注流于形式

### 1.2 改造目标

- 在不改动 OpenSpec workflow 模板结构的前提下，**通过新增特性级 skill + agent 派遣 prompt** 显著提升 design/spec 交付件质量
- skill 为人服务（可读、可讨论、可迭代），不止为 agent 服务
- 复用已有 agent（product / architect / researcher / 各 reviewer），不新建 agent
- 产品级 skill 保留并改名，避免后续真有从头开发场景时无法回头

---

## 二、核心职责边界

### 2.1 模板 / skill / agent 三者分工

| 角色 | 比喻 | 关键属性 | 谁拥有 |
|------|------|----------|--------|
| **模板** | 工作产物的"考卷" | 章节结构、字段定义、追溯关系 | 主人维护，skill 跟随 |
| **skill** | 工作流程的"施工手册" | 阶段、artifact 流转、agent 编排、生成范式、质量闸口 | 本方案主体 |
| **agent** | 干活的"专业人士" | 身份、能力、追问方式、协作边界、写作风格 | 已存在，按需通过 skill 派遣 prompt 适配场景 |

### 2.2 边界铁律

- **模板**不写"该填多少字"或"必须出图"——这是流程要求
- **skill** 不写"如何做架构师该做的事"——这是 agent 身份
- **agent** 不写"什么时候该派谁"——这是流程编排

### 2.3 OpenSpec 模板的不可破坏边界

- 不能动 Delta 语义（ADDED / MODIFIED / REMOVED / RENAMED 章节名 + Scenario 格式）—— archive 引擎依赖
- 不能动 artifact 名字和 require 关系——schema DAG 依赖
- 章节内部增强 OK——加注释引导、加可选字段、加子结构都不破坏外部契约

---

## 三、Artifact 编排与依赖图

### 3.1 修改后的 OpenSpec 工作流

```
proposal ─→ research ─→ spec ─┬─→ review ─→ tasks
                  │            │     ↑
                  └─→ design ──┘     │
                                     └─ AI 评审 + 人工决策
```

变更点：

1. **新增 research artifact**：`requires: [proposal]`，spec 与 design 都 `requires: [proposal, research]`
2. **review artifact 重新定位**：
   - **保持结构不变**：review.md 仍包含"AI 评审报告 + Tech Leader 人工决策区域"（与当前 schema 一致）
   - **AI 评审部分改造**：从"深度评审 + 修复循环（最多 5 轮）"改为"单轮扫描 + 问题清单输出"，**不做修复**
   - **人工决策部分不变**：Tech Leader 填写 PASS / PASS WITH CONDITIONS / REJECT，强制门槛
   - **底层实现改为调用 skill**：调用独立 `/df:spec-review` skill（同一 skill 也支持手动调用）
   - **可选性可配置**：默认 `required: true`（保持当前强制），项目可改为 `required: false` 允许跳过
3. **spec 与 design 之间无强制顺序**：保持 OpenSpec 现状，两者可任意先行

### 3.2 触发模式：workflow 触发 + skill 可恢复

```
/opsx:continue 走到 research/spec/design 步骤
  ↓
触发对应 skill（/df:research / /df:define / /df:design）
  ↓
skill 启动 → 扫描 artifact 完成度 → 决定模式
  ├─ 无相关 artifact：从零生成
  ├─ artifact 已存在：反问主人"修订 / 补全"
  └─ skill 显式带参数（修订 / 补全）：直接进入对应模式
  ↓
skill 内部多 agent 循环（生成 → reviewer 质疑 → 修正）
  ↓
skill 退出 → artifact 落地
  ↓
主人可对 artifact 直接对话讨论修改（不需要重启 skill）
  ↓
主人有结构性大修订意图时再 /df:design 等触发，skill 反问意图
```

### 3.3 修订/补全/重生成的处理

| 模式 | 触发方式 | skill 行为 |
|------|---------|----------|
| **修订** | 显式参数 / 反问后选择 | 读现有 artifact，主人指定修订范围，只跑相关阶段，结果 merge 回去 |
| **补全** | 显式参数 / 反问后选择 | 读现有 artifact，按结构性元素清单识别缺失，从断点续跑 |
| **重生成** | 不内置 | 主人自己删除文件后重新启动即可，无需 skill 支持 |

### 3.4 skill 启动时的状态识别

**职责边界**：
- **OpenSpec 引擎**：检查上游依赖是否就绪（如 design 的 `requires: [proposal, research]`），上游缺失时阻塞
- **skill**：只判断自己的 artifact 状态（不存在 / 完整 / 不完整），不判断上游状态

**状态识别流程**（以 `/df:design` 为例）：

```
1. 上下文准备（只读上游，不判断状态）
   Read proposal.md, research.md, spec.md（如存在）
   OpenSpec 已保证 proposal/research 存在

2. 自身状态识别
   design.md 存在？
   ├─ 不存在 → 初次生成模式
   └─ 存在 → 结构性扫描（轻量，不调 agent）
       - 章节齐全？（按 openspec template）
       - 必备元素齐全？（按 5.1 清单）
       ├─ 完整 → 反问"要修订哪部分？"
       └─ 不完整 → 反问"识别到 X 项缺失（具体列出），补全还是修订？"

3. 进入对应模式（生成 / 补全 / 修订）

4. 退出前做轻量引用扫描
   - design.md 引用的 Requirement ID 都在 spec.md 里吗？
   - design.md 引用的 research.md 段落都存在吗？
   ├─ 引用断裂 → 标注"⚠ 引用断裂：<具体>"在 design.md，提示主人
   └─ 引用完整 → skill 正常退出
```

**结构性扫描方法**：调用 LLM 做语义对比，不硬编码正则。

```
1. 读取模板和实际文档
   Read openspec template (如 templates/design.md)
   Read 实际 artifact (如 openspec/changes/<name>/design.md)

2. 调用 LLM 做语义对比
   Prompt: 对比模板和实际文档，识别结构性缺失
   - 缺失章节（模板有、实际没有）
   - 缺失字段（模板注释提示"必须"的内容）
   - 只看结构，不看质量
   
   输出：COMPLETE / INCOMPLETE + 缺失项清单

3. 根据完整性评估反问主人
   - COMPLETE: "要修订哪部分？"
   - INCOMPLETE: "识别到以下缺失：<清单>，补全还是修订？"
```

**模板即规范**：
- 模板定义的章节 → 必须有
- 模板注释里标注"必须"的 → 必须有
- 5.1 必备元素清单不在状态识别检查范围（只在生成和内化评审时用）

**跨文档一致性分层**：
- **skill 内（轻量）**：退出前调 LLM 扫引用断裂（提取 design 引用的 Requirement ID，检查是否在 spec 中存在）
- **spec-review（深度）**：扫语义对齐（reviewer agent 判断方案是否真的满足需求）

---

## 四、研究阶段方法论：standard-driven

### 4.1 research.md 三段式结构

```
research.md
├── 1. 自身约束清单
├── 2. 标杆方案空间
└── 3. 设计空间地图
```

**段 1：自身约束清单**

| 约束类别 | 来源 | 内容 |
|---------|------|------|
| 架构约束 | 产品级 architecture/ + ADR | 子系统边界、关键设计前提（如"客户端用户态架构"） |
| 协议约束 | 产品级 interfaces/ + 代码 | 既有接口契约、协议语义 |
| 性能约束 | 产品级 requirements/ 非功能需求 | 延迟、吞吐、可用性指标 |
| 范围约束 | 本特性 proposal | 本期做什么、不做什么、未来扩展点 |
| **未知约束** | 检索失败的项 | 显式标注，提示主人补充 |

每条约束附来源（文件路径 + 行号或锚点）���可追溯。

**段 2：标杆方案空间**

针对本特性主题做专题研究，按**取舍维度**而非**产品维度**组织。例如元数据缓存：

- 锁机制维度：NFSv4 delegation / Lustre 三锁分离 / 乐观版本号
- recall 触发位置维度：内核态 / 用户态
- 失效粒度维度：整目录 / 增量
- 断网处理维度：租约 / 会话探活

每个维度内对各候选方案做"原理 → 设计 → 取舍"三层拆解。

**段 3：设计空间地图**

标杆维度 × 候选方案 × 我们的约束过滤后的可行空间。形如：

```
| 维度 | 候选 A | 候选 B | 候选 C | 约束过滤结果 |
| 锁机制 | NFSv4 deleg | Lustre 三锁 | 乐观版本 | A、B 可选；C 破坏强一致 |
| recall 位置 | 内核 | 用户态 | - | 用户态（架构约束） |
```

### 4.2 标杆维度反向驱动约束发现

之前讨论中确立的核心机制：**约束不靠 agent 凭空提出，而是被标杆方案的取舍维度反向触发**。

```
1. 先做标杆研究（agent 靠预训练知识能完成）
2. 标杆方案的差异维度自然提出问题：
   "Lustre recall 在内核 → 我们的客户端架构是什么？"
3. 按问题去产品级文档检索（从会话上下文获取检索方式）
4. 命中 → 读对应文档片段
5. 未命中 → 标记「未知约束 X」，提示主人
6. 形成"标杆维度覆盖矩阵"
```

完备性判断交还给主人（看覆盖矩阵），skill 只负责把素材摊清楚。

### 4.3 产品级文档检索约定

主人维护产品级文档的检索入口（可能是索引文档、CLAUDE.md 中的说明、或其他约定），skill 从当前会话上下文中获取检索方式。

skill 启动时只读轻量的检索入口，按 proposal 关键词做检索，再局部读相关文档片段，避免通读架构目录。

---

## 五、内容质量抓手

### 5.1 结构性元素清单（生成与评审指导）

主人否决了字数下限的机械约束。每个产物单元的"必备结构性元素"成为生成时的指导原则和 skill 内化评审时的检查清单。

**定位**：
- ✓ 生成时：注入到 agent 派遣 prompt，指导生成
- ✓ skill 内化评审时：reviewer agent 的检查清单
- ✗ 状态识别时：不用（状态识别只看模板要求的结构）

#### Decision 必备元素

```
□ 选择了什么（一句话定调）
□ 候选方案 ≥ 2 个，每个标注标杆来源
□ 候选对比维度（一致性 / 复杂度 / 性能 / 与本项目约束的匹配度，至少 4 维）
□ 不选其他候选的具体理由（每个候选都要回应）
□ 演进性表态（未来扩展方向，或显式标注"本决策无演进性需求"）
□ 取舍代价 + 缓解措施
□ 未决问题拨入 Open Questions
```

#### Scenario 必备元素

```
□ 前置状态显式化（具体哪些条件成立，不能用"系统正常"这种粗粒度）
□ 触发动作的具体路径（哪个 API、哪条调用链、哪个事件）
□ 期望结果的多维度断言（返回值 + 副作用 + 性能 + 可观测信号）
□ 与基线行为的对比（说明改进点；新功能可标注"无基线，本特性首次引入"）
```

#### Requirement 必备元素

```
□ 能力定义
□ 服务于哪些场景
□ 边界（明确不做什么 + 不做的理由）
□ 未来扩展点（如有；为 cifs / 对象网关等场景预留）
```

合法回退：每项允许"显式标注本项不适用"作为合法填法（避免机械要求）。

### 5.2 可读性约束

#### 内容性质 → 表达形态映射

| 内容性质 | 表达形态 | 反例（不允许） |
|---------|---------|---------------|
| 设计思路、决策路径、演进考虑 | **叙述段（多段落）** | 列表 / 表格 |
| 多方案 trade-off 对比 | 叙述 + 对比表（叙述为主） | 只有表格 |
| 离散并列项（场景列表、影响清单） | 列表 | 不必要的拉长叙述 |
| 流程、交互、状态转移 | **图示 + 文字注解** | 纯文字描述步骤 |

#### 强制出图条件

| 设计内容 | 推荐图类型 | 实现方式 |
|---------|-----------|---------|
| 模块结构、组件关系（≥3 个组件） | 结构图 | Mermaid `graph` / ASCII |
| 跨进程/跨节点交互 | 时序图 | Mermaid `sequenceDiagram` |
| 有生命周期的对象（租约、连接、会话） | 状态机图 | Mermaid `stateDiagram` |
| 数据缓存、读写路径分离 | 数据流图 | Mermaid `flowchart` |
| 类/数据结构关系 | 类图 | Mermaid `classDiagram` |

默认 Mermaid（GitHub 原生渲染）。Mermaid 不适合时（如部署拓扑），允许 ASCII。

### 5.3 评审 agent 检查项

skill 内部循环中，reviewer agent 的评审清单：

```
[结构性合规]
- 每个 Decision 是否齐备 8 项必备元素？
- 每个 Scenario 是否齐备 4 项必备元素？
- 每个 Requirement 是否齐备 4 项必备元素？

[标杆引用]
- 每个 Decision 是否至少引用一个标杆方案？
- 候选对比表是否标注每个候选的标杆来源？

[范围对应]
- 每个 Decision 是否能追溯到 spec 的某个 Requirement？

[可读性]
- 是否存在「只有结论没有理由叙述」的决策？
- 是否存在「应该出图但没出图」的内容？
- 是否存在「列表/表格密度过高，叙述段缺失」的章节？

[未决问题闭环]
- Open Questions 是否都已记录、未误归到 Decision？
```

通过 → 落地。不通过 → 反馈给生成 agent 再来一轮。

---

## 六、Skill 详细设计

### 6.1 命名口径

| skill | 触发命令 | 职责 |
|-------|---------|------|
| `devforge-feature-research` | `/df:research` | 特性级研究：约束 + 标杆 + 设计空间地图 |
| `devforge-feature-define` | `/df:define` | 特性级需求：写 spec.md（Delta 格式） |
| `devforge-feature-design` | `/df:design` | 特性级设计:写 design.md |
| `devforge-spec-review` | `/df:spec-review` | OpenSpec 文档评审（proposal/spec/design） |
| `devforge-product-research` | `/df:product-research` | 产品级研究（原有，改名） |
| `devforge-product-define` | `/df:product-define` | 产品级需求（原有，改名） |
| `devforge-product-design` | `/df:product-design` | 产品级架构（原 `design`，改名） |

> 短名给高频的特性级，长名给低频的产品级。符合 Unix 哲学。

> **`spec-review` 与 `code-review` 的区别**：
> - `devforge-code-review` / `/df:code-review`：评审**代码**（git diff 的源文件变更）
> - `devforge-spec-review` / `/df:spec-review`：评审**OpenSpec 文档**（proposal/spec/design）
> - 两者评审对象、时机、维度完全不同，不可混用

### 6.2 `/df:research` 流程

```
[1] 启动检测
    扫描 research.md 是否存在
    ├─ 不存在：进入「初次生成」
    ├─ 存在 + skill 显式带参数：按参数走
    └─ 存在 + 无参数：反问主人「修订 / 补全」

[2] 上下文准备
    读 proposal.md（why / what / impact）
    获取产品级文档检索方式（从会话上下文）
    读 openspec template（research.md 模板，待主人新建）

[3] 标杆研究阶段
    派遣 researcher agent
    任务：基于 proposal 主题，做专题研究
         按取舍维度组织标杆方案（不按产品维度）
    产出：标杆方案空间（research.md 段 2）

[4] 约束发现阶段
    标杆维度反查：
        for each 标杆维度:
            生成"我们在这个维度的情况是什么"问题
            用 grep + 局部 read 检索产品级文档
            命中 → 提炼约束
            未命中 → 标记未知约束
    产出：约束清单（research.md 段 1） + 标杆维度覆盖矩阵

[5] 设计空间地图组装
    标杆方案 × 我们的约束 → 可行候选空间
    产出：设计空间地图（research.md 段 3）

[6] 评审循环
    派遣 architect-reviewer 质疑
    检查：标杆覆盖度、约束追溯、未知约束是否合理标注
    不通过 → 回到对应阶段

[7] 落地输出
    研究心得写入 research.md（按模板）
    在终端汇报：标杆覆盖维度数、约束清单条数、未知约束条数、置信度
```

### 6.3 `/df:define` 流程

```
[1] 启动检测
    扫描 spec.md 是否存在
    ├─ 不存在 + research.md 存在：进入「初次生成」
    ├─ 不存在 + research.md 不存在：提示先跑 /df:research（不强阻塞）
    ├─ 已存在：反问「修订 / 补全」

[2] 上下文准备
    读 proposal.md（特性范围）
    读 research.md 段 1（约束清单） + 段 3（设计空间地图）
    读 design.md（如已存在，作为可行性反向校准）
    读 openspec spec.md template（Delta 格式约束）
    读 产品级 docs/requirements/（按产品级文档检索方式查找相关 Feature）

[3] 范围决策阶段
    派遣 product agent，注入 skill 派遣 prompt：
        "当前是特性级 define 阶段。
         Actor 已在产品级文档识别完成，承接产品级 Feature [X]，
         在本特性范围内拆解为 Requirements + Scenarios。
         按 openspec spec.md 模板的 Delta 格式（ADDED/MODIFIED/REMOVED/RENAMED）输出。
         严格按结构性元素清单填充每个 Requirement 和 Scenario。
         可读性约束：避免列表堆砌，以叙述段为主。"
    产出：spec.md 草稿

[4] 评审循环
    派遣 product-reviewer 质疑
    检查：结构性元素清单合规、追溯到产品级 Feature、Scenario 三类覆盖
    派遣 architect-reviewer 评估技术可行性
    不通过 → 修正

[5] 横向校准（如 design.md 已存在）
    检查：spec 范围与 design 方案是否互相支撑？
    冲突 → 标注「需横向调整」，提示主人

[6] 落地输出
    spec.md 写入
    在终端汇报：Requirements 数、Scenarios 数（正常/异常/边界分布）、置信度
```

### 6.4 `/df:design` 流程

```
[1] 启动检测
    同 /df:define

[2] 上下文准备
    读 proposal.md
    读 research.md 全文（必读）
    读 spec.md（如已存在，作为范围约束）
    读 openspec design.md template
    读 产品级 docs/architecture/（按产品级文档检索方式查找相关子系统）
    读 产品级 docs/architecture/adr.md（按产品级文档检索方式查找相关决策）

[3] 决策点识别阶段
    派遣 architect agent，注入 skill 派遣 prompt：
        "当前是特性级 design 阶段。本特性在产品级架构 [子系统X] 内展开，
         不是新建子系统。
         读 research.md 获取标杆方案空间和约束清单。
         决策点写入 design.md 的 Decisions 段。
         严格按结构性元素清单填充每个 Decision。
         保持你已有的 ≥3 候选对比、reviewer 质疑等强制要求。
         可读性约束：
           - 决策叙述以多段落叙述为主，对比表辅助
           - 模块结构、跨节点交互、有生命周期对象必须出图（Mermaid 优先）
           - 避免「只有结论没有思路」的写法"
    任务：
        识别本特性的关键决策主题（如锁机制、缓存对象、失效策略、边界处理）
        每个主题下识别决策点
    产出：决策点列表（决策主题 + 每主题下的决策点）

[4] 决策填充阶段
    对每个决策点，agent 按结构性元素清单展开：
        候选 → 标杆做法 → 约束过滤 → 选择 → 取舍代价 → 演进性
    产出：design.md 各 Decision 段

[5] 架构定位与图示阶段
    Context 段：本特性在已有系统中的位置 + 与既有组件的关系（出结构图）
    复杂交互：时序图
    生命周期对象：状态机图
    数据流：数据流图

[6] 评审循环
    派遣 architect-reviewer 质疑
    检查：结构性元素清单合规、标杆引用、约束过滤、图的覆盖、可读性
    不通过 → 修正

[7] 横向校准（如 spec.md 已存在）
    检查：design 方案是否覆盖 spec 全部 Requirement？
    检查：design 是否有越出 spec 范围的设计（应砍掉或反推 spec 扩展）？

[8] 落地输出
    design.md 写入（如 design 先于 spec，标注"未受 spec 约束的部分"清单）
    在终端汇报：Decisions 数、出图数、置信度
```

### 6.5 三个 skill 的共享上下文协议

| skill | 必读 | 选读 | 写入 |
|-------|------|------|------|
| `feature-research` | proposal.md, 产品级文档检索入口 | 产品级架构/需求/ADR 片段 | research.md |
| `feature-define` | proposal.md, research.md, openspec template | design.md（如存在）, 产品级 requirements 片段 | spec.md |
| `feature-design` | proposal.md, research.md, openspec template | spec.md（如存在）, 产品级 architecture/ADR 片段 | design.md |

### 6.6 修订模式的工作方式（统一）

每个 skill 的修订模式都遵循：

```
1. 读现有 artifact
2. 反问主人「想修订哪一块」（提供章节 / 元素粒度的选项）
3. 只跑该范围对应的生成阶段
4. merge 结果回 artifact，不动其他章节
5. 评审循环只检查变更范围 + 受影响的相关性
```

补全模式的工作方式：

```
1. 读现有 artifact
2. 用结构性元素清单扫描，识别缺失项
3. 直接在缺失位置生成补全内容
4. 评审循环
```

---

## 七、Agent 复用与适配

### 7.1 复用判定

| Agent | 是否复用 | 适配方式 |
|-------|---------|---------|
| `product` | ✓ | skill 派遣 prompt 注入"特性级承���已���别 Actor"语境 |
| `architect` | ✓ | skill 派遣 prompt 注入"特性级在既有架构内展开 + 不出独立 ADR"语境 |
| `researcher` | ✓ | skill 派遣 prompt 注入"约束发现 + 设计空间地图"任务形态 |
| `product-reviewer` | ✓ | 直接评审 spec.md |
| `architect-reviewer` | ✓ | 直接评审 design.md / research.md |
| `code-reviewer` | 不参与 | 本方案不触及代码级 |

### 7.2 不新建 agent 的理由

- 现有 agent 已支持"工作模式 N"切换（如 architect 的探索/评审顾问/计划评审三模式）
- 特性级只是再加一个使用场景，由 skill 派遣 prompt 适配
- 新建 agent 会引入冗余角色，加重维护

### 7.3 派遣 prompt 模板（约定）

每个 skill 派遣 agent 时，prompt 必须包含：

```
1. [当前 skill 阶段]：明确告诉 agent 现在在哪个 skill 的哪个步骤
2. [上下文清单]：哪些 artifact 已读、哪些章节是输入
3. [任务定义]：要产出什么、写到哪里
4. [模板路径]：openspec template 的具体路径，agent 必须先 Read
5. [质量约束]：结构性元素清单 + 可读性约束
6. [禁忌项]：本场景不要做什么（如"特性级不出独立 ADR 文件"）
```

---

## 八、评审机制

### 8.1 三层评审

| 层级 | 形态 | 谁负责 | 检查重点 | 是否阻塞 |
|------|------|--------|---------|--------|
| **L1 skill 内化深度评审** | 多 agent 循环（生成 → reviewer → 修正） | reviewer agent | 结构性元素 + 标杆引用 + 可读性 | 阻塞 skill 输出 |
| **L2 review artifact（AI + 人工）** | 独立 artifact，调用 `/df:spec-review` skill | reviewer agent + Tech Leader | 全维度扫描（21 项）+ 人工决策 | 阻塞进入 tasks |
| **L3 主人对话讨论** | skill 退出后、review 前的自由对话 | 主人 + AI | 单点异议、内容打磨 | 不阻塞 |

### 8.2 L1 skill 内化深度评审

每个 feature-* skill 内部都有此循环，最多 3 轮：
- Round 1：生成 → reviewer 质疑 → 修正
- Round 2：再质疑 → 再修正
- Round 3：仍有 CRITICAL 问题 → 输出问题清单，要求主人介入决策

**目标**：保证 skill 输出的基础质量（结构性、标杆、可读性）。

### 8.3 L2 review artifact（AI 评审 + 人工决策）

**定位**：skill 输出后的"质量体检 + 人工门槛"，一个 artifact 包含两部分。

**与当前 schema 的关系**：

| 维度 | 当前 schema | 改造后 |
|------|------------|--------|
| artifact 名 | review.md | review.md（不变） |
| 内容结构 | AI 评审 + 人工决策区域 | AI 评审 + 人工决策区域（不变） |
| AI 评审部分 | 深度评审 + 修复循环（最多 5 轮） | 单轮扫描，输出问题清单，**不修复** |
| 人工决策部分 | Tech Leader 填写 PASS/REJECT | Tech Leader 填写 PASS/REJECT（不变） |
| 可选性 | 强制（required: true） | 默认强制，可配置 `required: false` |
| 底层实现 | schema instruction 内嵌逻辑 | 调用独立 `/df:spec-review` skill |

**与 L1 的分工**：

| 维度 | L1 skill 内化 | L2 review artifact |
|------|--------------|-------------------|
| **时机** | 生成过程中 | 生成完成后 |
| **目标** | 保证基础质量 | 全维度体检 + 人工门槛 |
| **检查深度** | 结构性元素 + 标杆 + 可读性 | 全维度（21 项，源自当前 schema） |
| **发现问题后** | 自动修复并再评审 | 输出清单，**不修复**，交人决策 |
| **可见性** | 黑盒（开发人员看不到） | review.md 落盘可见、可 git 追溯 |
| **是否阻塞** | 阻塞 skill 输出 | 阻塞进入 tasks（人工决策未填写时） |

**双重调用方式**：

| 方式 | 触发 | 场景 |
|------|------|------|
| **OpenSpec workflow 触发** | `/opsx:continue` 走到 review artifact | 标准流程，review.md 落到 `openspec/changes/<name>/review.md` |
| **手动触发** | 任意时刻直接 `/df:spec-review` | 临时体检、改散了想重新扫描、review.md 被删后重新生成 |

两种方式共享同一个 skill 实现。

**评审维度（21 项）**：保留当前 schema review instruction 中的全部维度——

```
跨文档一致性（追溯链 + 与产品级文档对齐）
Proposal 质量（3 项：动机/方案/范围）
Specs 质量（7 项：合理性/必要性/完整性/清晰性/可验收性/异常路径/安全覆盖）
Design 质量（11 项：可行性/竞争力/合理性/架构一致性/内部一致性/可维护性/
              故障处理/决策备选/并发模型/状态机/性能评估）
```

**review.md 输出格式**（保持当前结构，只改 AI 评审部分的生成方式）：

```markdown
# Review Report — [timestamp]

## AI Review

### Summary
- proposal.md: 缺陷密度 X.X
- spec.md: 缺陷密度 X.X
- design.md: 缺陷密度 X.X

### Issues by Severity

#### CRITICAL (10 分)
- [proposal] 动机不清晰：Why 段落未说明根因
- [design] 方案矛盾：Decision 2 与 Decision 5 冲突

#### HIGH (3 分)
- [spec] Scenario 缺失：Requirement 3 无异常路径

#### MEDIUM (1 分) / LOW (0.1 分)
...

### AI Recommendation
PASS / PASS WITH CONDITIONS / REJECT + 理由

### 后续处理建议
- 对话修改 artifact
- 重跑对应 skill（修订模式）
- 认为问题不成立，在人工决策时说明

---

## Tech Leader Decision

**Decision**: <!-- 填写 PASS / PASS WITH CONDITIONS / REJECT -->

**Reviewer**: <!-- leader 名字 -->

**Comments**:
<!-- 
- 已查看 AI review 报告，X 个问题已修复 / 可接受
- 其他备注
-->

**Date**: <!-- YYYY-MM-DD -->
```

**与 `devforge-code-review` 的边界**：

- `code-review`：评审**代码**（git diff 的源文件变更）— 代码级 task 完成后
- `spec-review`：评审**OpenSpec 文档**（proposal/spec/design）— 特性级 design 完成后

两者评审对象、时机、维度完全不同，独立存在不冲突。

### 8.4 L3 主人对话讨论

- skill 退出后、review 前，主人可直接对话改 artifact 文件
- 不需要重启 skill
- 改散了导致结构性问题时，可手动跑 `/df:spec-review` 做体检
- review 生成后发现问题，可对话修改后删除 review.md 重新触发（当前 schema 已支持）

## 九、依赖与前置条件

### 9.1 主人侧待办（不在本方案 skill 实现范围内）

| 项 | 说明 | 优先级 |
|---|------|-------|
| 维护产品级文档检索入口 | 索引文档 / CLAUDE.md 说明 / 其他约定，让 skill 能从会话上下文获取检索方式 | 高（research skill 启动依赖） |
| 完善 OpenSpec 模板 | 把团队现有模板内容融合进 openspec spec.md / design.md | 中（skill 可先跑现有模板） |
| 新建 OpenSpec research.md template | 三段式结构 | 高（research skill 落盘依赖） |
| 改造 OpenSpec schema | 新增 research artifact，review 重新定位��可选体检，新增 sign-off artifact | 高 |

### 9.2 skill 实现侧待办

| 项 | 说明 |
|---|------|
| `.claude/skills/devforge-feature-research/SKILL.md` | 新建 |
| `.claude/skills/devforge-feature-define/SKILL.md` | 新建 |
| `.claude/skills/devforge-feature-design/SKILL.md` | 新建 |
| `.claude/skills/devforge-spec-review/SKILL.md` | 新建（评审 OpenSpec 文档） |
| `.claude/commands/df/research.md` | 新建 |
| `.claude/commands/df/define.md` | 新建 |
| `.claude/commands/df/design.md` | 新建 |
| `.claude/commands/df/spec-review.md` | 新建 |
| 产品级 skill 改名 | `devforge-design` → `devforge-product-design` 等，更新所有引用 |
| `devforge-code-review` 文档补充 | 在 SKILL.md 开头加"与 spec-review 的区别"说明 |

---

## 十、落地步骤建议

> 实际落地顺序，主人可根据精力调整。

### Phase 0：准备工作（主人主导）

- 维护产品级文档检索入口（索引文档 / CLAUDE.md 说明 / 其他约定）
- 设计 research.md 的 OpenSpec template

### Phase 1：Schema 与模板改造（主人主导，skill 跟随）

- OpenSpec schema 新增 research artifact
- review artifact 重新定位：从"深度评审 + 修复循环"改为"可选质量体检"，调用 `/df:spec-review` skill
- 新增 sign-off artifact（轻量签字）
- spec.md / design.md template 增强（注释引导、结构性提示）

### Phase 2：产品级 skill 改名（低风险）

- `devforge-design` → `devforge-product-design`
- `devforge-define` → `devforge-product-define`
- 命令更新：`/df:design` → `/df:product-design` 等
- 全仓库引用同步

### Phase 3：feature-research skill 实现（最关键）

- 因为 define / design 都依赖 research，先实现这个
- 派遣 researcher agent + architect-reviewer 评审
- 标杆维度反向驱动约束发现的逻辑落地

### Phase 4：feature-define / feature-design skill 实现

- 两个 skill 可并行实现
- 重点：派遣 prompt 工程 + 结构性元素清单 + 可读性约束 + 图示触发

### Phase 5：spec-review skill 实现

- 独立 skill，支持 OpenSpec workflow 触发 + 手动触发双模式
- 评审维度保留当前 schema review instruction 的 21 项
- 输出 review.md（问题清单 + 分级），不做修复

### Phase 6：联调与质量验证

- 找一个真实特性（比如主人提到的"客户端元数据缓存"）跑一遍完整流程
- 评估输出质量，调优 prompt 工程

---

## 十一、未决问题与开放讨论

| 编号 | 问题 | 状态 |
|------|------|------|
| Q1 | research.md 的 OpenSpec template 由谁写、什么时候写？ | 待主人定 |
| Q2 | sign-off.md 是否要有最小模板（一行 APPROVED + 主导修订人）？ | 倾向是 |
| Q3 | "可读性约束"放进 agent 输出标准还是 skill 派遣 prompt？ | 暂放 skill 派遣（不影响产品级风格），未来可考虑升格 |
| Q4 | 是否需要 `/df:design verify` 子命令做结构性体检？ | 后续补充 |
| Q5 | 多人多天迭代时，artifact 的协作冲突（多人改同文件）怎么处理？ | 走 git，本方案不内置协作机制 |

---

## 十二、总结：方案核心五点

1. **三者分工**：模板（结构）/ skill（流程）/ agent（专业能力），互不越界
2. **artifact 编排**：proposal → research → spec/design → sign-off → tasks
3. **触发模式**：workflow 触发 + skill 可恢复，状态在 artifact 文件本身
4. **质量抓手**：结构性元素清单（替代字数下限）+ 可读性约束（叙述/出图）+ skill 内化评审
5. **不新建 agent**：复用现有 agent，靠 skill 派遣 prompt 适配特性级场景
