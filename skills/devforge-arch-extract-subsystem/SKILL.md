---
name: devforge-arch-extract-subsystem
description: 逆向提取子系统架构总览文档——分析一个子系统的源码，识别内部组件拓扑、对外接口契约、设计约束，汇总子系统内各技术主题的定位和关系
allowed-tools: [Read, Write, Edit, Bash, Grep, Glob, Agent, AskUserQuestion]
---

# devforge-arch-extract-subsystem — 子系统逆向提取

## 概述

从已有源码逆向提取子系统级架构总览文档。子系统是按代码目录或模块边界组织的功能集合（如 storage、network、scheduler），关注组件拓扑、模块分工和子系统间接口契约。

**核心原则**：
1. **源码 = 行为真相**：代码是唯一权威的事实来源
2. **子系统文档是独立的一级架构文档**：描述子系统自身的整体设计，不是 topic 文档的摘要集合
3. **聚焦模块间关系**：子系统文档描述组件拓扑和跨模块协作，不深入单个模块的内部机制（那是 topic 文档的职责）
4. **单次生成单篇文档**：每次执行只产出当前目标子系统的一篇 overview.md

**与 topic/system skill 的关系**：
- subsystem 文档为 topic 文档提供架构全景和模块间关系
- subsystem 文档从属于 system 文档定义的分层框架
- subsystem 文档中的接口契约指子系统对外接口（子系统间接口），不列 topic 内部接口

## 工作目录约定

- **输入**：当前分支的源码（事实来源） + 可选的社区文档目录 `--doc=<dir>`（参考来源）
- **输出**：`docs/architecture/<subsystem>/overview.md`
- **模板**：`skills/devforge-arch-extract-subsystem/templates/arch-reverse-subsystem.md`

**输出路径**：`<subsystem>` 由阶段 3 边界确认时与用户商定。

## 启动检测

### 步骤 1：解析参数

- `--target=<子系统名>`（必选）：要分析的子系统，如 "storage""network""scheduler"
- `--doc=<dir>`（可选）：社区文档目录路径，不传则不启用

若无 `--target` 参数，报错提示用法。

### 步骤 2：检测输出文件

检查 `docs/architecture/<subsystem>/overview.md` 是否已存在（<subsystem> 待阶段 3 确认）：
- **不存在** → 进入初次生成模式
- **已存在** → 反问主人「修订 / 补全」

---

## 初次生成模式

### 第 1 阶段：边界识别

**职责**：扫描代码库，识别子系统目录/模块边界

派遣 1 个 researcher agent：

```
**任务模式**：子系统边界识别
**任务**：根据子系统名 "<target>" 在代码库中识别模块边界

**输入**：
- 子系统名：<target>
- 代码库根目录：当前工作目录

**分析内容**：
1. 定位子系统源码目录（匹配 target 关键词）
2. 识别子系统的入口接口（头文件、主要 API）
3. 识别子系统内部模块划分
4. 识别周边子系统（include/import 关系中的外部模块）
5. 检测已有的 topic 文档：扫描 `docs/architecture/<subsystem>/` 下的已有 `.md` 文件

**输出**（写入 `/tmp/arch-extract-subsys-locate-<ts>.md`）：
- 源码目录及文件清单
- 内部模块列表
- 外部依赖（周边子系统）
- 已有的 topic 文档列表（文件路径 + 标题，若有）
- 规模估算：文件数、总行数
```

**质量门禁**：
- 找到子系统核心源码目录
- 识别 ≥2 个内部模块

### 第 2 阶段：文档发现与分析

**前置条件**：`--doc=<dir>` 已提供。未提供则跳过。

派遣 2 个 researcher agent 并行：

**Agent A — 文档发现与筛选**：

```
**任务模式**：社区文档发现
**任务**：在 <doc_dir> 下搜索与子系统 "<target>" 相关的文档

**匹配逻辑**：扫描 .md/.rst/.txt，按 target 关键词匹配文件名和标题，筛选 1-5 篇

**输出**（写入 `/tmp/arch-extract-subsys-doclist-<ts>.md`）：
- 匹配到的文档列表
```

**Agent B — 子系统级设计声明提取**：

```
**任务模式**：设计声明提取
**任务**：从匹配到的文档中提取子系统级设计声明

**提取维度**：
1. 子系统定位与边界
2. 内部模块划分
3. 外部接口契约
4. 设计约束与约定

**输出**（写入 `/tmp/arch-extract-subsys-claims-<ts>.md`）：
- 声明清单
```

### 第 3 阶段：边界确认

**职责**：展示识别结果 + 匹配到的文档 + 文档声明，确认子系统范围和已有 topic 文档

主会话读取阶段 1 和阶段 2 的产出摘要，展示给用户：

1. **子系统边界识别**：源码目录、内部模块列表、周边子系统
2. **已有 topic 文档**：`docs/architecture/<subsystem>/` 下已有的文档
3. **文档匹配**（若启用）：匹配到的文档和设计声明

使用 AskUserQuestion 确认：
- 子系统范围是否合适
- 输出路径：`docs/architecture/<subsystem>/overview.md`

### 第 4 阶段：深度分析

**职责**：子系统内部架构、数据模型、并发模型、接口契约、设计约束

派遣 3 个 researcher agent 并行（按关注域切分）：

**Agent A — 架构与接口**：

```
**任务模式**：架构与接口分析
**任务**：分析子系统内部组件拓扑、接口契约、数据流

**输入**：
- 阶段 1 产出（文件清单、模块列表）
- 子系统名：<target>

**分析维度**：
1. 内部组件拓扑：模块间的层次和依赖关系
2. 子系统间接口：对外暴露的 API（非内部 private 函数）
3. 数据流：请求在子系统各模块间的流转路径

**输出**（写入 `/tmp/arch-extract-subsys-arch-<ts>.md`）：
- ASCII Art 组件拓扑图
- ≥2 个对外接口的详细描述（含前置/后置/异常语义）
- 1-2 条核心数据/控制流的端到端描述
```

**Agent B — 数据与并发**：

```
**任务模式**：数据与并发分析
**任务**：分析子系统的数据模型、状态机、锁策略、线程模型

**输入**：
- 阶段 1 产出
- 子系统名：<target>

**分析维度**：
1. 核心数据模型：子系统级的关键实体
2. 状态机：有生命周期的关键对象
3. 锁策略：全局锁、锁顺序规则
4. 线程/协程模型：角色划分、调度方式

**输出**（写入 `/tmp/arch-extract-subsys-data-<ts>.md`）：
- 核心数据模型描述
- 状态机图（Mermaid stateDiagram，如适用）
- 锁清单和全局顺序
- 线程模型描述
```

**Agent C — 约束与边界**：

```
**任务模式**：约束与边界分析
**任务**：分析子系统的设计约定、错误处理策略、与周边子系统的边界

**输入**：
- 阶段 1 产出（外部依赖、周边子系统）
- 子系统名：<target>

**分析维度**：
1. 内部设计约定：跨模块的通用约束（lock order、内存管理、错误码规范等）
2. 错误处理策略：子系统级的错误分类和处理原则
3. 周边子系统边界：每个相邻子系统的交互方式和责任归属

**输出**（写入 `/tmp/arch-extract-subsys-bound-<ts>.md`）：
- ≥2 条跨模块的通用设计约定
- 错误处理策略描述
- 所有相邻子系统的边界分析
```

**质量门禁**：3 个 agent 全部返回，每个产出含各自维度的分析内容。

### 第 5 阶段：文档-代码核对

**前置条件**：阶段 2 产出了设计声明清单。未启用 `--doc` 则跳过。

派遣 2 个 researcher agent 并行：

**Agent A — 接口契约核对**：

```
**任务模式**：接口契约核对
**任务**：将社区文档中的接口声明与阶段 4-A 的接口分析逐条对比

**输出**（写入 `/tmp/arch-extract-subsys-check-iface-<ts>.md`）
```

**Agent B — 模块划分核对**：

```
**任务模式**：模块划分核对
**任务**：将社区文档中的模块划分声明与阶段 4-A 的组件拓扑逐条对比

**输出**（写入 `/tmp/arch-extract-subsys-check-module-<ts>.md`）
```

### 第 6 阶段：主题发现

**职责**：识别子系统内的核心技术主题，与已有 topic 文档关联

派遣 1 个 researcher agent：

```
**任务模式**：技术主题发现
**任务**：在子系统内识别核心技术主题

**输入**：
- 阶段 4 全部分析（A/B/C）
- 已有 topic 文档列表：阶段 1 产出

**分析维度**：
1. 从源码中识别跨模块的技术主题（非目录结构概念）
2. 与已有 topic 文档建立关联
3. 识别出尚未有文档覆盖的重要主题

**输出**（写入 `/tmp/arch-extract-subsys-topics-<ts>.md`）：
- 主题表格：主题名 / 一句话职责 / 已有文档链接 / 状态（已有/待生成）
```

### 第 7 阶段：分析确认

**职责**：展示架构推断 + 核对结果 + 主题划分

主会话汇总阶段 4（三维度分析）、阶段 5（核对结果，若有）、阶段 6（主题列表），展示摘要。

使用 AskUserQuestion 确认关键判断。矛盾处以用户判断为准。

### 第 8 阶段：文档生成

**职责**：按 subsystem 模板生成完整文档

派遣 3 个 architect agent 并行（按章切分），然后 1 个 architect agent 合并：

**Agent A — 子系统定位 + 技术主题索引 + 内部架构**：

```
**任务模式**：subsystem 文档写作
**任务**：撰写"子系统定位"、"技术主题索引"和"内部架构"三个章节

**输入**：
- 阶段 4 全部分析（A/B/C）
- 阶段 6 主题列表
- 模板：skills/devforge-arch-extract-subsystem/templates/arch-reverse-subsystem.md（写作前 MUST 先读取）

**输出**（写入 `/tmp/arch-extract-subsys-sec1-<ts>.md`）
```

**Agent B — 接口契约 + 依赖关系**：

```
**任务模式**：subsystem 文档写作
**任务**：撰写"接口契约"和"依赖关系"两个章节

**输入**：
- 阶段 4 全部分析（A/B/C）
- 模板：skills/devforge-arch-extract-subsystem/templates/arch-reverse-subsystem.md（写作前 MUST 先读取）

**输出**（写入 `/tmp/arch-extract-subsys-sec2-<ts>.md`）
```

**Agent C — 设计约束与约定 + 已知问题**：

```
**任务模式**：subsystem 文档写作
**任务**：撰写"设计约束与约定"和"已知问题"两个章节

**输入**：
- 阶段 4 全部分析（A/B/C）
- 阶段 5 核对结果（若有）
- 模板：skills/devforge-arch-extract-subsystem/templates/arch-reverse-subsystem.md（写作前 MUST 先读取）

**输出**（写入 `/tmp/arch-extract-subsys-sec3-<ts>.md`）
```

**Agent D — 合并**：

```
**任务模式**：文档合并
**任务**：合并为完整文档，写入 `/tmp/arch-extract-subsys-draft-<ts>.md`
- 参照模板自检清单
- 去掉章节间重复
- 术语统一
```

**质量门禁**：文档 ≤300 行，所有必填章节均已覆盖。

### 第 9 阶段：评审

**职责**：独立评审 + 修正循环（最多 3 轮）

派遣 3 个 architect-reviewer agent 并行（按视角切分）：

**Agent A — 技术准确性**：

```
**任务模式**：独立技术评审
**评审视角**：技术陈述准确性、组件拓扑正确性、接口契约与代码一致性
**被评审对象**：`/tmp/arch-extract-subsys-draft-<ts>.md`
**review_output_path**：`/tmp/arch-extract-subsys-review-tech-<ts>.md`
```

**Agent B — 内容完整性**：

```
**任务模式**：独立评审
**评审视角**：模板必填章节全覆、最低深度达标、主题索引完整、相邻子系统无遗漏
**被评审对象**：`/tmp/arch-extract-subsys-draft-<ts>.md`
**review_output_path**：`/tmp/arch-extract-subsys-review-comp-<ts>.md`
```

**Agent C — 表达质量**：

```
**任务模式**：独立评审
**评审视角**：篇幅 ≤300 行、图表清晰正确、术语统一、无占位填充
**被评审对象**：`/tmp/arch-extract-subsys-draft-<ts>.md`
**review_output_path**：`/tmp/arch-extract-subsys-review-expr-<ts>.md`
```

**评审修正循环**：同 topic 的 3 轮循环规则。

### 第 10 阶段：写入

主会话将最终文档写入 `docs/architecture/<subsystem>/overview.md`。

**终端汇报**：文档路径、章节数、主题索引数、置信度。

---

## 修订模式

反问主人「想修订哪一块」：
1. 修订内部架构与接口契约
2. 修订依赖关系与设计约束
3. 修订已知问题

只跑对应范围，merge 回原文档。

## 补全模式

用模板自检清单扫描，识别缺失项，对应补全。

---

## 禁忌项

- 禁止跳过边界确认（阶段 3 必须与用户交互）
- 禁止深入单个 topic 的内部机制细节（那是 topic 文档的职责）
- 禁止将 subsystem 文档变成 topic 文档的摘要集合
- 禁止跳过评审循环直接输出
- 禁止将社区文档描述当作本产品的设计声明
- 禁止写占位章节
- 禁止超过 300 行
- 禁止不读取模板就直接写作
