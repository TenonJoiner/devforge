# /df:lint

编译检查与静态分析——零 warning 验证。支持 `branch` 和 `mr` 两种场景。

## 用法

```
/df:lint [autofix] [--mr <url>]
```

| 参数 | 说明 |
|------|------|
| （无） | `branch` 模式，只检测不修复 |
| `autofix` | 检测后自动修复问题并回归检查（可与 `--mr` 叠加） |
| `--mr <url>` | MR 模式，对指定 MR 的源分支与目标分支差异做 lint（CI 场景） |

## 场景

| 触发 | 场景 | 命令来源 |
|------|------|---------|
| `/df:lint` | 开发期间本地检查 | 项目上下文 → 探测确认 |
| `/df:lint --mr <url>` | 提交 MR 后 CI 检查 | 项目上下文 → 探测确认，URL 透传给脚本 |

具体命令从项目上下文（CLAUDE.md 等）中发现，参数不绑死。

## 产出物

检查报告（输出到对话，不写入文件）。

- **不带 `autofix`**：输出问题清单和分析报告后结束，不执行修复
- **带 `autofix`**：发现问题后派遣 `developer` 修复并回归检查（最多 5 轮）

## 示例

**branch 模式（本地开发）**：

```
/df:lint
> 模式: branch
> L1 编译检查
>   ✓ make build: PASSED
> L2 Lint 分析
>   ✓ make lint-changed: 零告警通过
```

**mr 模式（CI）**：

```
/df:lint --mr https://github.com/org/repo/pull/123
> 模式: mr
> L1 编译检查
>   ✓ make build: PASSED
> L2 Lint 分析
>   ✓ ci/lint.sh --mr https://github.com/org/repo/pull/123: 零告警通过
```

执行细节进入 `devforge-lint-check` Skill。

## 关联

- **Skill**: `devforge-lint-check`
- **Agent**: `developer`
- **Rules**: `coding-style.md`、`coding-style-<lang>.md`
