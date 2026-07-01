---
name: devforge-arch-extract-system
description: 逆向合成系统级架构总览——从已有 subsystem 文档汇总合成，描述系统架构分层、子系统全景、全局设计约束。不分析源码
allowed-tools: [Read, Write, Edit, Bash, Grep, Glob, Agent]
---

# devforge-arch-extract-system — 系统级架构逆向合成

## 概述

从已有的 subsystem 文档汇总合成系统级架构总览文档。本 skill **不分析源码**——它通过读取 `docs/architecture/<subsystem>/overview.md` 来跨子系统汇总，产出产品级架构文档。

**核心原则**：
1. **从 subsystem 文档合成**：不直接读源码，通过已有 subsystem 文档提取系统级信息
2. **独立的产品级架构文档**：描述系统整体的架构分层、设计思想、子系统间的协作关系
3. **分层框架 vs 内部设计**：system 定义分层框架和子系统边界，不展开子系统内部设计
4. **单次生成单篇文档**：产出 `docs/architecture/system-overview.md`

**与 subsystem/topic skill 的关系**：
- system 文档是读者进入代码库的第一份文档，承载产品级的架构认知
- system 定义分层框架和子系统边界，subsystem 展开各层内部设计
- system 不重复 subsystem 的接口契约或 topic 的内部机制

## 工作目录约定

- **输入**：`docs/architecture/<subsystem>/overview.md`（已有的 subsystem 文档）
- **输出**：`docs/architecture/system-overview.md`
- **模板**：`skills/devforge-arch-extract-system/templates/arch-reverse-system.md`

## 启动检测

### 步骤 1：检查已有 subsystem 文档

扫描 `docs/architecture/` 目录，列出所有 `<subsystem>/overview.md` 文件：
- 找到 ≥2 个 subsystem 文档 → 进入初次生成模式
- 找到 0-1 个 → 提示用户先通过 `/df:arch-extract-subsystem` 生成至少 2 个 subsystem 文档后再运行本 skill

### 步骤 2：检测输出文件

检查 `docs/architecture/system-overview.md` 是否已存在：
- **不存在** → 进入初次生成模式
- **已存在** → 反问主人「修订 / 补全」

---

## 初次生成模式

### 第 1 阶段：收集

**职责**：读取所有 subsystem overview 文档

派遣 1 个 researcher agent：

```
**任务模式**：subsystem 文档收集
**任务**：读取并提取所有 subsystem overview 文档的关键信息

**输入**：
- 所有 `docs/architecture/<subsystem>/overview.md` 文件清单

**提取维度**（从每个 subsystem 文档中提取）：
1. 子系统定位和职责（"子系统定位"章节）
2. 对外接口契约（"接口契约"章节）
3. 依赖关系（"依赖关系"章节）
4. 设计约束与约定（"设计约束与约定"章节）
5. 已知问题（"已知问题"章节，关注子系统级技术债务）

**输出**（写入 `/tmp/arch-extract-sys-collect-<ts>.md`）：
- 每个子系统的关键信息摘要（≤20 行/子系统）
- 跨子系统的依赖关系矩阵
- 跨子系统的一致性约束列表（从各 subsystem 的约束章节提取，识别相同的约束）
```

**质量门禁**：所有 subsystem 文档均已读取并提取关键信息。

### 第 2 阶段：合成

**职责**：跨子系统汇总——数据流、接口索引、全局约束

派遣 1 个 researcher agent：

```
**任务模式**：跨子系统合成
**任务**：跨子系统汇总，识别系统级模式

**输入**：
- 阶段 1 的提取结果
- 所有 subsystem 文档全文

**分析维度**：
1. **架构分层推导**：从各子系统的依赖关系反推分层结构（上层依赖下层）
2. **设计思想识别**：从各子系统的设计约定中识别贯穿各层的设计思想
3. **端到端数据流**：从依赖关系矩阵推导 ≥2 条跨子系统的主数据流路径
4. **全局约束汇总**：各子系统共同遵守的约束
5. **系统级风险识别**：跨子系统的全局性风险

**输出**（写入 `/tmp/arch-extract-sys-synthesize-<ts>.md`）：
- 分层结构推导
- ≥2 条贯穿各层的设计思想
- ≥2 条端到端数据流路径
- ≥3 条全局约束
- 系统级已知风险
```

### 第 3 阶段：文档生成

**职责**：按 system 模板合成文档

派遣 2 个 architect agent 并行（按章切分），然后 1 个 architect agent 合并：

**Agent A — 系统简介 + 分层与设计思想 + 子系统全景**：

```
**任务模式**：system 文档写作
**任务**：撰写"系统简介"、"架构分层与设计思想"和"子系统全景"三个章节

**输入**：
- 阶段 1 收集结果 + 阶段 2 合成结果
- 模板：skills/devforge-arch-extract-system/templates/arch-reverse-system.md（写作前 MUST 先读取）

**输出**（写入 `/tmp/arch-extract-sys-secA-<ts>.md`）
```

**Agent B — 数据流总览 + 全局设计约束 + 已知风险**：

```
**任务模式**：system 文档写作
**任务**：撰写"数据流总览"、"全局设计约束"和"已知风险"三个章节

**输入**：
- 阶段 1 收集结果 + 阶段 2 合成结果
- 模板：skills/devforge-arch-extract-system/templates/arch-reverse-system.md（写作前 MUST 先读取）

**输出**（写入 `/tmp/arch-extract-sys-secB-<ts>.md`）
```

**Agent C — 合并**：

```
**任务模式**：文档合并
**任务**：合并为完整文档，写入 `/tmp/arch-extract-sys-draft-<ts>.md`
- 参照模板自检清单
- 去掉章节间重复
- 术语统一
```

**质量门禁**：文档 ≤300 行，所有必填章节均已覆盖。

### 第 4 阶段：评审

**职责**：独立评审 + 修正循环（最多 3 轮）

派遣 2 个 architect-reviewer agent 并行：

**Agent A — 技术准确性 + 一致性**：

```
**任务模式**：独立评审
**评审视角**：
1. 分层推导是否符合各 subsystem 文档的实际依赖关系
2. 子系统全景表中的信息是否与各 subsystem 文档一致
3. 端到端数据流路径是否与各 subsystem 文档描述的接口契约一致
4. 全局约束是否真正跨子系统（而非某子系统局部约束）

**被评审对象**：`/tmp/arch-extract-sys-draft-<ts>.md`
**review_output_path**：`/tmp/arch-extract-sys-review-tech-<ts>.md`
```

**Agent B — 完整性 + 表达质量**：

```
**任务模式**：独立评审
**评审视角**：
1. 模板必填章节全覆盖
2. 各章节最低深度达标
3. 文档 ≤300 行
4. 未展开子系统内部设计（那是 subsystem 文档的职责）
5. 图表清晰、术语统一、无占位填充

**被评审对象**：`/tmp/arch-extract-sys-draft-<ts>.md`
**review_output_path**：`/tmp/arch-extract-sys-review-comp-<ts>.md`
```

**评审修正循环**：同 topic 的 3 轮循环规则。

### 第 5 阶段：写入

主会话将最终文档写入 `docs/architecture/system-overview.md`。

**终端汇报**：文档路径、子系统数、章节数、置信度。

---

## 修订模式

反问主人「想修订哪一块」：
1. 修订架构分层与设计思想
2. 修订数据流与全局约束
3. 修订已知风险

只跑对应范围，merge 回原文档。

## 补全模式

用模板自检清单扫描，识别缺失项，对应补全。

---

## 禁忌项

- 禁止直接分析源码（本 skill 只能从 subsystem 文档合成）
- 禁止展开任何子系统的内部设计（那是 subsystem 文档的职责）
- 禁止将 system 文档变成 subsystem 文档内容的汇总复述
- 禁止在没有 ≥2 个 subsystem 文档时运行
- 禁止跳过评审循环直接输出
- 禁止写占位章节
- 禁止超过 300 行
- 禁止不读取模板就直接写作
