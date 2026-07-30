# /df:log-audit

日志审计——检查日志级别是否合理、打印是否过于频繁。

## 用法

```
/df:log-audit [--full] [--log-dir <path>] [--diff-range <range>]
```

| 参数 | 说明 |
|------|------|
| （无） | **MR 门禁**：审计本 MR 相对目标分支的变更（trunk 自动检测） |
| `--full` | **全仓批量整改**：审计全仓所有日志语句 |
| `--log-dir <path>` | 指定运行时日志目录——提供后两维度均执行：频率量化 + 运行时增强的级别审计（日志分布/高频模板作为级别滥用的实证线索） |
| `--diff-range <range>` | （内部参数）CI/门禁由 `pr-review` 等调用方注入显式 diff 范围，覆盖 trunk 自动检测 |

## 产出物

结构化日志审计报告（默认 `/tmp/log-audit-<ts>.md`），按 CRITICAL / HIGH / MEDIUM / LOW 分级。无 `--log-dir` 时仅做级别合理性审计；提供 `--log-dir` 时两维度均执行（频率量化 + 运行时增强的级别审计）。只评审不修复。

## 示例

**MR 门禁（默认）**：

```
/df:log-audit
> 探测：语言 Go，框架 zap，生产默认 INFO
> 审计本 MR 变更（相对 origin/main）｜频率维度未审（未提供 --log-dir）
> CRITICAL 0 | HIGH 1 | MEDIUM 1 | LOW 1
> 结论: NEEDS-FIX（存在 HIGH，阻断合并）
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
