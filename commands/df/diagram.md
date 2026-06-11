---
name: diagram
description: 从架构文档自动生成可编辑的 drawio 架构图。
---

# /df:diagram

从架构文档自动生成可编辑的 drawio 架构图。

## 使用场景

- 已有 `design.md` 或架构文档，需要生成可视化图示
- `devforge-feature-design` / `devforge-product-design` 的强制图示环节自动调用
- 手动补充或更新现有图示

## 输出物

- `<doc-name>-<type>.drawio` — 可编辑的 drawio 源文件
- 可选：`.drawio.png` / `.drawio.svg` / `.drawio.pdf`（导出格式）

## 调用方式

```
/df:diagram                          # 从当前目录 design.md 生成
/df:diagram <path/to/design.md>      # 指定源文档
/df:diagram png                      # 生成并导出为 PNG
/df:diagram svg <path/to/doc.md>     # 指定文档 + SVG 导出
/df:diagram url                      # 生成浏览器可打开的 URL
```

**支持的图示类型**（自动推断或手动指定）：
- 结构图（≥3 组件）
- 时序图（跨组件交互）
- 状态机图（生命周期对象）
- 数据流图（读写路径分离）

调用 Skill 工具加载 `devforge-diagram`。
