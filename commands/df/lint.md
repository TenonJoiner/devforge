# /df:lint

编译检查与静态分析——零 warning 验证。支持本地开发和 CI 两种模式。

## 用法

```
/df:lint [autofix] [--diff-range <range>]
```

| 参数 | 说明 |
|------|------|
| （无） | **本地开发模式**：本地分支相对主干的差异代码 lint，只检测不修复 |
| `autofix` | 检测后自动修复问题并回归检查（可与模式参数叠加） |
| `--diff-range <range>` | **CI 模式**：显式指定 git diff 范围（由 CI/pr-review 注入） |

## 模式

| 模式 | 触发 | 命令选择偏好 |
|------|------|-------------|
| 本地开发 | `/df:lint` | 优先增量检查命令（如 `make lint-changed`） |
| CI | `/df:lint --diff-range ...` | 优先 CI 脚本（如 `ci/lint.sh`） |

具体命令从项目上下文（CLAUDE.md/README/rules）中发现，参数不绑死。未找到时探测项目脚本并向用户确认。

## 产出物

检查报告（输出到对话，不写入文件）。

- **不带 `autofix`**：输出问题清单和分析报告后结束，不执行修复
- **带 `autofix`**：发现问题后派遣 `developer` 修复并回归检查（最多 5 轮）

## 示例

**本地开发（默认）**：

```
/df:lint
> 模式: 本地开发
> L1 编译检查
>   ✓ make build-debug: PASSED
> L2 Lint 分析
>   ✓ make lint-changed: 零告警通过
```

**CI 模式**：

```
/df:lint --diff-range "origin/main..HEAD"
> 模式: CI
> L1 编译检查
>   ✓ ci/build.sh: PASSED
> L2 Lint 分析
>   ✓ ci/lint.sh: 零告警通过
```

执行细节进入 `devforge-lint-check` Skill。

## 关联

- **Skill**: `devforge-lint-check`
- **Agent**: `developer`
- **Rules**: `coding-style.md`、`coding-style-<lang>.md`
