---
name: lint
description: 编译检查与静态分析——零 warning 验证 + 多语言静态分析工具链，按项目配置自动探测。
---

# /df:lint

编译检查与静态分析——零 warning 验证 + 多语言静态分析工具链，按项目配置自动探测。

## 用法

```
/df:lint [autofix] [target | --full]
```

| 参数 | 说明 |
|------|------|
| （无） | 根据 git 状态自动判定范围，只检测不修复 |
| `autofix` | 检测后自动修复问题并回归检查 |
| `<file-or-dir>` | 只检查指定目标 |
| `--full` | 强制分支全量（feature 分支相对于 main 的变更，不是全项目） |

## 产出物

检查报告（输出到对话，不写入文件）。通过时零 error 零 warning，失败时列出问题清单。

- **不带 `autofix`**：输出问题清单后结束，不执行修复
- **带 `autofix`**：发现问题后派遣 `developer` 修复并回归检查（最多 5 轮）

## 示例

**只检测不修复（默认）**：

```
/df:lint
> L1 编译检查: ✗ 1 error, 2 warning
>   - handler.c:89: error: implicit declaration of function 'write_record'
>   - handler.c:45: warning: unused variable 'rc'
>   - engine.c:2100: warning: variable 'idx' set but not used
> L2 静态分析: (跳过，L1 未通过)
> 总计: 1 error, 2 warning — 需修复
```

**检测并自动修复**：

```
/df:lint autofix
> L1 编译检查: ✓ 0 error, 0 warning
> L2 静态分析: ✓ clang-tidy: 0 error, 0 warning
> 总计: 0 error, 0 warning
```

执行细节进入 `devforge-lint-check` Skill，自动探测构建系统、执行 L1+L2。

## 关联

- **Skill**: `devforge-lint-check`
- **Agent**: `developer`（仅 `autofix` 模式）
- **Rules**: `coding-style.md`、`coding-style-<lang>.md`
- **Hooks**: `pre-commit-lint`
