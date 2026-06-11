---
name: define
description: 特性级需求定义——Requirement + Scenario（Delta 格式）。
---

# /df:define

特性级需求定义——Requirement + Scenario（Delta 格式）。

> 产品级需求定义使用 `/df:product-define`。

## 使用场景

- **手动触发**：任意时刻直接 `/df:define` 做临时定义或修订

## 输出物

- `docs/changes/<change-name>/specs/*.md` — Delta 格式 Requirement + Scenario

## 调用方式

调用 Skill 工具加载 `devforge-feature-define`
