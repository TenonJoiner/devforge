# decisions/ 目录导航

本目录存放第 1-2 轮架构决策过程中的探索性文档。

**核心原则**：
- `decision-*.md` 是面向架构决策的**正式探索笔记**
- `decision-*.research.md` 是 researcher 产出的**原材料/技术深潜**
- 两者**成对出现**，便于追溯决策依据

## 文档清单

### 整体架构
- [decision-overall.md](decision-overall.md) — KVCache Offloading 整体架构方案对比（3 个候选方案）
- [decision-dimensions.md](decision-dimensions.md) — 关键技术维度识别（9 个维度）

### 逐维度探索
| 维度 | 探索笔记 | 原材料 |
|------|----------|--------|
| 缓存索引与查找 | [decision-indexing.md](decision-indexing.md) | [decision-indexing.research.md](decision-indexing.research.md) |
| 分层存储介质组织 | [decision-tiering.md](decision-tiering.md) | [decision-tiering.research.md](decision-tiering.research.md) |
| Cache Block 粒度与对齐 | [decision-block-granularity.md](decision-block-granularity.md) | [decision-block-granularity.research.md](decision-block-granularity.research.md) |
| 数据传输与 IO 路径 | [decision-transport.md](decision-transport.md) | [decision-transport.research.md](decision-transport.research.md) |
| 与推理引擎集成接口 | [decision-integration.md](decision-integration.md) | [decision-integration.research.md](decision-integration.research.md) |

## 文档规范

### decision-*.md 必须包含
1. 探索目标和关联维度
2. ≥3 个候选方案（核心思路、参考来源、标杆映射）
3. 方案对比矩阵（量化指标）
4. 优缺点分析
5. 评估收敛（置信度、待验证假设、关键 trade-off）

### decision-*.research.md 必须包含
1. 问题背景与必要性
2. 核心原理（算法/数据结构/复杂度）
3. 设计机制（架构划分、数据流、接口抽象）
4. 性能剖析与量化数据
5. Trade-off 分析（至少 4 个维度）
