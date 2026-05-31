# /df:define

特性级需求定义——Requirement + Scenario（Delta 格式）。用于 OpenSpec workflow 的 specs artifact 生成。

> 产品级需求定义使用 `/df:product-define`。

## 使用场景

- **OpenSpec workflow 自动触发**：`/opsx:continue` 走到 specs artifact 时自动调用
- **手动触发**：任意时刻直接 `/df:define` 做临时定义或修订

## 输出物

- `openspec/changes/<change-name>/specs/*.md` — Delta 格式 Requirement + Scenario

## 调用方式

调用 Skill 工具加载 `devforge-feature-define`
