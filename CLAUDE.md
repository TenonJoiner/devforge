# 产品级文档索引

特性级 skill（如 `/df:research`、`/df:define`、`/df:design`）通过此索引定位产品级文档。
新增产品级文档时同步更新本节，否则特性级 skill 检索不到。

## 文档根

- `docs/architecture/` — 产品级架构文档
  - `docs/architecture/design.md` — 系统架构总纲（如存在）
  - `docs/architecture/adr.md` — 架构决策记录（如存在）
  - `docs/architecture/<subsystem>/design.md` — 子系统架构主文档
  - `docs/architecture/reference/` — 标杆产品研究资料
- `docs/requirements/` — 产品级需求文档
  - `docs/requirements/product-spec.md` — 产品规格总纲
  - `docs/requirements/<feature>.md` — Feature 详细需求与验收标准
  - `docs/requirements/<feature>-review.md` — Feature 评审记录
  - `docs/requirements/reference/` — 需求参考资料
- `docs/iteration-plan/` — 迭代计划（如存在）
  - `docs/iteration-plan/milestone-plan.md` — 里程碑 + Backlog
  - `docs/iteration-plan/iteration-m*-i*.md` — 各迭代执行计划
- `docs/test-strategy.md` — 测试策略（如存在）

## 检索约定

- skill 启动时只读相关章节，不通读整个目录
- 按 proposal 关键词在文件名和章节标题中匹配
- 命中文档后再局部读取相关段落
- 检索不到时标记「未知约束」并提示主人补充，不阻塞流程
