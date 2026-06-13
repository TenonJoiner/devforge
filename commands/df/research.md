# /df:research

特性级研究——约束清单、标杆方案空间、设计空间地图。

> 产品级标杆调研使用 `/df:product-design` 第 1 阶段。

## 使用场景

- **手动触发**：`/df:research` 或 `/df:research --change-dir <path>` 做研究

## 输出物

- `<change-dir>/research.md` — 约束清单 + 标杆方案空间 + 设计空间地图
  - 默认 `<change-dir>` 为当前工作目录

## 调用方式

调用 Skill 工具加载 `devforge-feature-research`，可选参数 `--change-dir <path>`。
