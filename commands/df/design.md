# /df:design

特性级架构设计——HOW 实现 specs（强制图示）。

> **产品级 vs 特性级**：
> - 产品级（`/df:product-design`）：子系统分解、ADR、系统架构总纲，产出 `docs/architecture/*.md`，可新建子系统
> - 特性级（本命令）：在既有架构内展开，不新建子系统，产出 `docs/changes/<name>/design.md`

## 使用场景

- **手动触发**：任意时刻直接 `/df:design` 做临时设计或修订

## 输出物

- `docs/changes/<change-name>/design.md` — Context + Decisions + Interface Changes + Risks + Upgrade Compatibility Statement

## 调用方式

调用 Skill 工具加载 `devforge-feature-design`
