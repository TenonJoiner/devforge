# DevForge

> 复杂基础软件开发 TeamSkills 框架 — Claude Code Plugin

DevForge 是一个面向复杂基础软件（分布式存储、数据库、操作系统内核等）的三层 TeamSkills 开发框架，提供产品级到代码级的完整工作流支持。

## 特性

- **三层工作流**：产品级（架构/需求/计划）→ 特性级（规范驱动）→ 代码级（TDD/评审/重构）
- **多 Agent 协作**：10 个预定义专业化 Agent（architect、product、developer、tester、reviewer 等）
- **自动化质量守护**：通过 hooks 和 agents 实现编码规范、测试覆盖、代码质量的自动化保障
- **多语言支持**：C、C++、Rust、Go、Python、Java 编码规范与工具链

## 安装

```bash
# 添加 marketplace（如果还未添加）
claude plugin marketplace add https://github.com/TenonJoiner/devforge

# 安装 plugin
claude plugin install devforge
```

## 快速开始

### 产品级工作流

```bash
# 架构探索与设计
/df:product-design

# 需求定义（Feature-Scenario 结构）
/df:product-define

# 迭代规划（里程碑 + 执行计划）
/df:plan

# 测试策略设计
/df:test-design
```

### 特性级工作流

```bash
# 标杆研究
/df:research <proposal-name>

# 需求定义（Delta 格式）
/df:define

# 架构设计（强制图示）
/df:design

# 文档评审
/df:spec-review
```

### 代码级工作流

```bash
# TDD 开发工作流
/df:tdd

# 代码评审（五维度：Correctness/Readability/Architecture/Security/Performance）
/df:code-review

# 代码简化重构（深度清理）
/df:simplify

# 系统化调试
/df:debug

# 编译检查与静态分析
/df:lint

# Git Worktree 管理
/df:switch-worktree
/df:finish-worktree
```

## 核心概念

### 三层工作流

```
产品级（数月周期）
  ├── 架构设计（ADR + 子系统设计）
  ├── 需求定义（Actor-Feature-Scenario）
  ├── 迭代规划（里程碑 + Backlog）
  └── 测试策略（分层 + 覆盖率目标）
        ↓
特性级（数周周期）
  ├── research（标杆研究）
  ├── specs（规格定义）
  ├── design（架构设计）
  └── review（文档评审）
        ↓
代码级（数天周期）
  ├── TDD（RED-GREEN-REFACTOR）
  ├── 代码评审（五维度评审）
  └── 质量守护（hooks + linters）
```

### 10 个预定义 Agent

| Agent | 职责 | 主要 Skills |
|-------|------|------------|
| **architect** | 架构设计与技术选型 | product-design, feature-design |
| **architect-reviewer** | 架构评审（技术视角） | product-design, feature-design |
| **product** | 需求定义与 Feature 拆解 | product-define, feature-define |
| **product-reviewer** | 需求评审（业务视角） | product-define, feature-define |
| **project** | 迭代规划与资源编排 | plan |
| **project-reviewer** | 计划评审（进度/资源视角） | plan |
| **researcher** | 标杆研究与技术调研 | feature-research |
| **developer** | 代码实现（TDD 铁律） | tdd |
| **tester** | 测试执行与覆盖率验证 | tdd, test-design |
| **code-reviewer** | 代码评审（五维度） | code-review |

### 编码规范分层

- **通用编码规范** — 跨语言通用原则：见 `rules/coding-style.md`
- **Git 工作流** — Conventional Commits + worktree 规范：见 `rules/git-workflow.md`
- **语言特定规范** — C / Go / Python / Java 等：见 `rules/coding-style-*.md`
- **测试分层** — 单元 / 集成 / 性能 + TDD 铁律（待补充）

## Plugin 结构

```
devforge/
├── .claude-plugin/
│   └── plugin.json              # Plugin 元数据
├── agents/                      # 预定义 Agent（10 个角色）
│   ├── architect.md
│   ├── architect-reviewer.md
│   ├── product.md
│   ├── developer.md
│   ├── tester.md
│   ├── code-reviewer.md
│   └── ...
├── skills/                      # DevForge Skills
│   ├── devforge-product-design/
│   ├── devforge-product-define/
│   ├── devforge-tdd-workflow/
│   ├── devforge-code-review/
│   └── ...
├── rules/                       # 编码规范与工作流规则
│   ├── coding-style.md          # 通用编码规范
│   ├── coding-style-c.md        # C 语言规范
│   ├── coding-style-rust.md     # Rust 规范
│   ├── git-workflow.md          # Git 规范
│   ├── testing.md               # 测试规范
│   └── workflow.md              # 工作流定义
├── hooks/                       # 自动化 Hooks
│   ├── hooks.json               # Hook 配置
│   ├── post-edit-format.sh      # H2 代码格式化
│   ├── post-edit-quality-gate.sh # H3 质量门禁
│   └── pre-commit-lint.sh       # H1 提交前检查
├── commands/                    # 用户可见命令
│   └── df/
└── README.md                    # 本文件
```

## 配置

### 项目配置（`.claude/` 目录）

```yaml
# .claude/domain-config.yaml
domain: distributed-storage
languages:
  primary: c
  secondary: [python]
test_framework: cmocka
```

### Hook 配置

Hooks 在 `hooks/hooks.json` 中定义，支持：
- **PostEdit** - 代码格式化（clang-format/rustfmt/black 等）
- **PreCommit** - 提交前编译检查与静态分析
- **PostTest** - 测试后覆盖率验证

## 适用场景

DevForge 特别适合以下项目：
- **复杂基础软件**：分布式存储、数据库、操作系统、编译器、虚拟化平台
- **长期迭代项目**：需要架构设计、需求管理、迭代规划的系统级软件
- **多人协作**：需要标准化 workflow、代码规范、评审流程的团队项目
- **质量敏感**：对测试覆盖率、代码质量、安全性有严格要求的项目

## 文档

- [CLAUDE.md](CLAUDE.md) - 框架设计核心规范
- [rules/workflow.md](rules/workflow.md) - 工作流详解
- [rules/testing.md](rules/testing.md) - 测试分层与 TDD 规范
- [rules/git-workflow.md](rules/git-workflow.md) - Git 工作流规范

## License

MIT

## 贡献

欢迎提交 Issue 和 Pull Request。贡献前请阅读 [CLAUDE.md](CLAUDE.md) 了解框架设计原则。
