# architecture/ 目录导航

本目录存放产品级架构设计文档，遵循 `/ky:arch` 定义的四轮迭代流程规范。

## 当前轮次状态

- **第 1 轮（标杆研究）**：✅ 完成（4/4）
- **第 2 轮（方案发散）**：✅ 完成（5 个维度已落盘）
- **第 3 轮（评估收敛）**：✅ 完成（ADR-001 85% ✓，Connector 87% ✓，Storage 86% ✓，Metadata 85% ✓）
- **第 4 轮（迭代完善）**：🔄 进行中（ADR-005 60% 待提升，design.md 总纲待产出）

## 文档地图

### 正式架构文档（第 3 轮+产出）
- [design.md](design.md) — 系统架构总纲（高置信度时产出）
- [kvcache-manager/](kvcache-manager/) — KVCache Manager 子系统（初稿，待收敛后修订）
- [metadata/](metadata/) — Metadata 子系统
- [storage/](storage/) — Storage 子系统
- [connector/](connector/) — Connector 子系统

### 决策过程文档（第 1-2 轮产出）
详见 [decisions/README.md](decisions/README.md)

### 标杆分析文档（第 1 轮产出）
详见 [reference/](reference/)

## 文档组织规范

| 目录/文件 | 对应轮次 | 文档性质 | 写入要求 |
|-----------|----------|----------|----------|
| `reference/*.md` | 第 1 轮 | 标杆产品/论文分析 | 每个标杆独立一篇，≥2-3 个 |
| `decisions/decision-<name>.md` | 第 2 轮 Step 1/3 | 整体架构/维度探索笔记（正式交付物） | ≥3 候选方案、对比矩阵、评估收敛 |
| `decisions/decision-<name>.research.md` | 第 2 轮 Step 3 子任务 | researcher 原材料（技术深潜） | 可选，内容丰富时独立存档 |
| `design.md` | 第 3 轮+ | 系统架构总纲 | 高置信度时产出 |
| `<subsystem>/design.md` | 第 3 轮+ | 子系统架构主文档 | 高置信度时产出，子目录存放 |
| `<subsystem>/module-*.md` | 第 3 轮+ | 子系统内模块拆分文档 | 可选，当 design.md 超过长度软约束时拆分 |
| `../adr.md` | 第 3 轮 | 架构决策记录 | 中置信度草稿 / 高置信度正式 ADR |

## 命名约定

- `decision-overall.md` — 整体架构方案对比
- `decision-dimensions.md` — 关键技术维度识别
- `decision-<dimension>.md` — 某技术维度的方案探索
- `decision-<dimension>.research.md` — 该维度的 researcher 原材料
- `<subsystem>/design.md` — 子系统架构主文档（如 `storage/design.md`、`transport/design.md`）

## 文档长度与拆分原则

为避免单文档过大导致上下文污染和思考深度下降，采用渐进式披露策略：

- **子系统主文档（design.md）建议长度**：400–800 行
  - 少于 400 行往往意味着论证不充分（rationale、边界分析、风险矩阵缺项）
  - 超过 800 行则建议检查是否混杂了过多实现细节或未拆分的独立模块
- **模块拆分文档（module-*.md）建议长度**：200–600 行
- **拆分信号**：主文档 >800 行，且其中某模块可提取为独立自洽的设计文档时
- **主文档（design.md）只放必须决策的内容**：高层方案对比、rationale、边界图、关键接口抽象
- **模块子文档只放支撑信息**：可选方案的详析、量化数据、接口草稿、扩展讨论
