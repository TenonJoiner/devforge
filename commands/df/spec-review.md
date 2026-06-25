# /df:spec-review

文档评审——按各维度的通过标准逐项判定。默认自动发现 openspec/changes 下的 change 目录；带 `autofix` 时按优先级自动修复所有级别问题并以全新上下文循环重评。

## 使用场景

- **手动触发**：`/df:spec-review` 自动发现 openspec/changes 下的合适 change；或 `/df:spec-review --change-dir <path>` 指定具体目录
- **自动修复**：`/df:spec-review autofix` 或 `/df:spec-review autofix --change-dir <path>` 在评审后按 CRITICAL → HIGH → MEDIUM → LOW 优先级自动修复问题并循环重评，最多 3 轮

## 输出物

- `<change-dir>/review.md` — AI 评审报告 + Tech Leader 最终决策（留空）
  - 默认自动发现 openspec/changes 下的 change 目录；显式 `--change-dir` 时直接使用指定目录

## 调用方式

```
/df:spec-review [autofix] [--change-dir <path>]
```

## 参数

- `autofix`（可选）：开启自动修复模式。评审后若未达 PASS，自动派遣 product/architect agent 按 CRITICAL → HIGH → MEDIUM → LOW 优先级修复问题，然后以全新上下文重新评审，最多循环 3 轮
- `--change-dir <path>`（可选）：直接指定 change 目录，跳过自动发现
