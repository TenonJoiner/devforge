# /df:design

特性级架构设计——HOW 实现 specs（强制图示）。

> **产品级 vs 特性级**：
> - 产品级（`/df:product-design`）：子系统分解、ADR、系统架构总纲，产出 `docs/architecture/*.md`，可新建子系统
> - 特性级（本命令）：在既有架构内展开，不新建子系统，产出 `docs/changes/<name>/design.md`

## 使用场景

- **手动触发**：`/df:design` 或 `/df:design --change-dir <path>` 做临时设计或修订

## 输出物

- `<change-dir>/design.md` — 特性级架构设计文档（HOW）
  - 默认 `<change-dir>` 为当前工作目录

## 调用方式

调用 Skill 工具加载 `devforge-feature-design`，可选参数 `--change-dir <path>`。
