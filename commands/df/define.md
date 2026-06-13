# /df:define

特性级需求定义——Requirement + Scenario（Delta 格式）。

> 产品级需求定义使用 `/df:product-define`。

## 使用场景

- **手动触发**：`/df:define` 或 `/df:define --change-dir <path>` 做临时定义或修订

## 输出物

- `<change-dir>/specs/*.md` — 特性级需求规范（Delta 格式）
  - 默认 `<change-dir>` 为当前工作目录

## 调用方式

调用 Skill 工具加载 `devforge-feature-define`，可选参数 `--change-dir <path>`。
