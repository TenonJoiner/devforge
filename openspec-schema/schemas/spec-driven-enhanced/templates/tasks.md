## 1. <!-- Requirement 名称 -->

**Parallel**: <!-- independent / depends-on:X.Y，仅在任务组粒度标注 -->
**Component**: <!-- 组件名，多仓场景使用；单仓可省略 -->

<!-- 多仓场景：若同一 Requirement 跨多个仓库，按仓库拆分子组，如 ### 1a. storage 侧 / ### 1b. meta 侧 -->

- [ ] 1.1 SCENARIO: <!-- Scenario 描述 --> [repo: <!-- 目标仓库名，多仓场景使用；单仓可省略 -->]
  <!-- 测试文件路径、测试函数名、源文件路径、函数签名、关键逻辑 -->
- [ ] 1.2 SCENARIO: <!-- Scenario 描述（异常路径） --> [repo: <!-- 目标仓库名，多仓场景使用；单仓可省略 -->]
  <!-- 异常路径测试文件路径、测试函数名、源文件路径、函数签名 -->
- [ ] 1.3 REVIEW: 调用 devforge-code-review autofix 评审并修复 CRITICAL/HIGH

## 2. <!-- Requirement 名称 -->

**Parallel**: <!-- independent / depends-on:X.Y -->
**Component**: <!-- 组件名，多仓场景使用；单仓可省略 -->

- [ ] 2.1 SCENARIO: <!-- Scenario 描述 --> [repo: <!-- 目标仓库名，多仓场景使用；单仓可省略 -->]
  <!-- 测试文件路径、测试函数名、源文件路径、函数签名、关键逻辑 -->
- [ ] 2.2 REVIEW: 调用 devforge-code-review autofix 评审并修复 CRITICAL/HIGH

## QA. 质量保障

- [ ] QA.1 FULL-LINT: 调用 devforge-lint-check autofix 全量编译检查与静态分析，修复所有 error/warning
- [ ] QA.2 FULL-REVIEW: 调用 devforge-code-review autofix --full 全量评审并修复 CRITICAL/HIGH
- [ ] QA.3 DEEP-REFACTOR: 调用 devforge-simplify 深度简化重构
- [ ] QA.4 UNIT-COVERAGE: 重新执行单元测试，验收覆盖率达标
- [ ] QA.5 INTEGRATION-TEST: 开发 feature 级别集成测试用例，运行并验证通过

<!-- 多仓场景追加（单仓不生成）：
- [ ] QA.6 CROSS-REPO-INTEGRATION: 触发跨仓库集成测试或最小端到端验证，确保各仓库变更协同工作
- [ ] QA.7 CROSS-REPO-COMMIT-ORDER: 确认各仓库 commit 顺序与接口契约匹配，避免部分提交导致中间状态不可用
-->
