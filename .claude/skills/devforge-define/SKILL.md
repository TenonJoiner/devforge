---
name: product/define
description: 定义产品需求、制定验收标准。采用多 agent 深度思考模式，强调标杆研究先行、Feature-Scenario 分层展开、独立评审验证。禁止快速产出，强制螺旋式迭代完善
allowed-tools: [Read, Write, Edit, Bash, Grep, Glob, Agent]
---

# product/define — 定义性思考

## 概述

需求定义是**长期、深度、迭代**的过程，不是单次对话能完成的。本 skill 采用**多 agent 协作模式**，通过持续多个阶段的思考-研究-发散-评审-完善循环，产出高质量的需求规格文档。

> **内容规范强牵引**：需求交付件的所有内容结构、章节要求、自检清单**以 `.claude/templates/*.md` 为唯一准绳**。本 skill 只负责定义**努力程度、写作风格、质量门槛和流程控制**，不再重复模板中已有的内容要求。

**核心原则**：
1. **模板牵引**：所有产出必须严格遵循对应模板，写前先读模板是铁律
2. **标杆先行**：不研究业界同类产品的需求规格，不允许定义自研 Feature
3. **Actor 驱动**：先识别所有交互角色，再围绕角色定义场景
4. **Feature 为主**：正常场景是需求的核心，故障/异常/运维场景从完整性维度补充
5. **分层产出**：先产出 Actor-Feature 清单并评审定稿，再进入 Scenario 挖掘
6. **可验收性**：每个 Scenario 可独立验证，验收标准必须量化
7. **长时间迭代**：需求文档需要 3-10 个阶段才能定稿，禁止一次对话定需求

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
| 第 0 阶段 | 交互式信息收集 | 低 | 1 个 product-manager |
| 第 1 阶段 | 标杆研究 | 高 | 每个标杆 2 个 researcher + 2 个 reviewer |
| 第 2 阶段 | Actor-Feature 定义 | 极高 | ≥5 个 product-manager + ≥3 个 reviewer |
| 第 3 阶段 | Scenario 挖掘 | 高 | 每个 domain ≥3 个 product-manager + ≥2 个 reviewer |
| 第 4 阶段 | 维护模式 | 低 | 1 个对应角色 agent |

**决策属性上调**：
- 第 1 阶段若「无现成方案」→ 复杂度上调一级
- 第 3 阶段若涉及「跨子系统边界」+「性能/一致性关键路径」→ 复杂度上调至「高」

---

## 启动检测

**核心原则**：状态汇报必须以 `ls`/`wc`/`Read` 扫描文件系统的**实时结果**为准。

**检测命令**：
```bash
ls -la docs/requirements/
ls -la docs/requirements/reference/
ls -la docs/architecture/reference/
```

**检测清单**：
1. 执行上述三个命令
2. 对声称"已完成"的文档，用 `ls` 验证存在、用 `wc -l` 验证非空
3. 汇报每个文件时使用**完整绝对路径**
4. 若两个目录下存在同名文件，必须明确标注归属

**状态判定**：
- product-spec.md 不存在 → 第 0 阶段
- product-spec.md 存在但 reference/ 下无标杆研究 → 第 1 阶段
- reference/ 有文件但 Actor-Feature 未定稿 → 第 2 阶段
- Actor-Feature 已定稿但 <feature-domain>.md 不完整 → 第 3 阶段
- 全部文档已定稿 → 第 4 阶段（维护模式）

---

## 执行流程

### 第 0 阶段：产品定位确认

**准入条件**：无
**产出文件**：`docs/requirements/product-spec.md`
**详细规则**：📖 读取 `00-positioning.md`

> 主会话进入本阶段时，必须先读取 `00-positioning.md` 获取详细执行规则。

### 第 1 阶段：标杆研究

**准入条件**：第 0 阶段完成，`product-spec.md` 初稿已落盘
**产出文件**：`docs/requirements/reference/<product>.md`（每个标杆一个文件，至少 2-3 个）
**详细规则**：📖 读取 `01-benchmarking.md`

> 主会话进入本阶段时，必须先读取 `01-benchmarking.md` 获取详细执行规则。

### 第 2 阶段：Actor-Feature 识别与定稿

**准入条件**：第 1 阶段完成，标杆研究通过评审（≥ 0.80）
**产出文件**：`docs/requirements/product-spec.md`（Actor-Feature 章节定稿）
**详细规则**：📖 读取 `02-actor-feature.md`

> 主会话进入本阶段时，��须先读取 `02-actor-feature.md` 获取详细执行规则。

### 第 3 阶段：Scenario 挖掘与特性域定稿

**准入条件**：第 2 阶段完成，Actor-Feature 已定稿（≥ 0.85）
**产出文件**：`docs/requirements/<feature-domain>.md`（各特性域文档）
**详细规则**：📖 读取 `03-scenario.md`

> 主会话进入本阶段时，必须先读取 `03-scenario.md` 获取详细执行规则。

### 第 4 阶段：需求维护与扩展

**准入条件**：第 3 阶段完成，所有特性域文档已定稿（≥ 0.85）
**产出文件**：按需修正现有文档
**详细规则**：📖 读取 `04-maintenance.md`

> 主会话进入本阶段时，必须先读取 `04-maintenance.md` 获取详细执行规则。

---

## 输出位置

### 本 Skill 产出（仅限 `docs/requirements/`）

- `docs/requirements/product-spec.md` — 全局需求总纲
- `docs/requirements/<feature-domain>.md` — 按特性域组织的需求规格
- `docs/requirements/reference/<product>.md` — 标杆需求分析

### 本 Skill 不产出

| 目录/文件 | 归属命令 |
|-----------|---------|
| `docs/architecture/` | `/df:design` |
| `docs/iteration-plan/` | `/df:plan` |
| `docs/test-strategy.md` | `/df:test-design` |

---

## 红旗信号

- 未做产品定位确认就进入标杆研究
- 标杆研究文档 < 2 个
- Feature 只有名称没有"为什么"论证
- 验收标准无法量化
- 单次对话内完成"研究→Feature→Scenario→文档"
- Agent 产出内容未写入项目文件
- 需求文档未经独立评审直接定稿

---

## 与用户协作模式

**三种协作节奏**（详见 CLAUDE.md「Skill 执行行为规范」）：
1. **自动推进**：阶段内产出→评审→修正循环自动执行
2. **确认后推进**：阶段完成后汇报，等待用户确认再进入下一阶段
3. **等待人工决策**：信息缺失、方向选择、置信度 < 0.75 时停止

**正常流程**：汇报状态 → 提出执行计划 → 自动执行 → 汇报结果摘要
