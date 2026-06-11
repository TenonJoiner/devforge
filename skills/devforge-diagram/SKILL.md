---
name: devforge-diagram
description: 从现有架构文档自动生成可编辑的 drawio 架构图。支持特性级 design.md、产品级系统架构总纲、子系统设计。产出 .drawio 文件，可选导出 PNG/SVG/PDF 或生成浏览器 URL。
allowed-tools: [Read, Write, Edit, Bash, Grep, Glob, Agent]
---

# devforge-diagram — 架构图自动生成

## 概述

将文本架构文档转化为可编辑的 drawio 图示。支持从 design.md、系统架构总纲、子系统设计等文档自动提取结构，生成专业级架构图。

**核心原则**：
1. **文档驱动**：图从现有架构文档提取，不凭空构造
2. **可编辑优先**：产出原生 `.drawio` 文件，非一次性图片
3. **与设计流程集成**：可被 design skill 在强制图示环节调用
4. **可选导出**：默认保留 `.drawio`，按需导出 PNG/SVG/PDF

---

## 工作目录约定

- **输入**：用户指定的架构文档路径，或当前目录的 `design.md`
- **输出**：`.drawio` 文件（与输入文档同级目录）
- **导出**：按用户请求处理 `png` / `svg` / `pdf` / `url`

---

## 启动检测

1. **用户显式指定文件** → 进入该文件的图示生成
2. **当前目录有 design.md** → 询问图示类型（结构图 / 时序图 / 状态机图 / 数据流图 / 全部）
3. **当前目录无 design.md** → 报错并提示主人指定文档路径或 `cd` 到正确目录

---

## 执行流程

### [1] 架构提取

派遣 1 个 architect agent，任务：
- 读取目标架构文档
- 提取图示所需的结构化信息：
  - **组件清单**：名称、类型、职责
  - **关系清单**：组件间依赖、调用方向、数据流向
  - **交互序列**（时序图）：参与方、消息顺序、生命周期
  - **状态集合**（状态机图）：状态列表、触发事件、转换条件
- 产出：结构化摘要（JSON-like 格式，写入临时摘要文件或直接返回）

### [2] 图示生成

派遣 1 个 architect agent，任务：
- 读取 [1] 的架构摘要
- 读取 `templates/drawio-xml-guide.md`
- 生成对应类型的 drawio XML（mxGraphModel 格式）
- 产出：`.drawio` 文件

**图示类型与触发条件**（与 feature-design 强制图示对齐）：

| 类型 | 触发条件 | 文件名约定 |
|------|---------|-----------|
| 结构图 | ≥3 个组件，模块/子系统关系 | `<doc-name>-structure.drawio` |
| 时序图 | 跨进程/跨节点/跨组件交互 | `<doc-name>-sequence.drawio` |
| 状态机图 | 有生命周期的对象（租约、连接、会话） | `<doc-name>-statemachine.drawio` |
| 数据流图 | 数据缓存、读写路径分离、ETL 流程 | `<doc-name>-dataflow.drawio` |

**命名规则**：
- 基于源文档名 + 图示类型后缀
- 示例：`design.md` → `design-structure.drawio`, `design-sequence.drawio`
- 多页 diagram：单文件多 page，每页一种图示类型

### [3] 导出处理（可选）

按用户请求处理输出格式：

| 格式 | 动作 | 依赖 |
|------|------|------|
| (默认) | 保留 `.drawio` 文件 | 无 |
| `png` | `drawio -x -f png -e -b 10 -o <out> <in>`，成功后删除源 `.drawio` | draw.io Desktop |
| `svg` | `drawio -x -f svg -e -b 10 -o <out> <in>`，成功后删除源 `.drawio` | draw.io Desktop |
| `pdf` | `drawio -x -f pdf -e -b 10 -o <out> <in>`，成功后删除源 `.drawio` | draw.io Desktop |
| `url` | zlib 压缩 XML → base64 → `app.diagrams.net` URL，保留 `.drawio` | Node.js（内置） |

**CLI 定位**（按平台）：
- macOS：`/Applications/draw.io.app/Contents/MacOS/draw.io`
- Linux：`drawio`（PATH）
- WSL2：`/mnt/c/Program Files/draw.io/draw.io.exe`
- Windows：`"C:\Program Files\draw.io\draw.io.exe"`

**CLI 未找到处理**：保留 `.drawio` 文件，告知主人可安装 draw.io Desktop 后手动导出，或使用 `url` 模式。

### [4] 结果汇报

汇报：
- 生成的图示文件路径
- 图示类型和页数
- 导出状态（格式 / 是否成功）

---

## 图示质量检查

主会话在 [2] 完成后执行轻量检查（不派遣 reviewer）：
- 文件存在性：`ls` 验证
- XML 基本结构：包含 `<mxGraphModel>`、`<root>`、`id="0"`、`id="1"`
- 组件数 ≥ 提取摘要中的组件数（不少于）

未通过 → 回到 [2] 重新生成（最多 2 次）。

---

## Agent 派遣 Prompt 模板

### 架构提取 agent

```
当前是 diagram 生成阶段，从架构文档提取图示结构。

**任务模式**：架构提取
**输入路径**：<文档路径>
**图示类型**：<structure|sequence|statemachine|dataflow|all>

**提取要求**：
- 结构图：列出所有组件（名称、类型、职责）和组件间关系（依赖方向、调用类型）
- 时序图：列出参与方、消息顺序（含方向）、关键生命周期节点
- 状态机图：列出状态集合、触发事件、转换条件、初始/终止状态
- 数据流图：列出数据源、处理节点、存储节点、数据流向

**输出格式**：结构化文本（列表/表格），便于下游 agent 直接用于生成 XML。
返回结构化摘要，不超过 20 行。
```

### 图示生成 agent

```
当前是 diagram 生成阶段，生成 drawio XML。

**任务模式**：drawio XML 生成
**输入**：<架构提取摘要>
**template_path**：`templates/drawio-xml-guide.md`
**output_path**：`<目标 .drawio 文件路径>`
**图示类型**：<structure|sequence|statemachine|dataflow>

**要求**：
- 严格遵循 drawio-xml-guide.md 的格式规范
- 组件布局合理（结构图用分层布局，时序图从左到右）
- 边和节点样式统一
- 标签清晰可读
- 禁止 XML 注释

产出完整的 `.drawio` 文件（mxGraphModel XML）。
```

---

## 与其他 skill 的协作

- **被调用方**：`devforge-feature-design` 在强制图示环节可调用本 skill
- **被调用方**：`devforge-product-design` 在架构总纲/子系统设计阶段可调用本 skill
- **上游输入**：任何包含架构描述的 markdown 文档
- **下游**：`.drawio` 文件可被 draw.io Desktop 或浏览器编辑
