# /df:design

探索产品架构方案、竞品分析、子系统分解。多 agent 深度思考，标杆研究先行。

## 使用示例

```
/df:design                    # 首次启动，从前置调研开始
/df:design                    # 再次调用，自动检测状态并继续
```

## 输出物

- `docs/architecture/reference/*.md` — 标杆分析
- `docs/architecture/decisions/decision-*.md` — 决策过程文档
- `docs/architecture/adr.md` — 架构决策记录
- `docs/architecture/design.md` — 系统架构总纲
- `docs/architecture/<subsystem>/design.md` — 子系统架构主文档

## 执行前必读

**CRITICAL**：Skill 工具加载后，立即读取 `.claude/skills/devforge-design/SKILL.md`，定位当前阶段，精读该阶段的"执行方式"部分，然后输出"执行方式确认"后再开始执行。

## 调用方式

调用 Skill 工具加载 `product/design`
