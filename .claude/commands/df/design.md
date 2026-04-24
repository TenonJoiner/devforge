# /df:design

探索产品架构方案、竞品分析、子系统分解。多 agent 深度思考，标杆研究先行，长时间迭代。

## 何时使用

- 系统架构设计（长期迭代，非一次对话完成）
- 重大技术决策 / 竞品分析 / 方案对比
- 架构重构评估 / 子系统分解调整
- 继续完善已有架构文档（螺旋式迭代）

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

## 关联

- Skill: `product/design`
- Rules: `workflow`、`coding-style`
