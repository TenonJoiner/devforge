# /df:design

特性级架构设计——HOW 实现 specs（强制图示）。用于 OpenSpec workflow 的 design artifact 生成。

> **产品级 vs 特性级**：
> - 产品级（`/df:product-design`）：子系统分解、ADR、系统架构总纲，产出 `docs/architecture/*.md`，可新建子系统
> - 特性级（本命令）：在既有架构内展开，不新建子系统，产出 `openspec/changes/<name>/design.md`

## 使用场景

- **OpenSpec workflow 自动触发**：`/opsx:continue` 走到 design artifact 时自动调用
- **手动触发**：任意时刻直接 `/df:design` 做临时设计或修订

## 输出物

- `openspec/changes/<change-name>/design.md` — Context + Decisions + Interface Changes + Risks + Migration Plan

## 调用方式

调用 Skill 工具加载 `devforge-feature-design`
