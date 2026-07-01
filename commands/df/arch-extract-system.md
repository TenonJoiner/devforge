# /df:arch-extract-system

从已有 subsystem 文档汇总合成系统级架构总览——描述架构分层、设计思想、子系统全景和全局设计约束。不分析源码。

> **system vs subsystem vs topic**：
> - system（本命令）：产品级架构文档，定义架构分层、子系统边界、全局约束
> - subsystem（`/df:arch-extract-subsystem`）：子系统级架构总览，展开各层内部设计
> - topic（`/df:arch-extract-topic`）：最深层的技术主题设计文档

## 使用场景

- 已有 ≥2 个 subsystem 文档后，合成系统级架构总览
- 新人 onboarding 的第一份架构文档
- 首次使用 DevForge 架构文档体系时，推荐顺序：topic → subsystem → system（本命令最后执行）

## 前置条件

- `docs/architecture/` 下已有 ≥2 个 `<subsystem>/overview.md`（由 `/df:arch-extract-subsystem` 生成）

## 输出物

- `docs/architecture/system-overview.md` — 系统级架构总览文档（8-10 页，≤300 行）

## 调用方式

```
/df:arch-extract-system
```

无需参数——自动扫描 `docs/architecture/` 下所有 subsystem 文档。
