# 第 0 阶段：前置调研与定位确认

**准入条件**：无
**产出文件**：
- `.claude/domain-config.yaml`
- `docs/architecture/design.md`（初稿/WIP 状态）

> **豁免说明**：第 0 阶段为交互式信息收集，豁免完整多 agent 评审修正循环，但需通过准入检查清单确认信息充分性。

---

## 核心原则

不调研清楚背景和约束就开始标杆研究，等同于盲人摸象。必须与用户通过**多次交互式提问**逐层深入，禁止一次性抛出所有问题。

每轮聚焦 1-2 个主题，从通用到具体逐层深入，根据用户回答动态调整后续问题方向。**问题由 architect agent 根据本次产品上下文动态生成，不预写固定问题清单。**

---

## 执行方式

交互式前置调研由**派遣 architect agent 执行**，主会话负责搬运产出到对话正文。

> **关键事实**：用户看不到 Agent 工具的返回内容，只能看到主会话输出的文本。主会话必须将 architect agent 的交互式提问**完整搬运到对话正文**，用户才能看到问题并回答。

**主会话职责**：
1. 派遣 architect agent 执行交互式提问（按主题清单收敛，每轮 1-2 个主题）
2. 将 agent 产出的问题列表完整搬运到对话正文（不改写、不裁剪，仅格式统一为 `R{n}-Q{m}` 编号）
3. 收集用户回答后，将回答传递给 agent 继续下一轮提问
4. 最终派 architect agent 写入 domain-config.yaml + design.md 初稿

> 多轮交互编号规范见 SKILL.md「多轮交互的轮次编号规范」。

---

## 步骤 1：检查 domain-config.yaml

主会话首先检查 `.claude/domain-config.yaml` 是否存在：

**场景 A：文件不存在**（首次执行，/df:define 未执行）
- 执行完整的领域信息收集（所有主题）
- 由派遣的 architect agent 生成新的 domain-config.yaml

**场景 B：文件已存在**（/df:define 已执行过）
- 主会话读取现有配置，向用户展示
- 询问："这些信息是否仍然准确？"
- 如果准确：跳过已有字段对应的主题，只收集 design 负责的字段
- 如果需要修正：逐项确认需要修改的字段

---

## 步骤 2：交互式领域信息收集

主会话派遣 architect agent，执行多轮交互式提问。**架构师按主题清单组织对话，禁止套用预写问题。**

### 必须收敛的主题清单（agent 据此组织对话）

> 每个主题至少收敛到「目标 + 1 个关键事实」即视为闭合。具体问法、追问深度、提问顺序由 architect agent 基于产品上下文动态决定。

**A. 系统类型与定位**（场景 A 必填，场景 B 已有则跳过）
- 收敛目标：填充 `system.primary_type` + `system.sub_type`
- 关键事实：系统主类型（分布式系统/OS/编译器/网络栈等）、子类型

**B. 系统规模与团队**（场景 A 必填，场景 B 已有则跳过）
- 收敛目标：填充 `system.complexity` + `team_size` + `codebase_size`
- 关键事实：复杂度量级（small/medium/large/very-large）、团队规模、目标代码量级

**C. 编程语言与工具链**（design 负责，必填）
- 收敛目标：填充 `languages.primary`（含 name/version/toolchain）
- 关键事实：主语言（C/C++/Rust/Go/Python/Java 等）、版本/标准、工具链。如多语言需明确主次定位

**D. 标杆产品清单**（design 负责，必填）
- 收敛目标：填充 `benchmarks` 列表
- 关键事实：用户希望对比的 2-3 个标杆产品（agent 可基于产品定位主动建议候选，由用户确认/修正）

**E. 架构约束**（design 负责，必填）
- 收敛目标：填充 `architecture.distributed` / `architecture.concurrency` / `architecture.memory`
- 关键事实：一致性模型（强一致/最终一致/因果一致）、并发模型（单线程/多线程/事件驱动/Actor）、内存管理策略（手动/GC/混合）

**F. 性能基线量化**（design 负责，必填）
- 收敛目标：填充 `quality_attributes.targets`
- 关键事实：至少 3 个可量化指标，覆盖延迟（P50/P99/P99.9）、吞吐（单节点/集群）、扩展性（节点数范围）

**G. 质量属性优先级**（场景 A 必填，场景 B 已有则跳过）
- 收敛目标：填充 `quality_attributes.priorities`
- 关键事实：1-5 排序（一致性/性能/可用性/可维护性/成本）

**H. 系统目标与边界**（design 负责，必填）
- 收敛目标：填充 `system.goal` + `system.non_goals`
- 关键事实：解决什么问题、明确不做什么（≥ 2-3 项 non-goal）

**I. 部署拓扑与规模量级**（design 负责，必填）
- 收敛目标：填充 `system.deployment`
- 关键事实：部署形态、节点规模量级

### Agent prompt 必须包含的约束

主会话派遣 architect agent 时，prompt 必须显式注入以下段落：

```markdown
## 交互式调研约束

- ✅ 按主题清单收敛，每轮聚焦 1-2 个主题
- ✅ 问题编号使用 `R{n}-Q{m}` 格式（如 R1-Q1、R2-Q2）
- ✅ 根据用户回答动态调整下一轮提问方向，不预设固定问题序列
- ✅ 涉及标杆产品候选时，可基于产品定位主动建议 2-3 个候选供用户选择
- ❌ 禁止一次性抛出所有主题的问题（用户疲劳）
- ❌ 禁止套用预写问题清单（如固定的"一致性模型选项 A/B/C/D"），应根据本次产品上下文动态产出
- ❌ 禁止在主题未闭合前进入下一主题
```

---

## 步骤 3：生成配置文件和文档

所有主题闭合后，主会话派 architect agent 完成落盘工作。

### 3.1 生成/更新 domain-config.yaml

agent 任务：
1. 读取 `.claude/templates/domain-config.yaml` 模板
2. 将收集到的字段填充进模板
3. 场景 A：写入完整文件
4. 场景 B：仅更新 design 负责的字段（保留 define 已生成字段）
5. 写入 `.claude/domain-config.yaml`

### 3.2 生成 design.md 初稿

agent 任务：
1. 读取 `.claude/templates/arch-system.md` 模板
2. 将调研结论整理为 design.md 初稿（WIP 状态，不含具体方案）
3. 包含：系统目标、核心约束、规模量级、明确不做的事项、性能基线
4. 写入 `docs/architecture/design.md`
5. 文档末尾标记 `**文档状态**: 第 0 阶段 - WIP（标杆研究待启动）`

主会话收到 agent 写入完成的摘要后，用 `ls` 验证文件存在。

---

## 出口标准

### 准入检查清单（豁免评审循环，但需准入清单）

> 第 0 阶段是交互式信息收集，用户可能在部分主题上尚未想清楚。核心项是进入标杆研究的前提，补充项可延后到第 1 阶段开始前逐步闭合——不必一次性收齐所有信息才推进。

**核心项**（必须闭合才能进入第 1 阶段）：

- [ ] `.claude/domain-config.yaml` 已存在或已生成
- [ ] `system.primary_type` + `system.sub_type` 已填充
- [ ] `languages.primary` 至少一个主语言（含版本和工具链）
- [ ] `benchmarks` 列表已填充（至少 2-3 个标杆产品）
- [ ] `system.goal` 已明确（一句话能描述系统目标）
- [ ] `docs/architecture/design.md` 初稿已写入并验证存在

**补充项**（可在第 1 阶段进行中逐步闭合，但需在第 1 阶段评审前完成）：

- [ ] `architecture.distributed` / `concurrency` / `memory` 已填充（如适用）
- [ ] `quality_attributes.targets` 至少 3 个量化指标
- [ ] `quality_attributes.priorities` 已排序
- [ ] `system.non_goals` 已列出（≥ 2-3 个明确不做的事项）
- [ ] 用户已确认定位摘要无误

### 自动推进规则

核心项全部通过 → 可进入第 1 阶段（标杆研究），补充项并行推进。

核心项未全部通过 → 继续派遣 architect agent 补充交互式提问，直至核心项闭合。

补充项未全部通过 → 第 1 阶段可启动，但主会话需在第 1 阶段评审前确认补充项已闭合。
