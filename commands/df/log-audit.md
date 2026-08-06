# /df:log-audit

日志审计——检查日志级别是否合理、打印是否过于频繁。

## 用法

```
/df:log-audit [--autofix] [--full] [--log-dir <path>] [--diff-range <range>] [--report-output-path <path>]
```

| 参数 | 说明 |
|------|------|
| （无） | 审计工作区未提交变更（`git diff HEAD` + `git diff --cached`），只审计不修复 |
| `--autofix` | 审计后自动修复日志问题并回归验证（最多 5 轮） |
| `--full` | **全仓批量整改**：审计全仓所有日志语句 |
| `--log-dir <path>` | 指定运行时日志目录——提供后两维度均执行：频率量化 + 运行时增强的级别审计（日志分布/高频模板作为级别滥用的实证线索） |
| `--diff-range <range>` | 显式指定 git diff 范围，优先级最高（由 pr-review 等调用方注入） |
| `--report-output-path <path>` | 指定报告写入路径，未提供时使用默认 `/tmp/log-audit-<ts>-<pid>.md` |

## 产出物

结构化日志审计报告（默认 `/tmp/log-audit-<ts>-<pid>.md`），按 CRITICAL / HIGH / MEDIUM / LOW 分级。无 `--log-dir` 时仅做级别合理性审计；提供 `--log-dir` 时两维度均执行（频率量化 + 运行时增强的级别审计）。带 `--autofix` 时审计后自动修复 CRITICAL/HIGH 问题并回归验证（最多 5 轮）。

## 示例

**未提交变更（默认）**：

```
/df:log-audit
> 探测：语言 Go，框架 zap，生产默认 Informational
> 审计未提交变更（3 个文件）｜频率维度未审（未提供 --log-dir）
> CRITICAL 0 | HIGH 1 | MEDIUM 1 | LOW 1
> 结论: NEEDS-FIX
```

**全仓批量整改（结合真实日志）**：

```
/df:log-audit --full --log-dir /var/log/myapp
> 运行时统计：1.2M 行，稳态 180 行/秒，峰值 900 行/秒
> 级别分布：NOTE 85%、INFO 12%、WARN 2%、ERROR 1% — NOTE 占比异常
> CRITICAL 1（NOTE 级别体系失效）| HIGH 2 | MEDIUM 3
> 产出全仓分级整改清单
```

## 关联

- **Skill**: `devforge-log-audit`
- **Agent**: `log-auditor`（内建级别语义 + 反模式 + 判定阈值基线）
