---
name: plan
description: 制定迭代计划与 Backlog 清单。多 Agent 深度思考，按阶段逐步展开，迭代式完善。
---

# /df:plan

制定迭代计划与 Backlog 清单。多 Agent 深度思考，按阶段逐步展开，迭代式完善。

## 使用示例

```
/df:plan                    # 首次启动，从里程碑规划开始
/df:plan                    # 再次调用，自动检测状态并继续
```

## 输出物

- `docs/iteration-plan/milestone-plan.md` — 里程碑计划与 Backlog 清单
- `docs/iteration-plan/iteration-m<x>-i<y>.md` — 各迭代执行计划

## 调用方式

调用 Skill 工具加载 `devforge-plan`
