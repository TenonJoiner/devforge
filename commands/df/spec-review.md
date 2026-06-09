# /df:spec-review

OpenSpec 文档评审——单轮全维度扫描 + 人工决策门禁。评审 proposal/specs/design，输出问题清单 + AI 建议。不做修复。

## 使用场景

- **OpenSpec workflow 自动触发**：`/opsx:continue` 走到 review artifact 时自动调用
- **手动临时体检**：任意时刻直接 `/df:spec-review` 做临时体检（例如对话散改后的引用断裂检查）

## 输出物

- `openspec/changes/<change-name>/review.md` — AI 评审报告 + Tech Leader 最终决策（留空）

## 调用方式

调用 Skill 工具加载 `devforge-spec-review`
