# /df:lint

编译检查与静态分析——零 warning 验证 + 多语言静态分析工具链，按项目配置自动探测。

## 用法

```
/df:lint [target | --full]
```

| 参数 | 说明 |
|------|------|
| （无） | 根据 git 状态自动判定范围（增量/分支全量） |
| `<file-or-dir>` | 只检查指定目标 |
| `--full` | 强制分支全量（feature 分支相对于 main 的变更，不是全项目） |

## 产出物

检查报告（输出到对话，不写入文件）。通过时零 error 零 warning，失败时列出问题清单。

## 示例

```
/df:lint
> L1 编译检查: ✓ 0 error, 0 warning
> L2 静态分析: ✓ clang-tidy: 0 error, 0 warning
> 总计: 0 error, 0 warning
```

执行细节进入 `devforge-lint-check` Skill，自动探测构建系统、执行 L1+L2、发现问题派遣 `developer` 修复并回归（最多 5 轮）。

## 关联

- **Skill**: `devforge-lint-check`
- **Agent**: `developer`
- **Rules**: `coding-style.md`、`coding-style-<lang>.md`
- **Hooks**: `pre-commit-lint`
