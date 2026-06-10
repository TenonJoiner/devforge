## 1. <!-- Requirement 名称 -->

**Parallel**: <!-- independent / depends-on:X.Y，仅在任务组粒度标注 -->

- [ ] 1.1 SCENARIO: <!-- Scenario 描述 -->
  <!-- 测试文件路径、测试函数名、源文件路径、函数签名、关键逻辑 -->
- [ ] 1.2 SCENARIO: <!-- Scenario 描述（异常路径） -->
  <!-- 异常路径测试文件路径、测试函数名、源文件路径、函数签名 -->
- [ ] 1.3 LINT: 调用 /df:lint autofix 检查变更文件，修复编译错误和静态分析问题
- [ ] 1.4 REVIEW: 调用 /df:code-review autofix 评审并修复 CRITICAL/HIGH

## 2. <!-- Requirement 名称 -->

**Parallel**: <!-- independent / depends-on:X.Y -->

- [ ] 2.1 SCENARIO: <!-- Scenario 描述 -->
  <!-- 测试文件路径、测试函数名、源文件路径、函数签名、关键逻辑 -->
- [ ] 2.2 LINT: 调用 /df:lint autofix 检查变更文件，修复编译错误和静态分析问题
- [ ] 2.3 REVIEW: 调用 /df:code-review autofix 评审并修复 CRITICAL/HIGH

## QA. 质量保障

- [ ] QA.1 FULL-LINT: 调用 /df:lint autofix 全量检查（编译 + 静态分析），修复所有 error/warning
- [ ] QA.2 FULL-REVIEW: 调用 /df:code-review autofix 全量评审并修复 CRITICAL/HIGH
- [ ] QA.3 DEEP-REFACTOR: 调用 /df:simplify 深度简化重构
- [ ] QA.4 UNIT-COVERAGE: 重新执行单元测试，验收覆盖率达标
- [ ] QA.5 INTEGRATION-TEST: 开发 feature 级别集成测试用例，运行并验证通过
