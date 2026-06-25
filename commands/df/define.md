# /df:define

特性级需求定义——Requirement + Scenario（Delta 格式）。

> 产品级需求定义使用 `/df:product-define`。

## 使用场景

- **手动触发**：`/df:define` 自动发现 `openspec/changes` 下的合适 change；或 `/df:define --change-dir <path>` 指定具体目录做临时定义或修订

## 输出物

- `<change-dir>/specs/*.md` — 特性级需求规范（Delta 格式）
  - 默认自动发现 `openspec/changes` 下的 change 目录；显式 `--change-dir` 时直接使用指定目录

## 调用方式

```
/df:define [--change-dir <path>]
```
