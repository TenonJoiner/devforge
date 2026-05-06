---
name: devforge-tdd-workflow
description: TDD 铁律开发工作流——RED-GREEN-REFACTOR，根据 domain-config.yaml 自动适配语言和测试框架
allowed-tools: [Read, Write, Edit, Bash, Grep, Glob]
---

# devforge-tdd-workflow — TDD 铁律开发工作流

## 概述

RED → GREEN → REFACTOR。没有先失败的测试，决不写生产代码。

**核心原则**：
- **测试先行**：每个功能增量必须有测试失败作为起点
- **最小步长**：每个步骤只解决当前测试失败，不超前实现
- **绿色保障**：REFACTOR 阶段必须保持测试常绿
- **内存安全**：proposal 收尾及 `/df:lint --full` 阶段集成 valgrind，确保无泄漏、无越界

## 何时使用

- 实现单个 OpenSpec task（尤其是 tasks.md 中的步骤 N.M）
- 为现有函数补充缺失单元测试
- 重构思路上需要测试保驾护航的代码修改

## 与 tasks.md 的映射

spec-driven-enhanced 的 tasks 模型采用 OpenSpec 两层结构 + TDD 步骤映射：

```
任务组层（## N. <Requirement>）：
├─ Scenario A 的实现：
│   ├─ - [ ] N.M  RED      → /df:tdd 的 RED 阶段（写失败测试 + 验证失败）
│   └─ - [ ] N.M' GREEN    → /df:tdd 的 GREEN 阶段（最小实现 + 验证通过）
├─ Scenario B 的实现：
│   ├─ - [ ] N.M'' RED
│   └─ - [ ] N.M''' GREEN
├─ - [ ] REFACTOR         → /df:refactor（积累 2-3 轮后做一次）
├─ - [ ] LINT             → /df:lint（任务组末尾质量闸口）
└─ - [ ] REVIEW           → /df:code-review（任务组末尾评审 + 修复）
```

**`/df:tdd` 的覆盖范围**：仅 RED 和 GREEN 两个步骤，对应单个 Scenario 的实现循环。

**REFACTOR / LINT / REVIEW 不在 `/df:tdd` 内**：
- REFACTOR 由 `/df:refactor` 独立 skill 处理（任务组中累积后做）
- LINT / REVIEW 由各自 skill 处理（任务组末尾固定追加，由 apply 阶段的 code-reviewer agent 评审 + developer agent 修复）

`/df:code-review` 输出评审报告后，由 developer agent 按 CRITICAL → HIGH 顺序修复，修复后必须通过回归测试。

## 核心流程

### 阶段 1：RED（写一个失败的测试）

**成功标准**：编译通过但测试失败（断言失败或预期错误）。

**步骤**：
1. 读取当前 task 的目标和 specs/design 约束
2. 确定本次要暴露的行为缺口
3. 在测试文件中编写最小测试用例
4. 运行测试，确认失败，记录失败信息

**语言特定测试建议**（根据 domain-config.yaml 的 languages.primary）：

**C/C++**：
- 使用 `cmocka` (C) 或 `gtest` (C++) 作为单元测试框架
- 测试文件命名：`tests/test_<module>_<scenario>.c`
- Mock 外部依赖时，优先使用链接期桩函数（link seam），避免侵入式宏修改

**Rust**：
- 使用内置 `#[test]` 和 `#[cfg(test)]`
- 测试文件命名：`tests/<module>_test.rs` 或模块内 `mod tests`
- Mock 使用 trait 抽象或 `mockall` crate

**Go**：
- 使用内置 `testing` 包
- 测试文件命名：`<module>_test.go`
- Mock 使用接口抽象或 `gomock`

**Python**：
- 使用 `pytest` 或 `unittest`
- 测试文件命名：`test_<module>.py`
- Mock 使用 `unittest.mock` 或 `pytest-mock`

**Java**：
- 使用 `JUnit`
- 测试文件命名：`<Module>Test.java`
- Mock 使用 `Mockito`

**红旗自查**：
- 测试一开始就通过了（说明测试没测到目标行为）
- 测试写了太多断言（应只有一个核心断言暴露缺口）
- 直接复制了生产代码到测试里（测试成了实现的影子）

### 阶段 2：GREEN（用最快速度让测试通过）

**成功标准**：所有测试通过（返回码 0）。

**步骤**：
1. 写最小量生产代码使测试通过
2. 运行测试确认通过

**阶段性容忍（必须在 REFACTOR 阶段清理）**：
- 直接返回硬编码值
- 复制粘贴重复逻辑
- 用最直白的方式实现条件分支

**边界说明**：
这些临时写法仅在当前测试与下一次 REFACTOR 之间短暂存在，**不得在未重构的情况下直接提交**。如果因为时间或其他原因跳过 REFACTOR，这些临时代码必须被标记为 TODO/FIXME 并在后续 task 中清理。

**禁止的操作**：
- 提前实现未被测试覆盖的行为
- 引入复杂抽象（提前设计）
- 优化性能（留在 REFACTOR 阶段）
- 以"GREEN 允许丑代码"为借口跳过 REFACTOR

### 阶段 3：REFACTOR（调用 `/df:refactor` 简化重构）

**成功标准**：测试保持绿色，代码质量提升。

**步骤**：
1. 识别代码异味：重复、过长函数、魔法数字、不清晰命名
2. 执行安全重构（提取函数、重命名变量、消除重复）
3. 运行测试确认绿色
4. 如需进一步简化，调用 `/df:refactor`

**REFACTOR 期间必须检查**：
- [ ] 所有测试通过
- [ ] 圈复杂度未显著上升
- [ ] 每个 C 函数返回值都被检查

> valgrind 内存检测留在 proposal 收尾或 `/df:lint --full` 阶段执行，不阻塞 TDD 小步循环。

## 铁律检查

```
NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST
```

## 常见借口与回应

| 借口 | 回应 |
|------|------|
| "测试框架还没搭好" | 先花 10 分钟写一个最小可运行的 `main.c` 测试桩 |
| "这太简单了，边写边测就行" | 简单代码也请写至少一个边界测试 |
| "TDD 不适合系统编程语言" | 这是本团队的工作方式，各语言都有成熟的测试框架和工具链 |

## 输出位置

- 测试文件：`tests/test_<module>_<scenario>.c`
- 生产代码：对应 task 指定的源文件
- 运行日志：终端输出或 `build/test-logs/`

## Integration

- **前置 Command**: `/opsx:apply`（提供当前 task 上下文）
- **后续 Command**: `/df:refactor`（GREEN 后的代码简化）
- **相关 Rules**: R3 `coding-style`, R4 `testing`
