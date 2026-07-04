---
name: devforge-harness-improve
description: Harness 诊断，从开发者 trace 数据中识别 harness 缺陷，输出结构化 issues 列表
allowed-tools: [Read, Write, Bash, Grep, Agent]
parameters:
  - name: trace_dir
    description: 单个项目的原始 trace 包目录路径（存储层已按项目分目录）
    required: true
  - name: project_dir
    description: 开发者项目源码目录路径，用于读取项目级上下文文件诊断缺陷
    required: true
---

# devforge-harness-improve — Harness 改进闭环

## 概述

本 skill 实现 DevForge harness 框架的诊断闭环：读取本地 trace 目录 → 蒸馏脱敏 → 聚合 → 分析 → 输出 issues。

**核心场景**：当开发者使用 DevForge skill（如 /df:pr-review、/df:tdd）遇到质量问题时，harness 工程师通过本 skill 获取系统化的 trace 数据，诊断是模型问题还是 harness 问题，输出结构化 issues 供人工决策。

## 何时使用

- 收到开发者反馈某个 skill 质量下降，需要诊断是模型还是 harness 问题
- 定期（每周）扫描 trace 数据，发现 harness 退化信号
- 新增 skill 后观察其在实际使用中的表现

## 架构

三端分离：

```
开发人员 Claude CLI → 采集 JSONL + 打包上传（trace-collector / trace-upload hooks）
        ↓
  MCP Server → 按项目存储原始 trace（trace.upload 接口）
        ↓
Harness 工程师 CLI → 下载到本地 trace_dir → 蒸馏 → 聚合 → 分析 → 输出 issues（本 skill）
```

本 skill 运行在 **Harness 工程师本地**，从指定本地目录读取已下载的 trace 包。

## 工作流程

### 准备工作：创建隔离工作目录

```bash
WORK_DIR=$(mktemp -d /tmp/harness-improve-XXXXXX)
echo "工作目录: $WORK_DIR"
```

后续所有中间文件均写入 `$WORK_DIR/`，不同项目、多次执行互不干扰。

### 第 1 阶段：读取本地 Trace

**步骤 1：列出 `trace_dir` 下所有 trace 包**

```bash
ls <trace_dir>/*.tar.gz
```

数据量检查：
- 若 trace 包对应会话数 < 3 或开发者数 < 2 → 提示「数据不足，继续积累」，停止执行
- 数据充足 → 进入第 2 阶段

**数据不足提示格式**：
```
当前数据不足以分析（X 个会话，Y 个开发者）
最低要求：≥3 个会话，≥2 个开发者
建议继续积累数据后重试。
```

### 第 2 阶段：本地蒸馏

**步骤 2：对每个原始 trace 包执行蒸馏**

```bash
mkdir -p "$WORK_DIR/reports"
for trace_pkg in <trace_dir>/*.tar.gz; do
    pkg_name=$(basename "$trace_pkg" .tar.gz)
    pkg_dir="$WORK_DIR/distill/$pkg_name"
    mkdir -p "$pkg_dir"
    tar xzf "$trace_pkg" -C "$pkg_dir"
    bash skills/devforge-harness-improve/trace-distill.sh \
        "$pkg_dir/events.jsonl" \
        "$pkg_dir/transcript.jsonl" \
        > "$WORK_DIR/reports/${pkg_name}.md"
done
```

蒸馏脚本 (`skills/devforge-harness-improve/trace-distill.sh`) 产出 AHE 式五层诊断报告（~3K token/session）：
- **L1 会话概览**：成功率、摩擦评分、Hook 阻拦数
- **L2 Skill 下钻**：每 skill 的工具调用、错误、重试、Agent 派遣
- **L3 执行对齐**：工具输出是否被后续消费（Grep→无跟进、Agent→结果忽略、Read→未编辑）
- **L4 恢复分类**：错误后行为归类为 RETRY / ESCALATE / WORKAROUND / IGNORE
- **L5 组件归因**：异常信号映射到具体 harness 文件（SKILL.md、agents/*.md、hooks/）
- 执行脱敏（替换密钥模式为 ***REDACTED***）

### 第 3 阶段：跨会话聚合

**步骤 3：聚合多份 per-session 报告**

```bash
bash skills/devforge-harness-improve/aggregate.sh "$WORK_DIR/reports" > "$WORK_DIR/aggregate.md" || {
    echo "错误: aggregate.sh 执行失败（退出码: $?）"
    echo "可能原因: Python 语法错误、蒸馏报告格式不匹配、或脚本本身存在 bug"
    echo "检查 aggregate.md 内容，若为空或不完整，需修复 aggregate.sh 后重试"
    exit 1
}
```

聚合脚本 (`skills/devforge-harness-improve/aggregate.sh`) 产出组件级诊断概览（~5K token），包含：
- 组件故障热点（跨会话共现 ≥2 的 harness 文件异常）
- Skill 级聚合（平均耗时、错误率、重试次数，跨会话对比）
- 恢复模式分布（RETRY/ESCALATE/WORKAROUND/IGNORE 占比及告警）
- 执行对齐问题（跨会话频率统计）
- 纠正热点（≥3 会话共现的 skill）
- 高摩擦会话列表
- 异常跨会话频率聚类

### 第 4 阶段：分析

**步骤 4：派遣 harness-engineer agent 分析聚合报告**

主会话派遣 harness-engineer agent（分析模式），注入以下 prompt：

```
读取 $WORK_DIR/aggregate.md，分析跨开发者 trace 中暴露的问题。aggregate.md 包含五类诊断信号：

- 组件故障热点：跨会话共现的 harness 文件异常（组件→信号数→涉及会话）
- Skill 级聚合：每 skill 的调用量、错误率、重试、平均耗时
- 恢复模式分布：RETRY/ESCALATE/WORKAROUND/IGNORE 占比及告警标记
- 执行对齐问题：工具输出未被后续消费的模式频率
- 纠正热点：≥3 会话中触发用户纠正的 skill

资源分三层，不同层级存放不同类型的文件，诊断时按归属层检查：

**第 1 层 — Plugin 层**（DevForge 安装目录，随 plugin 分发）：
`agents/`、`skills/`、`commands/`、`hooks/`、`templates/`、`rules/`
这些是 DevForge 框架基础设施，在所有项目中共享，由 harness 工程师维护。

**第 2 层 — 用户层**（`~/.claude/`）：
`CLAUDE.md`（用户全局偏好）、`settings.json`（用户级 hooks/权限配置）
影响所有项目的全局行为。

**第 3 层 — 项目层**（`<project_dir>` 及 `<project_dir>/.claude/`）：
`CLAUDE.md`（项目指令）、`.claude/settings.local.json`（项目级配置）、`.claude/rules/`（项目规则）、`docs/`（架构/需求文档）
仅影响当前项目，内容因项目而异。

**关键规则**：
- Plugin 层资源（agents/、skills/、commands/、hooks/、templates/）**不在项目层**，禁止因项目目录中找不到这些文件而报 issue
- 诊断时：若 aggregate 归因到 `agents/*.md`，应读取 Plugin 层的 `agents/` 目录；若归因到 `SKILL.md`，应读取 Plugin 层的 `skills/` 目录；hooks/ 问题检查 Plugin 层的 `hooks/`
- 项目层仅检查项目特有的文件：`CLAUDE.md`、`.claude/settings.local.json`、`.claude/rules/`、`docs/`
- 用户层仅当异常跨多个项目共现时才检查（单项目 issue 优先排查 Plugin 层和项目层）

读取对应层的实际源文件，对照 aggregate 中的组件归因和恢复模式信号，诊断具体缺陷。禁止脱离真实文件内容推断——每个 issue 必须引用对应源文件的具体内容作为证据。

分析要求：
- 优先关注组件故障热点中 sessions ≥ 2 的条目，逐一读取对应层源文件诊断根因
- IGNORE 占比 >40% 或 RETRY 占比 >30% 时，必须诊断 skill 中缺失的错误处理/退出条件
- 按五大类别分类，每个 issue 标注归属层（Plugin / 用户层 / 项目级）
- 3+ 开发者共现 → 共性模式（高优先级），1 个开发者 → 个人模式（标记 NEEDS_HUMAN_REVIEW）
- 每个 issue 必须包含 Change Manifest：

```
### Issue: <标题>
- 严重度: CRITICAL | HIGH | MEDIUM | LOW
- 类别: 编排缺陷 | Agent 偏差 | Hook 漂移 | 上下文缺失 | 用户摩擦
- 归属层: Plugin | 用户层 | 项目级
- 涉及: X 个会话, Y 个开发者
- 证据: <aggregate 中的具体数据和组件归因信号>
- 目标文件: <源文件路径，标注所属层>

**Proposed Fix**: <具体修改方案>
**Predicted Effect**: <预期改善的指标及幅度，如"Skill 错误率从 X% → Y%">
**Verification**: <下一轮如何验证——检查哪些 aggregate 信号>
```

将结构化 issues 列表（含 Change Manifest）写入 $WORK_DIR/issues.md。若未发现问题，写入空文件。
```

### 第 5 阶段：展示结果

**步骤 5：展示 issues 列表并持久化**

主会话读取 `$WORK_DIR/issues.md` 并按归属层分组展示给 harness 工程师：

```
## Plugin 层
- Issue 1: ...
- Issue 2: ...

## 用户层
- Issue 3: ...

## 项目级
- Issue 4: ...
```

- 共性模式 = 3+ 开发者共现的 issue，高优先级
- 个人模式 = 1 个开发者的 issue，降级为标记 NEEDS_HUMAN_REVIEW

将 issues 文件拷贝到 `trace_dir`，文件名含时间戳避免覆盖：

```bash
ISSUES_COPY="<trace_dir>/issues-$(date +%Y%m%d-%H%M%S).md"
cp "$WORK_DIR/issues.md" "$ISSUES_COPY"
echo ""
echo "=== Issues 文件: $ISSUES_COPY ==="
```

harness 工程师根据 issues 人工决定后续处理。

### 清理

删除 `trace_dir` 下的原始 trace 包：

```bash
rm -f <trace_dir>/*.tar.gz
```

`$WORK_DIR` 保留不删，供后续查阅。

## 质量门禁

- 第 1 阶段数据不足 → 停止，不进入后续阶段
- 第 3 阶段 `aggregate.sh` 执行失败 → 停止，提示「aggregate.sh 执行失败，检查脚本本身是否存在 bug（如 Python 语法错误、报告格式解析不匹配等），修复后重试」
- 第 3 阶段 `aggregate.md` 平均摩擦评分 < 0.1 且无组件故障热点（sessions ≥ 2）→ 提示「摩擦评分极低，harness 运行良好」，跳过第 4 阶段分析
- 第 3 阶段 `aggregate.md` 中「数据质量」表存在告警 → 将告警展示给 harness 工程师，但**不阻塞**后续分析（数据质量问题不影响已有数据的诊断价值）
  - 若 `duration_ms 全为 0` 影响 ≥80% 会话 → 额外提示「建议先修复 trace-collector hook 的耗时采集后再重新收集数据」
  - 若 `零 Skill/Agent 事件` 影响全部会话 → 提示「会话可能未使用 DevForge skill，或 agent_dispatch 采集存在问题」
- 第 4 阶段 `$WORK_DIR/issues.md` 为空 → 停止，提示「未发现 harness 问题」

## 关联

- **相关 Agent**: `harness-engineer`
- **相关 Hook**: `trace-collector`（PreToolUse + PostToolUse）、`trace-upload`（SessionEnd）
- **相关脚本**: `trace-distill.sh`、`aggregate.sh`
