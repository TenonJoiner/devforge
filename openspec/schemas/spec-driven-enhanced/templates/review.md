## Review Scope

- Proposal：<!-- 文件路径 -->
- Specs：<!-- 文件路径列表 -->
- Design：<!-- 文件路径 -->

## AI Review Rounds

<!-- AI 迭代评审记录，每轮包含问题清单和修复动作 -->

### Round N

**Issues Found**:

| # | Severity | Location | Issue | Fix Applied |
|---|----------|----------|-------|-------------|
| 1 | <!-- CRITICAL/HIGH/MEDIUM/LOW --> | <!-- 文件:章节 --> | <!-- 问题描述 --> | <!-- 修复说明，或"未修复：原因" --> |

**Round Result**: <!-- CRITICAL/HIGH 清零 → 进入下一阶段 / 仍有问题 → 继续迭代 / 达到 5 轮上限 → 停止 -->

## Review Checklist

### Product-level Consistency
- [ ] proposal/specs/design 与产品级文档（docs/requirements/、docs/architecture/）无矛盾
- [ ] 涉及的需求追溯链完整（产品级需求 → proposal → specs → design）

### Requirements Quality (specs)
- [ ] 每条 Requirement 清晰无歧义，可独立验收
- [ ] Requirement 整体能完整支撑 proposal 的目的（无遗漏、无超出）
- [ ] 每条 Requirement 至少有正常路径和异常路径 Scenario

### Design Quality (design)
- [ ] 方案设计合理可行，技术决策不与 specs 矛盾
- [ ] 不违反产品级架构设计原则
- [ ] 方案具备竞争力（性能、可扩展性、可维护性等关键维度有说服力）
- [ ] 所有跨子系统接口变更已声明

## Review Conclusion

### AI 建议（仅供参考）

- **AI 建议决策**：<!-- PASS / PASS WITH CONDITIONS / REJECT -->
- **建议理由**：<!-- AI 的评审总结 -->
- **遗留问题**：<!-- 需在 tasks 阶段解决的问题 -->

### 交叉评审记录

<!-- 各评审人在此记录评审意见，每人一条 -->
<!-- 格式：
- **评审人**：<姓名> | **日期**：<YYYY-MM-DD> | **结论**：PASS / PASS WITH CONDITIONS / REJECT
  - <评审意见和发现的问题>
-->

### Tech Leader 最终决策（必填——未填写则不允许进入 tasks 阶段）

> **决策选项说明**：
> - **PASS** — 评审通过，直接进入 tasks 分解阶段
> - **PASS WITH CONDITIONS** — 有条件通过，进入 tasks 阶段但必须在任务分解中落实「附加条件」中列出的要求
> - **REJECT** — 评审驳回，需根据「决策理由」修改 specs/design 后重新评审（删除 review.md 后执行 `/opsx:continue`）

- **决策**：<!-- PASS / PASS WITH CONDITIONS / REJECT -->
- **决策人**：<!-- Tech Leader 姓名 -->
- **决策日期**：<!-- YYYY-MM-DD -->
- **决策理由**：<!-- 综合交叉评审意见，简要说明同意/驳回的原因 -->
- **附加条件**：<!-- PASS WITH CONDITIONS 时必填，说明进入 tasks 前须满足的条件；PASS 时填"无" -->
