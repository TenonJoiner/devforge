# DevForge Marketplace Entry

## Plugin Information

**Name**: DevForge  
**ID**: `devforge`  
**Version**: 0.1.0  
**Author**: TenonJoiner  
**License**: MIT

## Description

复杂基础软件开发 TeamSkills 框架 — 三层工作流（产品级/特性级/代码级）+ OpenSpec 规范驱动 + 多 Agent 协作 + 自动化质量守护

## Features

- 三层工作流体系：产品级 → 特性级 → 代码级
- 10 个预定义专业化 Agent
- OpenSpec 规范驱动开发
- 多语言编码规范（C/C++/Rust/Go/Python/Java）
- 自动化质量守护（Hooks + Linters）
- TDD 工作流与五维度代码评审

## Installation

```bash
claude plugin marketplace add https://github.com/TenonJoiner/devforge
claude plugin install devforge
```

## Target Users

- 分布式系统/数据库/操作系统开发团队
- 需要严格工程规范的基础软件项目
- 长期迭代的复杂系统开发

## Commands

### 产品级
- `/df:product-design` - 架构探索与设计
- `/df:product-define` - 需求定义
- `/df:plan` - 迭代规划
- `/df:test-design` - 测试策略设计

### 特性级
- `/opsx:new` - 创建新特性
- `/opsx:continue` - 继续下一阶段
- `/opsx:apply` - 执行任务
- `/opsx:verify` - 验证实现
- `/opsx:archive` - 归档变更

### 代码级
- `/df:tdd` - TDD 开发工作流
- `/df:code-review` - 代码评审
- `/df:simplify` - 代码简化重构
- `/df:debug` - 系统化调试
- `/df:lint` - 编译检查与静态分析

## Repository

https://github.com/TenonJoiner/devforge
