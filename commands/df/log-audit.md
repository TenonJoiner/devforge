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
| `--log-dir <path>` | 指定运行时日志目录——**频率维度仅在此时执行**，用真实日志量化各级别计数/高频重复/打印速率，定位洪泛 |
| `--diff-range <range>` | （内部参数）CI/门禁由 `pr-review` 等调用方注入显式 diff 范围，覆盖 trunk 自动检测 |

## 产出物

结构化日志审计报告（默认 `/tmp/log-audit-<ts>.md`），按 CRITICAL / HIGH / MEDIUM / LOW 分级。两个维度——级别合理性（纯静态，无 `--log-dir` 时执行）与打印频率（仅 `--log-dir` 提供时），两者互斥。只评审不修复。

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
> CRITICAL 1 | HIGH 1 | MEDIUM 2
> 产出全仓分级整改清单
```

## 关联

- **Skill**: `devforge-log-audit`
- **Agent**: `log-auditor`（内建级别语义 + 反模式 + 判定阈值基线）
