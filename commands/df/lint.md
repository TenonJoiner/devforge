# /df:lint

编译检查与静态分析——零 warning 验证。

## 用法

```
/df:lint [autofix]
```

| 参数 | 说明 |
|------|------|
| （无） | 只检测不修复，输出检查报告 |
| `autofix` | 检测后自动修复问题并回归检查 |

## 产出物

检查报告（输出到对话，不写入文件）。

- **不带 `autofix`**：输出问题清单和分析报告后结束，不执行修复
- **带 `autofix`**：发现问题后派遣 `developer` 修复并回归检查（最多 5 轮）

## 示例

**只检测不修复（默认）**：

```
/df:lint
> L1 编译检查
>   ✗ make: FAILED
>     error: handler.c:89: implicit declaration of function 'write_record'
>     warning: handler.c:45: unused variable 'rc'
> (L1 未通过，结束)
```

**检测并自动修复**：

```
/df:lint autofix
> L1 编译检查
>   ✓ make: PASSED
> Lint 分析报告
>   需修复 1 条：
>     1. handler.c:89 空指针解引用 — 未检查 malloc 返回值 — 添加 NULL 检查
>   排除 3 条：误报 1 / 有意为之 1 / 非本次变更引入 1
```

执行细节进入 `devforge-lint-check` Skill。

## 关联

- **Skill**: `devforge-lint-check`
- **Agent**: `developer`
- **Rules**: `coding-style.md`、`coding-style-<lang>.md`