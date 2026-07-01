# /df:arch-extract-subsystem

逆向提取子系统架构总览文档——分析一个子系统的源码，识别内部组件拓扑、对外接口契约、设计约束，汇总子系统内各技术主题的定位和关系。

> **subsystem vs topic vs system**：
> - subsystem（本命令）：子系统级架构总览，描述组件拓扑、模块分工、对外接口契约
> - topic（`/df:arch-extract-topic`）：深层设计文档，聚焦单个技术主题的内部机制
> - system（`/df:arch-extract-system`）：系统级架构总览，从 subsystem 文档合成

## 使用场景

- 了解一个子系统的整体架构和与周边子系统的关系
- 为后续 topic 分析提供架构全景和上下文
- 首次使用 DevForge 架构文档体系时，推荐顺序：topic → subsystem → system

## 输出物

- `docs/architecture/<subsystem>/overview.md` — 子系统架构总览文档（8-10 页，≤300 行）

## 调用方式

```
/df:arch-extract-subsystem --target=<子系统名> [--doc=<社区文档目录>]
```

**参数**：
- `--target`（必选）：子系统名，如 "storage""network""scheduler"
- `--doc`（可选）：社区文档目录（上游开源项目的文档）

**示例**：
```
/df:arch-extract-subsystem --target=storage
/df:arch-extract-subsystem --target=network --doc=docs/community/
```
