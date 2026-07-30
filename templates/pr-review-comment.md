---
template-for: PR/MR CI 评论正文（devforge-pr-review skill 第 5 阶段使用）
mandatory-sections:
  - MR 标题
  - 变更统计表格
  - 评审结论
  - 问题计数表
  - 代码评审折叠块（分支 A 必填，分支 B 省略）
  - 日志审计折叠块（分支 A 必填，分支 B 省略）
optional-sections: []
checklist-at-end: true
---

## MR 评审报告：<MR 标题>

本次 MR 变更统计如下：

| 分类 | 文件数 | 新增行数 | 删除行数 |
|---|---|---|---|
| 代码 | <Nc> | +<Xc> | -<Yc> |
| 文档 | <Nd> | +<Xd> | -<Yd> |
| 其他 | <No> | +<Xo> | -<Yo> |
| **总计** | **<N>** | **+<X>** | **-<Y>** |

**评审结论：** <APPROVE / COMMENT / REQUEST_CHANGES>

| 级别 | 数量 | 语义 |
|---|---|---|
| CRITICAL | <N_critical> | 阻塞合并 |
| HIGH | <N_high> | 强烈建议修改 |
| MEDIUM | <N_medium> | 优化建议 |
| LOW | <N_low> | 轻微问题 / 变体分析 |

<details>
<summary>展开查看代码评审报告</summary>

<代码评审报告完整内容，原样粘贴，禁止概括/删减/改写>

</details>

<details>
<summary>展开查看日志审计报告</summary>

<日志审计报告完整内容，原样粘贴，禁止概括/删减/改写>

</details>

---

> **严格约束**：
> 1. 外层摘要只展示数量，不展示任何具体问题的标题、文件位置或描述
> 2. 完整报告的问题详情必须放在 `<details>`/`<summary>` 折叠块内
> 3. 中间报告内容原样粘贴进折叠块，禁止重新概括、删减、改写、只摘录部分
> 4. 禁止把 CRITICAL/HIGH 的具体发现提到外层的"阻塞项""强烈建议"等段落
> 5. 若日志审计报告不存在，对应折叠块省略；代码评审折叠块始终存在（本 skill 调用方）

---

## 自检清单

生成评论正文文件后，必须逐项自检，全部通过才能发送：

- [ ] 文件开头是 `## MR 评审报告：` 标题（含 MR 标题文本，非占位符）
- [ ] 变更统计表格分类完整（代码/文档/其他），计数与实际一致
- [ ] 评审结论为 APPROVE / COMMENT / REQUEST_CHANGES 三者之一
- [ ] 问题计数表各级别数量与折叠块内报告摘要一致
- [ ] 所有问题详情在 `<details>` 折叠块内，外层无泄露的具体发现
- [ ] 每个折叠块以 `<details>` 开始、`</details>` 结束，标签完整闭合
- [ ] 折叠块内容与对应的中间报告文件（`/tmp/pr-review-report-*.md`、`/tmp/log-audit-*.md`）内容一致，未被改写
