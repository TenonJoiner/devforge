# /df:arch-extract-topic

逆向提取技术主题深度设计文档——跨目录追踪一个技术主题（如协程调度模型、本地存储引擎、Raft 共识），深入分析其设计，生成单篇 topic 文档。

> **topic vs subsystem vs system**：
> - topic（本命令）：最深层的设计文档，聚焦单个技术主题的"怎么做"和"为什么这样做"
> - subsystem（`/df:arch-extract-subsystem`）：子系统级架构总览，描述组件拓扑和模块间关系
> - system（`/df:arch-extract-system`）：系统级架构总览，从 subsystem 文档合成

## 使用场景

- 深入理解某个跨目录的技术主题的架构设计
- 配合社区文档 `--doc` 发现设计意图与代码实现的差异
- 首次使用 DevForge 架构文档体系时，推荐顺序：topic → subsystem → system

## 输出物

- `docs/architecture/<subsystem>/<topic>.md` — 技术主题深度设计文档（14-17 页，≤500 行）

## 调用方式

```
/df:arch-extract-topic --target=<主题名> [--doc=<社区文档目录>]
```

**参数**：
- `--target`（必选）：技术主题名，如 "协程调度模型""本地存储引擎""Raft 共识"
- `--doc`（可选）：社区文档目录（上游开源项目的文档），用于提供设计背景和概念框架

**示例**：
```
/df:arch-extract-topic --target=协程调度
/df:arch-extract-topic --target=本地存储引擎 --doc=docs/community/
```
