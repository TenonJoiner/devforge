# /df:spec-review

文档评审——单轮全维度扫描 + 人工决策门禁。评审 proposal/specs/design，输出问题清单 + AI 建议。不做修复。

## 使用场景

- **手动触发**：`/df:spec-review` 或 `/df:spec-review --change-dir <path>` 做临时体检（例如对话散改后的引用断裂检查）

## 输出物

- `<change-dir>/review.md` — AI 评审报告 + Tech Leader 最终决策（留空）
  - 默认 `<change-dir>` 为当前工作目录

## 调用方式

调用 Skill 工具加载 `devforge-spec-review`，可选参数 `--change-dir <path>`。
