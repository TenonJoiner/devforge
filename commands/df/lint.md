# /df:lint

编译检查与静态分析——零 warning 验证。

## 用法

```
/df:lint [autofix] [--full] [--diff-range <range>]
```

| 参数 | 说明 |
|------|------|
| （无） | 检查工作区未提交变更（`git diff HEAD` + `git diff --cached`），只检测不修复 |
| `autofix` | 检测后自动修复问题并回归检查（最多 5 轮） |
| `--full` | 全仓 lint 检查 |
| `--diff-range <range>` | 显式指定 git diff 范围，优先级最高（由 pr-review 等调用方注入） |

## 场景

| 触发 | 场景 | 命令来源 |
|------|------|---------|
| `/df:lint` | 检查未提交变更 | 项目上下文 → 探测确认，diff 透传给 lint 脚本 |
| `/df:lint --full` | 全仓 lint | 项目上下文 → 探测确认 |
| `/df:lint --diff-range <range>` | MR 门禁 | 项目上下文 → 探测确认，范围透传给 lint 脚本 |

## 产出物

检查报告（输出到对话，不写入文件）。

- **不带 `autofix`**：输出经源码+规则交叉验证后的分析报告，不执行修复
- **带 `autofix`**：对确认需修复的问题派遣 `developer` 修复并回归检查（最多 5 轮）

lint 原始告警不是最终结果。每条告警经 `developer` 读源码、查规则后做四维判定（是否误报 / 是否需修复 / 级别是否合适 / 规则是否合理），结果直接覆盖原报告，同时给出规则层面的建议（屏蔽/新增）。

## 示例

**未提交变更（默认）**：

```
/df:lint
> 范围: 未提交变更
> L1 编译检查
>   ✓ make build: PASSED
> L2 Lint 分析
>   ✓ make lint-changed: 零告警通过
```

**全仓 lint**：

```
/df:lint --full
> 范围: 全量
> L1 编译检查
>   ✓ make build: PASSED
> L2 Lint 分析
>   ✓ make lint: 零告警通过
```

**MR 门禁**（通常由 pr-review 调用）：

```
/df:lint --diff-range "git diff origin/main...HEAD"
> 范围: MR
> L1 编译检查
>   ✓ make build: PASSED
> L2 Lint 分析
>   ✓ ci/lint.sh "git diff origin/main...HEAD": 零告警通过
```

执行细节进入 `devforge-lint-check` Skill。

## 关联

- **Skill**: `devforge-lint-check`
- **Agent**: `developer`
- **Rules**: `coding-style.md`、`coding-style-<lang>.md`
