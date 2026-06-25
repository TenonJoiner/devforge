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

**Round Result**: <!-- 本轮各文档缺陷密度：proposal.md: X.X | specs/*.md: X.X | design.md: X.X（与 ≤ 3.0 标准对比） -->

## Review Conclusion

<!-- 评审标准参见 schema.yaml 中 review 阶段的「评审标准」定义 -->

### AI 建议（仅供参考）[AI 填写]

- **AI 建议决策**：<!-- PASS / PASS WITH CONDITIONS / REJECT -->
- **建议理由**：<!-- AI 的评审总结 -->
- **遗留问题**：<!-- 评审中发现的需要后续关注的事项（供 Tech Leader 决策参考，不自动转入 tasks；实际约束以「附加条件」为准） -->

### Tech Leader 最终决策（必填——未填写则不允许进入 tasks 阶段）[人工填写]

> **决策选项说明**：
> - **PASS** — 评审通过，直接进入 tasks 分解阶段
> - **PASS WITH CONDITIONS** — 有条件通过，允许进入 tasks 阶段，但附加条件中的事项需并行跟进并在归档前闭环
> - **REJECT** — 评审驳回，需根据「决策理由」修改 specs/design 后重新评审（删除 review.md 后执行 `/opsx:continue`）

- **决策**：<!-- PASS / PASS WITH CONDITIONS / REJECT -->
- **决策人**：<!-- Tech Leader 姓名 -->
- **决策日期**：<!-- YYYY-MM-DD -->
- **决策理由**：<!-- 综合交叉评审意见，简要说明同意/驳回的原因 -->
- **附加条件**：<!-- PASS WITH CONDITIONS 时必填，列出评审中需要后续闭环的事项（如补充方案分析、可信赖验证、友商调研等），可与 tasks 并行推进，须在归档前完成；PASS 时填"无" -->
