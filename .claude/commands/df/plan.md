# /df:plan

制定迭代计划和 proposal 清单。

## 使用示例

```
/df:plan
```

## 输出物

```
docs/iteration-plan/
├── milestone-plan.md      # 第 1 阶段：里程碑计划 + Backlog 清单
├── iteration-m1-i1.md     # 第 2 阶段：迭代执行计划
└── ...
```

## 执行前必读

**CRITICAL**：Skill 工具加载后，立即读取 `.claude/skills/product/plan/SKILL.md`，定位当前阶段，精读该阶段的"执行方式"部分，然后输出"执行方式确认"后再开始执行。

## 调用方式

调用 Skill 工具加载 `product/plan`
