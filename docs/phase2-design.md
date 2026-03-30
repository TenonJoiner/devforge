# Phase 2 设计文档：产品级核心 + 分发基础设施

## 目标

建立产品级文档生产能力、骨架工作流规范，为后续代码级能力提供上层约束。

## 前置依赖

- Phase 1（schema 可用）：spec-driven-enhanced schema 已定义且通过验证

## 为什么产品级先于代码级？

1. **spec-driven-enhanced schema 的 instruction 依赖产品级文档**：proposal 需追溯 iteration-plan、spec 需追溯 requirements、design 需参考 architecture
2. **R1 `workflow` 是整个四层体系的骨架规则**：代码级 skill 应在其约束下开发

---

## 交付物设计

### 2.1 Skill: `product/architect`（架构探索与决策）

**文件路径**：`.claude/skills/product/architect/SKILL.md`

**解决**：P1（缺少产品级规划视角）

**执行角色**：`architect`(A1)

**设计思路**：
- 与 OpenSpec 彻底脱离，按思考模式辅助设计——产品级设计是持续数月的创意迭代过程，重要的是**输出质量**而非**流程控制**
- 可反复使用：架构可以反复迭代，子系统划分可以重新调整，技术选型可以随着认知升级而重新评估
- 没有"完成"状态，只有"当前最佳版本"

**SKILL.md 结构**：

```yaml
---
name: product/architect
description: Use when 需要探索产品架构方案、进行竞品分析、分解子系统、或制定重大技术决策
version: 1.0.0
allowed-tools: [Read, Write, Edit, Bash, Grep, Glob, Agent]
---
```

**正文内容**：

```markdown
# product/architect — 架构探索与决策

## Overview

架构探索与决策 Skill —— 发散思考 → 多方案对比 → 收敛决策。

**Core Principle**: 每个重大架构决策前必须经历完整的探索-对比-收敛过程。

## When to Use

- 系统架构设计（子系统分解、技术选型）
- 竞品分析和方案对比
- 重大技术决策（一致性模型、存储引擎、协议选择）
- 架构重构或技术债务清理评估

**不适用场景**：
- 具体特性实现细节（使用 `/ky:tdd`）
- 代码级 bug 修复（使用 `/ky:debug`）
- 已有明确方案的增量开发

## The Iron Law

```
重大决策必须产出 ADR（Architecture Decision Record）
每个架构方案必须至少对比 3 个候选方案
只有一个候选方案时，禁止进入收敛阶段
```

## 核心流程

### 阶段 1：发散思考（Diverge）

**目标**：尽可能全面地收集信息、生成候选方案。

**启发方法**：
- **竞品分析框架**：技术方案对比矩阵（功能/性能/一致性/可运维性/社区活跃度）
- **多方案探索**：强制生成至少 3 个候选方案，包括：
  - 保守方案（基于现有技术栈）
  - 激进方案（采用新技术/新架构）
  - 折中方案（平衡风险与收益）

**输出**：候选方案列表（每个方案包含：名称、核心思路、适用场景、主要风险）

### 阶段 2：多方案对比（Compare）

**目标**：从多个维度评估每个候选方案。

**质量属性五维评估**：

| 维度 | 评估要点 | 关键指标 |
|------|---------|---------|
| 性能 | 吞吐、延迟、扩展性 | QPS、P99 延迟、水平扩展能力 |
| 一致性 | 数据一致性模型、故障后完整性 | 强一致/最终一致、副本一致性 |
| 可靠性 | 故障恢复、容错能力、可用性 | MTTR、MTBF、多副本策略 |
| 可维护性 | 代码复杂度、运维难度、监控能力 | 圈复杂度、故障定位时间 |
| 扩展性 | 功能扩展、容量扩展、接口兼容 | 插件机制、平滑扩容 |

**Trade-off 分析**：
- 对每个维度，列出各方案的得分（高/中/低）
- 明确标注每个方案的取舍点（如：高一致性 vs 高性能）
- 识别不可接受的缺陷（如：数据丢失风险）

### 阶段 3：收敛决策（Converge）

**目标**：选择最优方案并记录决策过程。

**置信度守门**（五项加权评估）：

| 评估项 | 权重 | 评估标准 |
|--------|------|---------|
| 问题理解充分度 | 25% | 是否充分理解问题域、约束条件、利益相关方需求 |
| 方案可行性验证 | 25% | 是否有 PoC 验证、原型测试结果、或业界成功案例 |
| 业界方案调研 | 20% | 是否调研同类产品的解决方案及其演进历史 |
| 风险识别 | 15% | 是否识别并评估了主要技术风险及缓解措施 |
| 团队共识 | 15% | 是否与关键干系人沟通并达成一致 |

**决策规则**：
- ≥90%：可以推进，产出 ADR
- 70-89%：**禁止产出 ADR**。必须列出继续调研项，补充信息后重新评估
- <70%：**立即停止**。返回发散阶段，重新审视问题定义

**用户审批门**：ADR 草稿完成后，必须经用户确认"接受此决策"方可写入文件。若用户提出修改意见，更新后重新进入审批。

**ADR 输出格式**（写入 `docs/architecture/` 或 `docs/adr.md`）：

```markdown
## ADR-XXX: <决策标题>

- **状态**: 已接受 / 已否决 / 已替代
- **日期**: YYYY-MM-DD
- **决策人**: <姓名>

### 背景

<问题描述和上下文>

### 候选方案

| 方案 | 优点 | 缺点 |
|------|------|------|
| A: xxx | ... | ... |
| B: xxx | ... | ... |
| C: xxx | ... | ... |

### 决策

选择 **方案 X**，因为...

### 影响

- 正面影响：...
- 负面影响：...
- 风险：...

### 替代方案排除理由

...
```

## Red Flags

- 🚩 只有一个候选方案（无比较即无决策）
- 🚩 方案描述只有优点没有缺点（不诚实）
- 🚩 未考虑团队技术栈和运维能力（不可落地）
- 🚩 重大决策无 ADR（不可追溯）
- 🚩 置信度 <70% 仍强行推进（高风险）

## Common Rationalizations

| 借口 | 现实 |
|------|------|
| "时间紧，先做一个再说" | 后期返工成本远高于前期探索 |
| "业界都用这个，我们也用" | 你的场景可能与业界不同，需要评估适配成本 |
| "这个方案太保守/太激进" | 保守和激进是相对的，关键是匹配当前团队阶段 |
| "先上线再优化" | 架构缺陷往往无法后期修补，必须在设计阶段解决 |

## Verification Checklist

- [ ] 至少对比了 3 个候选方案
- [ ] 完成了五维质量属性评估
- [ ] 每个方案的取舍点已明确
- [ ] 置信度 ≥90% 或明确记录了继续调研项
- [ ] 重大决策已产出 ADR
- [ ] 输出文档已保存到 docs/architecture/ 或 docs/adr.md

## Integration

- **前置 Skill**: 无（可作为起点）
- **后续 Skill**: `/ky:define`（基于架构分解定义需求）、`/ky:plan`（基于架构制定迭代计划）
- **协作 Agent**: `architect`(A1)
- **相关 Rules**: R1 `workflow`（四层工作流规范）
```

---

### 2.2 Skill: `product/define`（定义性思考）

**文件路径**：`.claude/skills/product/define/SKILL.md`

**解决**：P1（缺少产品级规划视角）

**执行角色**：`architect`(A1)

**设计思路**：
- Feature-Scenario 两级结构，Scenario 是独立验收单元
- 需求定义必须有明确的验收标准（铁律：每个 Scenario 可独立编写测试用例验收）
- 接口契约完整（输入/输出/错误码/一致性语义/幂等性/版本兼容）

**SKILL.md 结构**：

```yaml
---
name: product/define
description: Use when 需要定义产品需求、设计接口契约、制定验收标准
version: 1.0.0
allowed-tools: [Read, Write, Edit, Bash, Grep, Glob, Agent]
---
```

**正文内容**：

```markdown
# product/define — 定义性思考

## Overview

定义性思考 Skill —— 场景驱动 → 精确定义 → 场景独立可验收。

**Core Principle**: 每个需求必须可独立验收，每个接口必须有完整的错误处理契约。

## When to Use

- 定义产品需求规格（requirements/）
- 设计子系统间接口契约（interfaces/）
- 制定功能验收标准
- 量化非功能需求（性能/可用性/容量）
- 接口变更或版本升级设计

**不适用场景**：
- 架构方向探索（使用 `/ky:architect`）
- 迭代计划制定（使用 `/ky:plan`）
- 具体代码实现（使用 `/ky:tdd`）

## The Iron Law

```
每个 Scenario 必须可独立编写测试用例验收
每个接口必须定义错误处理契约（错误码/异常/回退行为）
```

## 核心流程

### 阶段 1：Feature 识别

**目标**：从用户视角识别能力分组。

**方法**：
- 识别用户角色（管理员/开发者/运维/客户端）
- 按用户目标分组（如：数据读写、集群管理、监控告警）
- 检查与现有 Feature 的关系（新增/修改/废弃）

### 阶段 2：Scenario 挖掘

**目标**：为每个 Feature 定义完整的 Scenario 集合。

**Feature-Scenario 格式**：

```markdown
## Feature: <特性名称>

**做什么**：该特性提供的能力和行为

**为什么**：为什么需要这个特性，解决什么问题或带来什么价值

### Scenario: <场景名称>

**前置条件**：系统处于什么状态

**触发动作**：用户/系统执行什么操作

**预期行为**：系统应产生什么结果

**验证方法**：具体的测试手段（可独立编写测试用例验收）
```

**必须覆盖的场景类型**：

| 类型 | 说明 | 示例 |
|------|------|------|
| 正常路径 | 标准使用流程 | 客户端写入数据成功 |
| 节点故障 | 单节点宕机 | 写入时副本节点宕机，数据不丢失 |
| 网络分区 | 网络隔离/脑裂 | 网络分区期间写入，恢复后数据一致 |
| 并发冲突 | 多客户端竞争 | 并发写入同一 key，按版本号解决冲突 |
| 磁盘故障 | IO 错误/磁盘满 | 磁盘满时拒绝写入并返回明确错误码 |

**分布式场景强制要求**：每个涉及分布式交互的 Feature 必须覆盖至少 4 种故障模式。

### 阶段 3：接口契约设计

**目标**：定义清晰的接口边界和行为契约。

**接口规格包含**：

| 要素 | 说明 | 示例 |
|------|------|------|
| 输入 | 参数名、类型、取值范围、必填/可选 | `key: string, max_len=256, required` |
| 输出 | 返回值结构、字段含义 | `{status: enum, data: object}` |
| 错误码 | 错误类型、错误码、错误信息 | `ENOMEM: 内存不足` |
| 一致性语义 | 读写一致性保证 | `强一致 / 最终一致` |
| 幂等性 | 重复调用是否安全 | `幂等 / 非幂等（需去重）` |
| 版本兼容 | API 版本、兼容性策略 | `v2，向后兼容至 v1.5` |

**错误处理契约铁律**：
- 每个错误码必须有明确的业务含义
- 每个错误必须有预期的客户端回退行为
- 错误信息必须包含足够的诊断信息（但不得泄露敏感数据）

### 阶段 4：非功能需求量化

**目标**：将性能、可用性、容量等需求转化为可测试的指标。

| 类型 | 量化指标 | 验收标准示例 |
|------|---------|-------------|
| 性能 | 吞吐、延迟 | P99 写入延迟 < 10ms，单节点 QPS > 10K |
| 可用性 | SLA、MTTR | 年度可用性 ≥ 99.99%，MTTR < 5分钟 |
| 容量 | 数据量、连接数 | 单节点支持 10TB 数据，10000 并发连接 |
| 扩展性 | 扩容粒度 | 支持在线扩容，单步增加 1 节点 |
| 一致性 | 一致性级别 | 线性一致 / 顺序一致 / 最终一致 |

## Red Flags

- 🚩 Scenario 无法独立验收（依赖其他 Scenario 的状态）
- 🚩 接口无错误处理契约（只有成功路径）
- 🚩 分布式场景未覆盖故障模式（只有 happy path）
- 🚩 非功能需求无具体数字（"高性能"、"高可用"）
- 🚩 Feature 粒度不均（有的过大有的过小）

## Common Rationalizations

| 借口 | 现实 |
|------|------|
| "错误场景太多，写不完" | 至少覆盖最可能的 4 种故障模式，其他可标注"待补充" |
| "性能指标现在定不了" | 给出预期范围和测试方法，后期可调整 |
| "这个接口很简单，不用写契约" | 简单的接口也要有错误码定义 |
| "异常路径测试太麻烦" | 分布式系统 80% 的 bug 在异常路径，必须覆盖 |

## Verification Checklist

- [ ] 每个 Feature 有清晰的"做什么"和"为什么"
- [ ] 每个 Scenario 包含前置条件、触发动作、预期行为、验证方法
- [ ] 每个接口有完整的错误处理契约
- [ ] 分布式 Feature 覆盖至少 4 种故障模式
- [ ] 非功能需求有具体量化的指标和验收标准
- [ ] 输出文档已保存到 docs/requirements/ 和 docs/interfaces/

## Integration

- **前置 Skill**: `/ky:architect`（基于架构分解定义需求）
- **后续 Skill**: `/ky:plan`（基于需求制定迭代计划）
- **协作 Agent**: `architect`(A1)
- **相关 Rules**: R1 `workflow`、R3 `coding-style`（接口命名规范）
```

---

### 2.3 Skill: `product/plan`（规划性思考）

**文件路径**：`.claude/skills/product/plan/SKILL.md`

**解决**：P1（缺少产品级规划视角）

**执行角色**：`project-manager`(A10) 编排 + `architect`(A1) 技术可行性判断

**设计思路**：
- MVP 优先识别最小可用产品的核心能力边界
- 依赖图分析 + Wave 分组最大化并行开发
- 输出 iteration-plan.md 包含 proposal 清单（含测试相关 proposal）

**SKILL.md 结构**：

```yaml
---
name: product/plan
description: Use when 需要制定迭代计划、分解 proposal、安排开发节奏、或协调多子系统并行开发
version: 1.0.0
allowed-tools: [Read, Write, Edit, Bash, Grep, Glob, Agent]
---
```

**正文内容**：

```markdown
# product/plan — 规划性思考

## Overview

规划性思考 Skill —— MVP 优先 → 依赖分析 → 最大化并行。

**Core Principle**: 计划的价值在于识别关键路径和并行机会，而非精确预测。

## When to Use

- 制定产品迭代计划（iteration-plan.md）
- 分解需求为可执行的 proposal 清单
- 识别关键路径和里程碑
- 协调多子系统并行开发
- 调整计划应对变更（范围/优先级/资源）

**不适用场景**：
- 具体技术方案设计（使用 `/ky:architect`）
- 需求定义（使用 `/ky:define`）
- 单个 proposal 的任务分解（在特性级 tasks.md 中处理）

## The Iron Law

```
每个 proposal 必须是可独立交付的最小有价值单元
关键路径上的 proposal 必须识别并优先安排
```

## 核心流程

### 阶段 1：MVP 识别

**目标**：确定最小可用产品的核心能力边界。

**方法**：
- 识别"没有它产品就无法使用"的核心能力
- 区分"必须有"（Must have）和"应该有"（Should have）
- 考虑技术依赖：某些能力可能是其他能力的前置条件

**MVP 边界检查清单**：
- [ ] 用户能否完成最核心的操作？
- [ ] 系统能否在最小配置下运行？
- [ ] 是否有完整的端到端流程？
- [ ] 是否可以部署并获得反馈？

### 阶段 2：Proposal 分解

**目标**：将需求分解为可独立交付的 proposal 清单。

**分解原则**：

| 原则 | 说明 | 示例 |
|------|------|------|
| 单一职责 | 每个 proposal 只做一件事 | "实现写入缓存"而非"实现读写缓存" |
| 可独立交付 | 完成后可独立验证价值 | "完成数据分片路由"可单独测试 |
| 粒度适中 | 1-4 周工作量，过大则拆分 | 超过 4 周拆分为多个 proposal |
| 可追踪 | 能追溯到需求文档的具体条目 | 关联 docs/requirements/xxx.md#Feature-Y |

**命名规范**：
- 使用 kebab-case（短横线连接的小写）
- 格式：`<子系统>-<动作>-<对象>`
- 示例：`storage-write-buffer`、`metadata-raft-election`、`network-connection-pool`

### 阶段 3：依赖分析

**目标**：识别 proposal 之间的依赖关系，构建依赖图。

**依赖类型**：

| 类型 | 说明 | 示例 |
|------|------|------|
| 数据依赖 | A 的输出是 B 的输入 | 存储引擎需要先实现分片，才能做副本 |
| 接口依赖 | A 定义的接口被 B 使用 | 元数据服务先定义 API，客户端才能调用 |
| 资源依赖 | A 和 B 竞争同一资源 | 两个 proposal 修改同一核心数据结构 |

**依赖图构建**：
```
proposal-a ──┬──┐
             │  │
proposal-b ──┤  ├──→ proposal-d
             │  │
proposal-c ──┴──┘
```

### 阶段 4：Wave 分组

**目标**：将无依赖的 proposal 分组，最大化并行开发。

**分组方法**：
- Wave 0：无依赖的 proposal（可立即启动）
- Wave 1：仅依赖 Wave 0 的 proposal
- Wave 2：仅依赖 Wave 0/1 的 proposal
- ...依此类推

**并行约束**：
- 同一 Wave 内的 proposal 可并行开发
- 跨 Wave 的 proposal 有先后顺序
- 同子系统的 proposal 可能需要串行（避免冲突）

### 阶段 5：复杂度估算

**目标**：为每个 proposal 估算复杂度，辅助排期。

**三档估算**：

| 档位 | 工作量 | 风险等级 | 说明 |
|------|--------|---------|------|
| S (Small) | < 1 周 | 低 | 明确的需求，清晰的实现路径 |
| M (Medium) | 1-2 周 | 中 | 有一定技术挑战，需要调研 |
| L (Large) | 2-4 周 | 高 | 复杂度高，可能遇到未知问题 |

**估算原则**：
- 技术债务清理通常低估，需 +50% 缓冲
- 涉及多子系统的 proposal 需 +1 档复杂度
- 首次使用的新技术需 +1 档复杂度

### 阶段 6：测试相关 Proposal 生成

**目标**：确保测试能力与开发能力同步规划。

**测试 proposal 类型**：

| 类型 | 说明 | 命名示例 |
|------|------|---------|
| 集成测试 | 跨组件交互验证 | `test-integration-replication` |
| 系统测试 | 端到端场景验证 | `test-system-failover` |
| 性能测试 | 基准/压力/回归测试 | `test-perf-write-throughput` |
| 故障注入 | 故障场景验证 | `test-fault-disk-corruption` |

**测试 proposal 关联**：
- 每个测试 proposal 关联到开发 proposal
- 测试方案来源：`/ky:test-design` 输出的 test-strategy.md

## 输出格式（iteration-plan.md）

```markdown
# 迭代计划

## 迭代目标

<本迭代要达成的核心目标>

## Wave 分组

### Wave 0（立即启动）

| Proposal | 子系统 | 复杂度 | 关联需求 | 备注 |
|----------|--------|--------|----------|------|
| xxx | storage | M | requirements/io.md#Feature-X | 阻塞 Wave 1 |

### Wave 1（依赖 Wave 0）

...

## 关键路径

```
[proposal-a] → [proposal-b] → [proposal-d]
```

关键路径长度：X 周

## 里程碑

| 日期 | 里程碑 | 达成标准 |
|------|--------|---------|
| YYYY-MM-DD | MVP 可用 | Wave 0/1 完成，端到端流程跑通 |
| YYYY-MM-DD | Beta 发布 | Wave 0-3 完成，核心功能稳定 |

## 风险与应对

| 风险 | 影响 | 应对措施 |
|------|------|---------|
| ... | ... | ... |

## 测试相关 Proposal

| Proposal | 类型 | 关联开发 Proposal |
|----------|------|------------------|
| test-integration-xxx | 集成测试 | xxx |
```

## Red Flags

- 🚩 所有 proposal 都在 Wave 0（未识别依赖关系）
- 🚩 单个 proposal 超过 4 周（粒度太大）
- 🚩 无关键路径分析（无法识别阻塞点）
- 🚩 无测试 proposal（测试滞后风险）
- 🚩 计划过于乐观（无缓冲时间）

## Common Rationalizations

| 借口 | 现实 |
|------|------|
| "这个 proposal 依赖太多，没法并行" | 考虑拆分 proposal，提取可独立交付的部分 |
| "测试可以后面补" | 测试方案必须与开发同步设计，测试用例可与开发并行编写 |
| "计划赶不上变化，随便排一下" | 计划的价值在于识别依赖和关键路径，帮助应对变化 |
| "这个很重要，那个也很重要" | 必须识别 MVP，否则资源分散什么都做不好 |

## Verification Checklist

- [ ] 已识别 MVP 边界
- [ ] Proposal 已分解到可独立交付的粒度（1-4 周）
- [ ] 依赖关系已识别并构建依赖图
- [ ] 已完成 Wave 分组
- [ ] 已估算每个 proposal 的复杂度
- [ ] 已生成测试相关 proposal 清单
- [ ] 已识别关键路径
- [ ] 已定义里程碑和达成标准
- [ ] 已评估主要风险并制定应对措施

## Integration

- **前置 Skill**: `/ky:architect`（架构确定后制定计划）、`/ky:define`（需求明确后分解）
- **后续 Skill**: `/ky:test-design`（基于计划设计测试方案）、`/ky:product-review`（评审计划合理性）
- **协作 Agent**: `project-manager`(A10) 编排 + `architect`(A1) 技术可行性判断
- **相关 Rules**: R1 `workflow`、R2 `git-workflow`（分支策略）
- **与特性级衔接**: iteration-plan.md 的 proposal 名称使用 kebab-case，团队通过 `/opsx:propose <name>` 启动特性级开发
```

---

### 2.4 Agent: `architect`（架构师）

**文件路径**：`.claude/agents/architect.md`

**解决**：P1, P2

**定位**：系统架构设计、子系统分解、技术选型、ADR、需求分解分配

**关注点**：数据分布策略、副本一致性模型、故障域划分、存储引擎分层（元数据/数据/索引）、IO 路径设计

**Agent 格式**：

```yaml
---
name: architect
description: PROACTIVELY USE when 执行 /ky:architect、/ky:define、/ky:product-review、/ky:verify，或需要架构设计、技术选型、子系统分解、ADR 编写
model: opus
tools: ["Read", "Write", "Edit", "Bash", "Grep", "Glob", "Agent"]
---

# architect — 架构师

## Identity

你是分布式存储系统的架构师，专注于系统级设计和技术决策。你具备深厚的分布式系统理论基础和丰富的存储引擎设计经验。

**专业领域**：
- 分布式一致性协议（Raft/Paxos/Quorum）
- 存储引擎架构（LSM-Tree/B+树/哈希索引）
- 数据分布与副本策略（一致性哈希/范围分片）
- 故障域划分与容灾设计
- IO 路径优化（零拷贝/异步 IO/批处理）
- 性能与可靠性的权衡

## Core Mission

1. **架构设计**：设计可扩展、高可用的分布式存储架构
2. **技术选型**：为关键决策选择最合适的技术方案
3. **子系统分解**：合理划分模块边界，定义交互接口
4. **ADR 编写**：记录重大技术决策及其理由
5. **需求分配**：将产品需求映射到子系统职责

**优先级**：数据一致性 > 可靠性 > 性能 > 可维护性

## Critical Rules

1. **每个重大决策必须产出 ADR**，包含至少 3 个候选方案的对比
2. **数据一致性优先**：在一致性和性能的权衡中，默认选择更强的一致性
3. **故障常态假设**：设计必须考虑节点故障、网络分区、磁盘损坏是常态
4. **接口先行**：子系统间接口必须在实现前明确定义
5. **量化评估**：技术选型必须有可量化的评估标准（延迟/吞吐/可用性）
6. **可演进性**：架构必须支持在线升级和平滑演进
7. **不重复造轮子**：优先使用经过验证的成熟方案

## Workflow

### 架构探索模式（/ky:architect）

1. 收集背景信息和约束条件
2. 生成至少 3 个候选架构方案
3. 从五维质量属性（性能/一致性/可靠性/可维护性/扩展性）评估各方案
4. 计算置信度：
   - ≥90%：产出 ADR 草稿，提交用户审批，确认后写入文件
   - 70-89%：列出继续调研项，禁止产出 ADR
   - <70%：立即停止，返回发散阶段重新审视问题
5. ADR 经用户确认后记录到 docs/architecture/ 或 docs/adr.md

### 定义模式（/ky:define）

1. 基于架构分解识别 Feature 边界
2. 为每个 Feature 定义完整的 Scenario 集合（正常+4种故障模式）
3. 设计子系统间接口契约（输入/输出/错误码/一致性语义）
4. 量化非功能需求（性能指标/可用性 SLA/容量限制）
5. 输出到 docs/requirements/ 和 docs/interfaces/

### 评审模式（/ky:product-review）

1. 检查跨文档一致性（架构↔需求↔接口）
2. 识别红旗信号（无 ADR 的重大决策、无故障场景的接口等）
3. 评估设计完备性（每个子系统有架构、每个特性有需求）
4. 输出评审意见（CRITICAL/HIGH/MEDIUM/LOW 分级）

### 验证模式（/ky:verify）

1. 对比产品级文档与特性级 spec/design/code
2. 识别不一致点
3. 判断同步方向（上行同步/下行修正）
4. 输出不一致清单 + 方向建议

## Deliverables

### ADR 模板

```markdown
## ADR-XXX: <决策标题>

- **状态**: 已接受
- **日期**: YYYY-MM-DD
- **决策人**: architect

### 背景

### 候选方案

| 方案 | 优点 | 缺点 |
|------|------|------|
| A | ... | ... |
| B | ... | ... |
| C | ... | ... |

### 决策

### 影响

### 替代方案排除理由
```

### 架构文档模板

```markdown
# <子系统> 架构设计

## 概述

## 职责边界

## 关键数据结构

## 并发模型

## 错误处理策略

## 接口定义

## 部署拓扑
```

## Success Metrics

- 每个重大技术决策有 ADR
- 架构文档覆盖所有子系统
- 接口定义先于实现完成
- 故障场景覆盖率 ≥80%

## Communication Style

- **直接指出问题**：不说"有趣"，说"这里有风险"
- **提供具体建议**：每个问题附带可行的修复方案
- **量化优先**：用数据支撑观点（"延迟增加 2x"而非"性能下降"）
- **承认不确定性**：不确定时明确标注，不猜测
```

---

### 2.5 Command: `/ky:architect`

**文件路径**：`.claude/commands/explore.md`

**映射 Skill**: `product/architect`

**Command 格式**：

```markdown
# /ky:architect

探索产品架构方案、竞品分析、子系统分解。

## 何时使用

- 系统架构设计
- 重大技术决策
- 竞品分析和方案对比
- 架构重构评估
- 子系统分解调整

## 执行流程

1. 激活 `architect` Agent
2. 进入 `product/architect` Skill 流程：
   - 发散思考（生成 ≥3 候选方案）
   - 多方案对比（五维质量属性评估）
   - 收敛决策（置信度守门 + ADR 输出）
3. 输出保存到 docs/architecture/ 和 docs/adr.md

## 参数

无参数。交互式引导。

## 示例

```
/ky:architect
> 你想探索什么方向？
> 1. 新的存储引擎架构
> 2. 一致性协议选择
> 3. 子系统分解调整
```

## 输出物

- docs/architecture/<subsystem>.md（如适用）
- docs/adr.md（ADR 记录）

## 关联

- Skill: `product/architect`
- Agent: `architect`
- Rules: R1 `workflow`
```

---

### 2.6 Command: `/ky:define`

**文件路径**：`.claude/commands/define.md`

**映射 Skill**: `product/define`

**Command 格式**：

```markdown
# /ky:define

定义产品需求、接口契约、验收标准。

## 何时使用

- 定义产品需求规格
- 设计子系统间接口
- 制定验收标准
- 量化非功能需求

## 执行流程

1. 激活 `architect` Agent
2. 进入 `product/define` Skill 流程：
   - Feature 识别
   - Scenario 挖掘（正常+4种故障模式）
   - 接口契约设计
   - 非功能需求量化
3. 输出保存到 docs/requirements/ 和 docs/interfaces/

## 参数

无参数。交互式引导。

## 示例

```
/ky:define
> 你想定义什么？
> 1. 新 Feature 的需求规格
> 2. 子系统间接口契约
> 3. 修改现有需求
```

## 输出物

- docs/requirements/<feature-domain>.md
- docs/interfaces/<subsystem>.md

## 关联

- Skill: `product/define`
- Agent: `architect`
- Rules: R1 `workflow`
```

---

### 2.7 Command: `/ky:plan`

**文件路径**：`.claude/commands/plan.md`

**映射 Skill**: `product/plan`

**Command 格式**：

```markdown
# /ky:plan

制定迭代计划和 proposal 清单。

## 何时使用

- 制定产品迭代计划
- 分解需求为 proposal 清单
- 识别关键路径和里程碑
- 协调多子系统并行开发

## 执行流程

1. 激活 `project-manager` + `architect` Agents
2. 进入 `product/plan` Skill 流程：
   - MVP 识别
   - Proposal 分解
   - 依赖分析
   - Wave 分组
   - 复杂度估算
   - 测试相关 Proposal 生成
3. 输出保存到 docs/iteration-plan.md

## 参数

无参数。交互式引导。

## 示例

```
/ky:plan
> 迭代周期：3个月
> 主要目标：完成核心存储引擎
> 可用资源：5人（存储团队3人，元数据团队2人）
```

## 输出物

- docs/iteration-plan.md

## 关联

- Skill: `product/plan`
- Agents: `project-manager` + `architect`
- Rules: R1 `workflow`

## 与特性级衔接

iteration-plan.md 的 proposal 名称使用 kebab-case，团队通过 `/opsx:propose <name>` 启动特性级开发。
```

---

### 2.8 Rule: R1 `workflow`（四层工作流规范）

**文件路径**：`.claude/rules/workflow.md`

**解决**：P1-P5

**Rule 格式**：

```markdown
# 四层工作流规范

## 概述

本文档定义 teamskills 的四层工作流体系：产品级 → 特性级 → 代码级 → 测试验证级。

## 四层关系

```
产品级（启发式 Skills + /ky: 命令）
  /ky:architect ←→ /ky:define ←→ /ky:plan
      │               │              │
      ▼               ▼              ▼
  architecture/  requirements/    iteration-plan.md
       adr.md       interfaces/
      │
      │ /ky:test-design（测试策略）
      │ /ky:product-review（多维评审）
      │
      └── proposal 清单（人工执行）
          ▼
特性级（OpenSpec spec-driven-enhanced schema + /opsx:* 命令）
  proposal → specs → design → review → tasks
  → /opsx:apply → /opsx:verify → /opsx:archive
          │                               │
          │ apply 阶段调度代码级            │ 合并 Delta + 归档
          ▼                               │
代码级（teamskills /ky:* skills）
  worktree 隔离 → /ky:tdd → /ky:refactor → /ky:lint
  → /ky:review → commit
          │
          │ 单元测试通过
          ▼
测试验证级（独立测试目录 workflow + 脚本执行）
  测试用例开发（独立测试目录走专用 workflow）
  → 脚本执行（集成测试 + 性能测试）→ merge
          │
          │ 测试失败反馈代码级
          ▼
       ┌──── 变更反馈回路
       ▼
  /ky:verify: 全量双向一致性检查
```

## 各层职责

### 产品级

**目标**：架构设计、需求定义、迭代规划

**核心原则**：
- 与 OpenSpec 彻底脱离，按思考模式辅助设计
- 重要的是**输出质量**而非**流程控制**
- 可反复迭代，无固定顺序

**交付物**：
- docs/architecture/
- docs/adr.md
- docs/requirements/
- docs/interfaces/
- docs/iteration-plan.md

**触发命令**：
- `/ky:architect` — 架构探索
- `/ky:define` — 需求定义
- `/ky:plan` — 迭代计划
- `/ky:product-review` — 多维评审
- `/ky:test-design` — 测试策略
- `/ky:verify` — 一致性检查

### 特性级

**目标**：单个特性的规范驱动开发

**核心原则**：
- 基于 OpenSpec spec-driven-enhanced schema
- 流程控制严格，必须按依赖图推进
- 新增 review 门禁，TDD 粒度任务分解

**交付物**：
- proposal.md
- specs/*.md
- design.md
- review.md
- tasks.md

**触发命令**：
- `/opsx:propose <name>` — 创建 proposal
- `/opsx:continue` — 继续下一阶段
- `/opsx:apply` — 执行任务
- `/opsx:verify` — 验证实现
- `/opsx:archive` — 归档变更

### 代码级

**目标**：单个 task 的代码实现

**核心原则**：
- TDD 铁律：RED-GREEN-REFACTOR
- 自动化 Hook 守护
- worktree 隔离并行开发

**触发命令**：
- `/ky:tdd` — TDD 开发
- `/ky:review` — 代码评审
- `/ky:spec-review` — 交付件评审
- `/ky:refactor` — 代码重构
- `/ky:lint` — 编译检查
- `/ky:switch-worktree` — 切换 worktree
- `/ky:debug` — 系统化调试

### 测试验证级

**目标**：集成测试、系统测试、性能测试

**核心原则**：
- 不设 `/ky:*` 命令
- 测试用例开发在独立测试目录走 OpenSpec workflow
- 测试执行通过脚本触发

## 审批节点

| 层级 | 审批点 | 审批人 | 通过标准 |
|------|--------|--------|---------|
| 产品级 | 架构决策 | 技术委员会 | ADR 评审通过 |
| 产品级 | 迭代计划 | 产品经理+技术负责人 | 资源/时间/范围可接受 |
| 特性级 | review.md | 技术 leader | APPROVED 签字 |
| 代码级 | commit | 代码评审 | 0 CRITICAL，HIGH 已处理 |
| 测试验证级 | merge | CI 通过 | 集成/系统/性能测试通过 |

## 子系统分工

- 产品级文档维护在 `docs/` 目录
- 特性级文档维护在各子系统目录的 `openspec/changes/` 下
- 代码实现维护在各子系统目录（如 `src/storage/`、`src/metadata/` 等）
- 测试用例维护在 `tests/` 目录

## 接口对齐

- 子系统间接口定义维护在 teamskills/docs/interfaces/
- 接口变更必须更新 interfaces/ 文档
- 跨子系统特性需相关子系统评审

## 冲突解决

- 同文件修改标记为不可并行
- Wave 分组避免资源冲突
- 冲突发生时由 project-manager(A10) 协调

## 并行开发规约

1. **独立任务并行**：修改不同文件的任务可并行
2. **同文件串行**：修改同一文件的任务串行
3. **worktree 隔离**：每个并行 agent 使用独立 worktree
4. **冲突检测**：/opsx:apply 自动检测文件冲突

## 漂移信号检测

`/opsx:archive` 归档时扫描以下标签：
- 「新增发现」：spec 中标注的产品级未覆盖需求
- 「架构偏离」：design 中标注的与产品级架构偏差

**阈值**：累计超过 3 个未处理时，提示执行 `/ky:verify`

## 与 OpenSpec 的分工

| 能力 | OpenSpec 提供 | teamskills 自建 |
|------|--------------|----------------|
| Artifact 依赖图 | ✅ | — |
| Delta spec 解析 | ✅ | — |
| Schema 自定义 | ✅ | — |
| 模板系统 | ✅ | — |
| 命令系统 | ✅ | — |
| 产品级 Skills | — | ✅ |
| 代码级 Skills | — | ✅ |
| Agents | — | ✅ |
| Hooks | — | ✅ |
| Rules | — | ✅ |
```

---

### 2.9 产品级参考模板（5 个）

**文件路径**：`templates/product/{architecture,requirements,interface,iteration-plan}.md`

这些模板作为编写产品级文档的参考，团队可以按需调整格式。

---

### 2.10 产品级交付物目录骨架

**目标**：创建 docs/ 目录结构，存放产品级文档。

```
docs/
├── architecture/                      # 架构设计
│   ├── design.md                      #   系统级总纲
│   └── <subsystem>/                   #   子系统架构（按需创建）
├── adr.md                             # 架构决策记录
├── requirements/                      # 需求规格
│   └── <feature-domain>.md            #   按特性域组织
├── interfaces/                        # 接口规格
│   └── <subsystem>.md                 #   按子系统组织
└── iteration-plan.md                  # 迭代计划 + proposal 清单
```


---

## 验证计划

1. **Schema 验证**：`openspec schema validate spec-driven-enhanced` — 验证 schema 合法（Phase 1 已完成）

2. **产品级探索验证**：
   - 执行 `/ky:architect`
   - 验证启发式思考引导有效（生成 ≥3 候选方案、五维评估、ADR 输出）
   - 验证输出保存到 docs/architecture/ 和 docs/adr.md

3. **工作流集成验证**：
   - 执行 `/ky:plan` 生成 iteration-plan.md
   - 验证 proposal 清单正确关联产品级文档
   - 验证 `/opsx:propose` 能正确读取产品级约束

---

## 与 Phase 1 的关系

Phase 1 提供了特性级的基础设施（spec-driven-enhanced schema），Phase 2 在其之上建立产品级能力：

- Phase 1 的 proposal template 要求关联产品级 iteration-plan（Phase 2 产出）
- Phase 1 的 spec template 要求追溯产品级 requirements（Phase 2 产出）
- Phase 1 的 design template 要求参考产品级 architecture（Phase 2 产出）

因此 Phase 2 必须在 Phase 1 之后实施，为特性级提供上层约束。

---

## 与 Phase 3 的关系

Phase 3 将建立代码级日常工作流（TDD、代码评审、lint、worktree 等），这些能力：

- 在 Phase 2 的 R1 `workflow` 规则约束下开发
- 被 Phase 1 的 tasks.md 模板引用（TDD 步骤）

因此 Phase 3 依赖 Phase 2 完成，形成完整的四层体系。
