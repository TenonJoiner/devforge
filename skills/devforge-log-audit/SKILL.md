---
name: devforge-log-audit
description: 日志审计——从「级别合理性」与「打印频率」两维度审查日志质量，静态审源码、运行时析日志文件，输出结构化分级报告
allowed-tools: [Read, Grep, Glob, Bash, Agent]
parameters:
  - name: full
    description: 全仓批量整改——审计全仓所有日志（默认为 MR 门禁范围：本分支相对 trunk 的变更）
    required: false
    default: false
  - name: log-dir
    description: 运行时日志目录，提供后对真实日志文件做频率量化分析（不提供则频率维度不执行）
    required: false
  - name: diff-range
    description: 显式指定 git diff 范围，优先级高于 full（由外部调用方注入）
    required: false
  - name: report-output-path
    description: 审计报告输出路径（由调用方注入，空则用默认 /tmp 路径）
    required: false
---

# devforge-log-audit — 日志审计

## 概述

两个审计维度：**级别合理性**（有无滥用高级别）与 **打印频率**（是否过于频繁）。**级别合理性为纯静态审计，始终执行**；**打印频率为运行时维度**——频率本质取决于运行时调用量，静态无法确认，故**仅在提供 `--log-dir` 时**用真实日志量化，不提供则跳过该维度并在报告标注。

审计知识基线（级别语义 + 反模式 + 判定阈值）内建于 `log-auditor` agent；**项目特定级别定义由第 1 阶段探测后注入 `log-auditor`**。默认只审计不修复。

### 职责边界

- ✅ 探测范围内各语言的日志级别定义（配置/文档/源码反推）与日志框架
- ✅ 派遣 `log-auditor` 执行两维度审计，汇总分级报告
- ✅ 提供 `--log-dir` 时驱动运行时日志量化分析
- ❌ 不修改日志、不改代码（本 skill 只评审）
- ❌ 不评日志文案措辞、标点、大小写等风格偏好 → 超出两维度范围（完全无动态变量的静态消息除外——属结构性缺陷，非措辞问题）
- ❌ 主会话不做深度审计判断（由 `log-auditor` 完成），不读 agent 完整产出（只读 ≤5 行数字摘要）

## 使用场景与审计范围

本 skill 聚焦两个场景：

| 场景 | 审计范围 | 触发方式 | 典型用途 |
|------|---------|---------|---------|
| **全仓批量整改** | 全仓所有日志语句 | `/df:log-audit --full` | 一次性排查并整改存量日志质量 |
| **MR 门禁** | 本 MR 相对目标分支的变更（`git diff $(git merge-base HEAD <trunk>)..HEAD`） | `/df:log-audit`（默认）；CI/门禁经 `diff-range` 注入 | 每个 MR 增量把关，后续接入合并门禁 |

**范围确定优先级**：

1. `diff-range` 参数存在：直接使用（外部门禁 / `pr-review` 注入）
2. `full` 参数存在：全仓批量整改（Grep 全仓日志语句，不做 diff）
3. 都不传（默认）：MR 门禁范围——先检测 trunk（`git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null` 或 `git remote show origin 2>/dev/null | grep 'HEAD branch' | cut -d: -f2`），再 `git diff $(git merge-base HEAD origin/<trunk>)..HEAD`；**检测失败不猜测**，提示用户通过 `--diff-range` 显式指定

**范围铁律**：审计只针对范围内的日志语句。范围外发现降为 LOW，不阻塞本次合并。

> **运行时频率与场景**：`--log-dir` 是频率维度的**唯一开关**。全仓批量整改常能拿到真实日志，建议带 `--log-dir` 量化洪泛；MR 门禁在 CI 中通常无生产日志，此时**只审级别合理性**，频率维度不执行、报告标注未审。

## 审计流程

### 第 1 阶段：级别定义探测（主会话）

审计前必须先弄清"这个项目的级别是怎么定义的"，否则会用通用假设误判项目的自定义约定。

**步骤 1：探测语言与日志框架**
- 按源码文件扫描统计范围内各语言占比（源码后缀计数 → 构建文件佐证）
- **多语言项目**：范围内出现的语言均纳入审计，按语言分别派遣 `log-auditor`（每种语言有独立的日志框架和级别定义）
- 定位各语言的日志框架：搜索日志调用符号（如 `LOG_ERROR`/`zap.`/`logger.`/`slog.`/`spdlog::`）与依赖声明

**步骤 2：探测级别定义**（按优先级）
1. 从源码中定位日志级别定义结构体/枚举/常量（如 `LOG_LEVEL_*` 宏、`Level` enum、`zapcore.Level`），确定可用级别集合——这是最可靠来源
2. 从日志配置文件（`log4j2.xml`、`logback.xml`、`*.conf` 等）或框架初始化代码（zap/slog 初始化、glog flags、spdlog set_level）提取生产默认级别——配置文件通常只设阈值，无法反推全量级别集合
3. 项目文档 / CLAUDE.md / README 中的日志约定作为补充佐证（极少存在，不作为主要来源）

**步骤 3：记录探测结果**——各语言、对应日志框架、可用级别集合（含自定义级别）、生产默认级别（未探测到则显式标注）。探测结果按语言分别注入对应 `log-auditor`，并在报告元数据中记录供人工复核。

> 探测不到明确级别定义时，回退 `log-auditor` 内建通用基线，并在报告中标注"级别定义来源：源码反推/通用基线"。

### 第 2 阶段：日志审计（派遣 `log-auditor`）

派遣 `log-auditor`（多语言时按语言切分，范围大时还可按目录/模块切分多实例并行，合并规则见下）：

**多实例并行合并规则**：多实例时，各 agent 产出独立报告片段（仅「问题清单」节，按 CRITICAL→LOW 排列），主会话负责汇合：
1. 将各片段的问题清单拼接后按级别分组、按 path:line 排序
2. 同一 path:line + 同一问题维度的重复条目只保留一条（取更详细者）
3. 数字摘要为各片段之和，审计范围为各子范围拼接
4. 审计元数据取第一份报告的元数据，频率分析取各片段汇总

1. **级别合理性（始终执行，纯静态）**：逐条核对范围内日志语句级别，对照 `log-auditor` 内建级别滥用反模式标出滥用（高级别滥用、log-and-throw、裸 printf/printStackTrace 等）
2. **打印频率（仅当 `--log-dir` 提供）**：运行 `scripts/analyze_logs.py` 解析真实日志，用各级别计数 / 高频重复消息 Top-N / 打印速率量化洪泛，把确证的高频对回源码打印点并分级。**未提供 `--log-dir` 时本维度不执行**，报告标注"频率维度未审：未提供 --log-dir"，不做静态臆测

`log-auditor` 按 `skills/devforge-log-audit/log-audit-report.md` 生成报告，写入 `report_output_path`，返回数字摘要。

### `log-auditor` 派遣字段（必填，由 skill 注入）

| 字段 | 说明 | 示例 |
|------|------|------|
| `语言` | 第 1 阶段探测（本 agent 实例负责的语言） | `C` / `Go` |
| `日志框架` | 第 1 阶段探测 | `zap` / `spdlog` / `自定义宏 LOG_*` |
| `级别定义` | 可用级别集合 + 生产默认级别（探测所得，含"未探测到"标注） | `TRACE<DEBUG<INFO<WARN<ERROR，生产默认 INFO` |
| `scope` | skill 计算后的审计范围（全仓 / MR diff 命令） | `全仓` / `git diff $(git merge-base HEAD origin/main)..HEAD` |
| `project_levels` | 第 1 阶段探测的级别定义（规范名+别名），注入脚本 `--levels` | `DEBUG,INFO,NOTE,WARN|WARNING,ERROR|ERR,CRITICAL,FATAL,EMIT` |
| `log_dir` | 运行时日志目录，未提供则注入"无" | `/var/log/myapp/` / `无` |
| `analyze_script` | 运行时分析脚本路径 | `scripts/analyze_logs.py` |
| `template_path` | 报告格式契约文件 | `skills/devforge-log-audit/log-audit-report.md` |
| `report_output_path` | 报告写入路径 | `/tmp/log-audit-<ts>.md` |

## 运行时日志分析脚本

`scripts/analyze_logs.py` 是确定性统计工具，避免 agent 手工数日志。级别定义与格式由 skill 注入，不自作假设：

```
python3 scripts/analyze_logs.py --log-dir <dir> \
    --levels "DEBUG,INFO,NOTE,WARN|WARNING,ERROR|ERR,CRITICAL,FATAL,EMIT" \
    [--log-format auto|text|json] \
    [--glob '*.log'] [--top 15] [--json]
```

- `--levels`：第 1 阶段探测结果，逗号分隔，低→高。管道符指定别名：`WARN|WARNING` 表示规范名 WARN，别名 WARNING
- `--log-format`：`auto`（默认，自动探测）、`text`（纯文本正则匹配）、`json`（结构化解析，自动提取 level/msg/ts 字段）

输出各级别计数、总行数、打印速率（时间戳可解析时给稳态/峰值 行/秒）、高频重复消息 Top-N（消息经归一化后聚合：剥离时间戳/数字/十六进制/UUID/引号内容）。`log-auditor` 读取其 `--json` 输出，转化为分级发现，判定阈值见 `log-auditor` 内建频率基线。

## 报告输出

- `report-output-path` 存在则写入该路径；为空则用默认 `/tmp/log-audit-<ts>.md`
- 报告路径通过 `report_output_path` 字段注入 `log-auditor`
- 主会话只读 `log-auditor` 返回的数字摘要（`{critical, high, medium, low, sites}`），据此输出对话摘要与结论，不读报告全文

## 出口标准

- [ ] 第 1 阶段级别定义已探测（探测不到已显式标注回退基线）
- [ ] 级别合理性已审计（始终执行）
- [ ] 打印频率：提供 `--log-dir` 时已量化产出；未提供时报告已标注"频率维度未审：未提供 --log-dir"
- [ ] 报告按 CRITICAL/HIGH/MEDIUM/LOW 分级，结论标注 PASS / NEEDS-FIX
- [ ] **报告格式校验**：主会话对 `log-auditor` 产出做轻量校验——必填章节全部存在（审计元数据 / 级别使用分析 / 频率分析 / 问题清单 / 审计结论）+ 数字摘要与问题清单各级别条目数一致。不通过则要求 `log-auditor` 补全修正（不改审计判断，只补格式）

## 红旗清单

| 红旗 | 触发条件 | 处理方式 |
|------|---------|---------|
| 🚩 级别定义未知 | 文档/配置/源码均无法确定级别集合 | 回退 `log-auditor` 内建通用基线，报告显式标注，不臆造项目约定 |
| 🚩 无日志硬报频率 | 未提供 `--log-dir` 却给出频率缺陷或静态"潜在高频"发现 | 频率维度需真实日志，无 `--log-dir` 时不审频率，报告标注"频率维度未审"，不臆测 |
| 🚩 日志目录不可读 | `--log-dir` 提供但目录不存在/无日志文件 | 跳过运行时分析，报告标注原因，频率维度记为未审 |
| 🚩 主会话越界审计 | 主会话自己逐条判断日志级别/频率 | 回退到派遣 `log-auditor` |
| 🚩 超范围审计 | 评日志文案措辞/结构化字段/脱敏等两维度外问题 | 剔除，本 skill 只审级别 + 频率 |

## 审计后处置

本 skill 只审计不修复。报告产出后，主会话输出数字摘要与结论；用户决定处置策略：

- **接受修复**：对 HIGH/CRITICAL 项逐条确认后，用 `/df:tdd` 逐项整改
- **接受风险**：显式记录某条不修复的原因（如"本 ERROR 确为不可恢复场景，级别正确"），由 `log-auditor` 误报则反馈改进基线
- **批量整改**：全仓场景产出整改清单后，按模块分批用 `/df:tdd` 修复

MR 门禁阻断时，建议在 MR 评论中引用报告路径与数字摘要，便于 reviewer 对照决策。

## Integration

- **相关 Template**：`skills/devforge-log-audit/log-audit-report.md`
- **相关 Agent**：`log-auditor` 执行两维度审计（级别语义 + 反模式 + 判定阈值基线内建于此）
- **相关脚本**：`scripts/analyze_logs.py` 运行时日志量化分析
