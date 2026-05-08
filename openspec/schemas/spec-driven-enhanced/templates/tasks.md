## 任务粒度原则

每个 `- [ ]` 对应一个 **Scenario 级别的任务**，由 `/df:tdd` 完成实现。

- **Scenario 应足够小**：一个 Scenario 只描述一个具体的、可验证的行为。小到一次 `/df:tdd` 调用可在几分钟到十几分钟内完成。
- **异常路径独立成任务**：正常路径和异常路径各自是独立的 Scenario，各自对应独立的 checkbox。
- **拆细信号**：如果一个 Scenario 的描述中包含"和"、"同时"、"然后"等连接词，或 WHEN/THEN 涉及多个不相关的动作，说明该 Scenario 定义过粗，应在 specs 层面拆分为多个更细的 Scenario。

## 1. <!-- Requirement 名称 -->

**Parallel**：<!-- independent / depends-on:X.Y，仅在任务组粒度标注 -->

- [ ] 1.1 <!-- Scenario A 标识 -->: RED → GREEN → REFACTOR
  <!-- 测试文件路径、测试函数名、源文件路径、函数签名、关键逻辑 -->
- [ ] 1.2 <!-- Scenario B（异常路径）标识 -->: RED → GREEN → REFACTOR
  <!-- 异常路径测试文件路径、测试函数名、源文件路径、函数签名 -->
- [ ] 1.3 LINT: 调用 /df:lint 检查变更文件，修复编译错误和静态分析问题
- [ ] 1.4 REVIEW: 调用 /df:code-review 评审并修复 CRITICAL/HIGH

## 2. <!-- Requirement 名称 -->

**Parallel**：<!-- independent / depends-on:X.Y -->

- [ ] 2.1 <!-- Scenario 标识 -->: RED → GREEN → REFACTOR
  <!-- 测试文件路径、测试函数名、源文件路径、函数签名、关键逻辑 -->
- [ ] 2.2 LINT: 调用 /df:lint 检查变更文件，修复编译错误和静态分析问题
- [ ] 2.3 REVIEW: 调用 /df:code-review 评审并修复 CRITICAL/HIGH

## QA. 质量保障

- [ ] QA.1 FULL-LINT: 调用 /df:lint 全量检查（编译 + 静态分析），修复所有 error/warning
- [ ] QA.2 FULL-REVIEW: 调用 /df:code-review 全量评审并修复 CRITICAL/HIGH
- [ ] QA.3 DEEP-REFACTOR: 调用 /df:simplify 深度简化重构
- [ ] QA.4 UNIT-COVERAGE: 重新执行单元测试，验收覆盖率达标
- [ ] QA.5 INTEGRATION-TEST: 开发 feature 级别集成测试用例，运行并验证通过
- [ ] QA.6 MEMORY-CHECK: 调用 valgrind / AddressSanitizer 执行内存检测（动态分析，需编译运行）
