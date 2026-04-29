# /df:define

定义产品需求、制定验收标准。多 Agent 深度思考，标杆研究先行，Feature-Scenario 分层展开，螺旋式迭代完善。

## 使用示例

```
/df:define                    # 首次启动，从产品定位确认开始
/df:define                    # 再次调用，自动检测状态并继续
```

## 输出物

- `docs/requirements/product-spec.md` — 全局需求总纲
- `docs/requirements/<feature-domain>.md` — 按特性域组织的需求规格
- `docs/requirements/reference/<product>.md` — 标杆需求分析

## 调用方式

调用 Skill 工具加载 `product/define`
