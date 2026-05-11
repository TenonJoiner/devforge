# /df:design

探索产品架构方案、竞品分析、子系统分解。多 Agent 深度思考，标杆研究先行。

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

## 调用方式

调用 Skill 工具加载 `devforge-design`
