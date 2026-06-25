# /df:spec-review

文档评审——单轮全维度扫描 + 人工决策门禁。默认只输出问题清单、不做修复；带 `autofix` 时自动修复并循环评审。

## 使用场景

- **手动触发**：`/df:spec-review` 或 `/df:spec-review --change-dir <path>` 做临时体检（例如对话散改后的引用断裂检查）
- **自动修复**：`/df:spec-review autofix` 或 `/df:spec-review autofix --change-dir <path>` 在评审后自动修复问题并循环重评，最多 3 轮

## 输出物

- `<change-dir>/review.md` — AI 评审报告 + Tech Leader 最终决策（留空）
  - 默认 `<change-dir>` 为当前工作目录

## 调用方式

```
/df:spec-review [autofix] [--change-dir <path>]
```

## 参数

- `autofix`（可选）：开启自动修复模式。评审后若未达 PASS，自动派遣 product/architect agent 修复问题，重新评审，最多循环 3 轮
- `--change-dir <path>`（可选）：指定工作目录，默认为当前工作目录
