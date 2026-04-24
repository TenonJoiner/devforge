# 四层工作流规范

## 概述

本文档定义 teamskills 的四层工作流体系：产品级 → 特性级 → 代码级 → 测试验证级。

**核心原则**：
- 上层约束下层，下层变更反馈上层
- 产品级灵活创作，特性级规范驱动
- 长期迭代，螺旋式完善

## 四层关系

```
产品级（启发式 Skills + /df:* 命令）
  /df:design ←→ /df:define ←→ /df:plan
      │               │              │
      ▼               ▼              ▼
  architecture/   requirements/   iteration-plan/
      adr.md                        milestone-plan.md
     design.md                      iteration-m*-i*.md
   <subsystem>/
      │ 人工决策：从 proposal 清单选择当前要实现的特性
      │
      └──▶ 特性级（OpenSpec + /opsx:* 命令）
              proposal → specs → design → tasks
              → /opsx:apply → /opsx:verify → /opsx:archive
                      │
                      │ 开发实现
                      ▼
              代码级（teamskills 代码级 skills）
                worktree 隔离 → TDD 开发 → 代码评审
                        │
                        │ 单元测试通过
                        ▼
              测试验证级（独立测试目录）
                集成测试 → 系统测试 → 性能测试
                        │
                        │ 全量测试通过
                        ▼
                   merge to main
```

## 各层职责

### 产品级

**目标**：架构设计、需求定义、迭代规划

**核心原则**：
- **与 OpenSpec 彻底脱离**，按思考模式辅助设计
- 重要的是**输出质量**而非**流程控制**
- **可反复迭代**，无固定顺序，螺旋式完善

**交付物**：
- `docs/architecture/` — 子系统架构
  - `docs/architecture/adr.md` — 架构决策记录
  - `docs/architecture/design.md` — 系统架构总纲
  - `docs/architecture/<subsystem>/design.md` — 子系统架构主文档（每个子系统文档在对应 ADR 达到高置信度后产出，且需独立经过 architect 发散 → architect-reviewer 质疑 → architect 修正定稿的多 agent 协作）
- `docs/requirements/` — 需求规格（内容结构严格遵循 `.claude/templates/*.md`，skill 文件只约束流程与质量）
- `docs/iteration-plan/` — 迭代计划
  - `milestone-plan.md` — 里程碑计划 + Backlog 清单（第 1 阶段）
  - `iteration-m*-i*.md` — 各迭代执行计划（第 2 阶段）
- `docs/test-strategy.md` — 测试策略

**触发命令**：
- `/df:design` — 架构探索（检测现有文档，支持迭代完善）
- `/df:define` — 需求定义（Feature-Scenario 结构）
- `/df:plan` — 迭代计划（两阶段：里程碑+Backlog → 迭代执行计划，每阶段三重评审）
- `/df:test-design` — 测试策略设计（测试分层 → 覆盖率目标 → 各级方案）

**使用模式**：
1. **从零开始**：全新系统或重大架构调整
2. **迭代完善**：已有文档需要更新，可多次执行
3. **快速记录**：讨论中产生的灵感或临时决策

### 特性级

**目标**：单个特性的规范驱动开发

**核心原则**：
- 基于 OpenSpec spec-driven-enhanced schema
- 流程控制严格，按依赖图推进
- 产出质量需符合产品级文档约束

**交付物**：
- `openspec/changes/<proposal>/proposal.md`
- `openspec/changes/<proposal>/specs/*.md`
- `openspec/changes/<proposal>/design.md`
- `openspec/changes/<proposal>/review.md`
- `openspec/changes/<proposal>/tasks.md`

**触发命令**：
- `/opsx:new` — 创建 proposal（从 iteration-plan.md 选择）
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
- `/df:tdd` — TDD 开发
- `/df:review` — 代码评审
- `/df:refactor` — 代码重构
- `/df:lint` — 编译检查
- `/df:switch-worktree` — 切换 worktree
- `/df:debug` — 系统化调试

### 测试验证级

**目标**：集成测试、系统测试、性能测试

**核心原则**：
- 不设 `/df:*` 命令
- 测试用例开发在独立测试目录
- 测试执行通过脚本触发

## 产品级 → 特性级衔接

### 启动特性开发

1. 从产品级 `docs/iteration-plan/milestone-plan.md` 的 Backlog 中选择 proposal
2. 使用 `/opsx:new <proposal-name>` 启动特性级 workflow
3. proposal.md 自动关联产品级需求文档（`docs/requirements/*.md`）
4. design.md 自动关联产品级架构文档（`docs/architecture/design.md` 系统总纲，及 `docs/architecture/<subsystem>/design.md` 相关子系统）

### 变更反馈

特性级开发中发现的产品级文档问题：
- 在 spec/design 中使用 `[[发现]]` 标注
- `/opsx:archive` 时汇总未处理发现
- 累计超过 3 个时，提示执行 `/df:design` 或 `/df:define` 更新产品级文档

## 文档对齐

### 追溯关系

| 特性级文档 | 应追溯的产品级文档 |
|-----------|------------------|
| proposal.md | iteration-plan/milestone-plan.md#对应 proposal |
| specs/*.md | requirements/*.md#相关 Feature |
| design.md | architecture/design.md（系统总纲）、architecture/<subsystem>/design.md（相关子系统） |

## 并行开发规约

1. **独立任务并行**：修改不同文件的任务可并行
2. **同文件串行**：修改同一文件的任务串行
3. **worktree 隔离**：每个并行开发使用独立 worktree
4. **冲突检测**：特性级自动检测文件冲突

## 与 OpenSpec 的分工

| 能力 | OpenSpec 提供 | teamskills 自建 |
|------|--------------|----------------|
| Artifact 依赖图 | ✅ | — |
| Delta 规范格式 | ✅ | — |
| Schema 自定义 | ✅ | — |
| 模板系统 | ✅ | — |
| 命令系统 | ✅ | — |
| 产品级 Skills | — | ✅ `/df:*` |
| 代码级 Skills | — | ✅ `/df:*` |
| Agents | — | ✅ |
| Hooks | — | ✅ |
| Rules | — | ✅ |

## 使用建议

### 产品级（数月周期）

```
第 1-2 周：/df:design → 系统级架构框架
第 2-4 周：/df:define → 核心 Feature 需求
第 3-5 周：/df:test-design → 测试策略设计
第 4-6 周：/df:plan → 初始迭代计划
...
第 N 周：/df:design → 基于新认知调整架构
```

### 特性级（数周周期）

```
/opsx:new storage-write-buffer
/opsx:continue → specs
/opsx:continue → design
/opsx:continue → tasks
/opsx:apply → 代码实现
/opsx:verify
/opsx:archive
```

### 混合模式

产品级和特性级可交错进行：
1. 产品级规划部分子系统
2. 特性级开始实现已明确的 proposal
3. 产品级继续完善其他子系统架构
4. 特性级实现中发现的问题反馈到产品级
