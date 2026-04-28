---
name: product/design
description: 架构探索与决策 skill。采用多 agent 深度思考模式，强调标杆研究先行、方案对比、长时间迭代。禁止快速产出，强制螺旋式完善
allowed-tools: [Read, Write, Edit, Bash, Grep, Glob, Agent]
---

# product/design — 架构探索与决策

## 概述

架构探索是**长期、深度、迭代**的过程，不是单次对话能完成的。本 skill 通过持续多个阶段的思考-研究-对比-完善循环，产出高质量的架构设计。

**核心原则**：
1. **标杆先行**：不研究业界方案，不允许提出自研方案
2. **深度对比**：至少 3 个候选方案，每个方案必须有明确的取舍分析
3. **长时间迭代**：架构文档需要 5-20 个阶段才能定稿，禁止一次对话定架构
4. **方案 > 代码**：聚焦设计决策和 rationale，不讨论具体代码实现
5. **模板即法源**：所有正式交付文档的内���结构、必填章节、自检清单以 `.claude/templates/*.md` 为唯一标准

---

## 文档写入铁律

**每一阶段迭代的产出必须写入项目文件，禁止仅在对话中输出。**

详细规则见 `common.md`。

**执行规则**：
1. Agent 产出内容后，**主会话必须立即将内容写入对应文件**
2. 写入完成后才能向用户汇报"本阶段完成"
3. 验收检查必须包含"文件是否已写入"这一项
4. **写入后必须验证文件存在**（`ls` 确认文件已落盘）

---

## 通用规范

本 skill 遵守 `common.md` 中定义的通用规范，包括：
- 评审与修正记录规范
- 通用术语（问题分级、评审结论三态、修正工作量分级）
- 标准评审修正循环
- 主会话职责边界

> 主会话启动时或进入阶段时，如果 `common.md` 未加载，必须先读取。

---

## 复杂度判定

| 阶段 | 内容类型 | 基准复杂度 | agent 配置 |
|------|---------|-----------|-----------|
| 第 0 阶段 | 交互式信息收集 | 低 | 1 个 architect |
| 第 1 阶段 | 标杆研究 | 中等 | 每个标杆 2 个 researcher + 2 个 reviewer |
| 第 2 阶段 | 方案发散 | 极高/高 | Step 1: ≥5 个 architect; Step 4: 每个维度 ≥3 个 architect |
| 第 3 阶段 | 评估收敛 | 极高/高 | Step 1: ≥5 个 architect; Step 3: 每个子系统 ≥3 个 architect |
| 第 4 阶段 | 维护模式 | 低 | 1 个对应角色 agent |

**决策属性上调**：
- 涉及「跨子系统边界」或「一致性关键路径」→ 复杂度 +1 级
- 涉及「不可逆决策」→ 复杂度 +1 级
- 「无现成方案」（需原创设计）→ 复杂度 +1 级

---

## 启动检测

**核心原则**：状态汇报必须以 `ls`/`wc`/`Read` 扫描文件系统的**实时结果**为准。

**检测命令**：
```bash
ls -la docs/architecture/
ls -la docs/architecture/decisions/
ls -la docs/architecture/reference/
```

**状态判定**：
- design.md 不存在 → 第 0 阶段
- design.md 存在但 reference/ 下无标杆研究 → 第 1 阶段
- reference/ 有文件但 decisions/ 下无决策文档 → 第 2 阶段
- decisions/ 有文件但 design.md 未定稿 → 第 3 阶段
- 全部文档已定稿 → 第 4 阶段（维护模式）

---

## 执行流程

### 第 0 阶段：前置调研与定位确认

**准入条件**：无
**产出文件**：`docs/architecture/design.md`（初稿）
**详细规则**：📖 读取 `00-research-prep.md`

> 主会话进入本阶段时，必须先读取 `00-research-prep.md` 获取详细执行规则。

### 第 1 阶段：标杆研究

**准入条件**：第 0 阶段完成，`design.md` 初稿已落盘
**产出文件**：`docs/architecture/reference/<product>.md`（每个标杆一个文件，至少 2-3 个）
**详细规则**：📖 读取 `01-benchmarking.md`

> 主会话进入本阶段时，必须先读取 `01-benchmarking.md` 获取详细执行规则。

### 第 2 阶段：方案发散

**准入条件**：第 1 阶段完成，标杆研究通过评审（≥ 0.80）
**产出文件**：`docs/architecture/decisions/decision-overall.md` + `docs/architecture/decisions/decision-<维度>.md`
**详细规则**：📖 读取 `02-divergence.md`

> 主会话进入本阶段时，必须先读取 `02-divergence.md` 获取详细执行规则。

### 第 3 阶段：评估收敛与文档定稿

**准入条件**：第 2 阶段完成，所有决策文档通过评审（≥ 0.80）
**产出文件**：`docs/architecture/adr.md` + `docs/architecture/design.md`（定稿）+ `docs/architecture/<subsystem>/design.md`
**详细规则**：📖 读取 `03-convergence.md`

> 主会话进入本阶段时，必须先读取 `03-convergence.md` 获取详细执行规则。

### 第 4 阶段：架构维护与扩展

**准入条件**：第 3 阶段完成，所有架构文档已定稿（≥ 0.85）
**产出文件**：按需修正现有文档
**详细规则**：📖 读取 `04-maintenance.md`

> 主会话进入本阶段时，必须先读取 `04-maintenance.md` 获取详细执行规则。

---

## 输出位置

### 本 Skill 产出（仅限 `docs/architecture/`）

- `docs/architecture/design.md` — 系统架构总纲
- `docs/architecture/adr.md` — ADR 索引
- `docs/architecture/decisions/` — 架构决策文档
- `docs/architecture/<subsystem>/design.md` — 子系统架构
- `docs/architecture/reference/<product>.md` — 标杆架构分析

### 本 Skill 不产出

| 目录/文件 | 归属命令 |
|-----------|---------|
| `docs/requirements/` | `/df:define` |
| `docs/iteration-plan/` | `/df:plan` |
| `docs/test-strategy.md` | `/df:test-design` |

---

## 红旗信号

- 未做前置调研就进入标杆研究
- 标杆研究文档 < 2 个
- 候选方案只有 1 个
- 方案描述中代码细节 > 设计 rationale
- 单次对话内完成"研究→方案→文档"
- Agent 产出内容未写入项目文件
- 架构文档未经独立评审直接定稿
- design.md 总纲未产出前就产子系统文档

---

## 与用户协作模式

**三种协作节奏**（详见 CLAUDE.md「Skill 执行行为规范」）：
1. **自动推进**：阶段内产出→评审→修正循环自动执行
2. **确认后推进**：阶段完成后汇报，等待用户确认再进入下一阶段
3. **等待人工决策**：信息缺失、方向选择、置信度 < 0.70 时停止

**正常流程**：汇报状态 → 提出执行计划 → 自动执行 → 汇报结果摘要
