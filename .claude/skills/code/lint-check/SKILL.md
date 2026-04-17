---
name: code/lint-check
description: C 项目静态检查与内存安全检测——编译 + clang-tidy + valgrind
version: 1.0.0
allowed-tools: [Read, Bash, Grep, Glob]
---

# code/lint-check — 编译检查与静态分析

## 概述

编译通过 → clang-tidy 检查 → valgrind 内存检测。三层防护，提前拦截问题。

**技能边界**：本 skill 仅执行检测并输出报告，不自动修改代码。

## 何时使用

- 编写或修改 C 代码后（fast 模式）
- 提交前最终检查（fast 模式）
- `/ky:tdd` GREEN 后快速验证（fast 模式）
- 特性级 archive 前或 Q.1 质量收尾（`--full` 模式）

## 检查层级

### L1：编译检查

**目标**：零 warning，零 error。

**策略**：
1. **优先使用项目自身构建脚本**：检测是否存在 `Makefile`、`CMakeLists.txt`、`build.sh`、`meson.build`、`configure` 等，直接调用对应构建命令（如 `make`、`cmake --build build`、`./build.sh`）。
2. **检查结果**：提取输出中的 `error:` 和 `warning:` 数量，确保全部为 0。
3. **分布式存储强制编译选项**（如 `-Wformat=2`、`-fstack-protector-strong`）应直接维护在项目的构建脚本中（如 `CMakeLists.txt`），由本 skill 通过 `Read` 检查确认存在即可，不在命令行硬编码。

### L2：clang-tidy

**目标**：捕获潜在 bug 和代码规范问题。

**执行前前置条件检查**：

1. **`.clang-tidy` 配置文件**：
   - 检查项目根目录是否存在 `.clang-tidy`。
   - 若存在，尊重并使用该配置，不额外覆盖 `-checks`。
   - 若不存在，提示用户创建，并给出推荐内容：
     ```yaml
     Checks: "bugprone-*,cert-*,clang-analyzer-*,cppcoreguidelines-*,performance-*,portability-*,readability-*"
     ```

2. **`compile_commands.json`**：
   - clang-tidy 需要此文件才能正确解析头文件路径和宏定义。
   - 检查项目根目录或 `build/` 目录下是否存在 `compile_commands.json`。
   - **若不存在**，停止 clang-tidy 检查并输出提示及生成命令：

     提示文本示例（输出给用户）：
     ```
     [WARNING] 未检测到 compile_commands.json，clang-tidy 无法准确分析头文件依赖和宏定义。

     生成方式（按构建系统选择）：
     - CMake：-DCMAKE_EXPORT_COMPILE_COMMANDS=ON
     - Makefile 项目：先安装 bear，然后 bear -- make clean && bear -- make
     - Meson：编译时自动生成，通常位于 builddir/compile_commands.json
     ```

**运行命令**（具备上述条件后）：
```bash
clang-tidy <sources>
```

**关键规则说明**：
- bugprone-*：悬垂指针、资源泄漏、错误使用 API
- cert-*：安全编码标准
- clang-analyzer-*：静态分析器深度检查（内存、死锁、空指针）
- cppcoreguidelines-*：C++ 核心准则中适用于 C 的部分（如宏使用限制）

### L3：valgrind 内存检测

**目标**：运行测试二进制，检测内存错误和泄漏。

**前提**：必须通过项目构建脚本先生成测试可执行文件。

**执行步骤**：

1. 确认测试二进制已存在（如 build/test_<module> 或 `./run-tests.sh ut` 生成的产物）。
2. 对测试二进制运行：
```bash
valgrind --leak-check=full --error-exitcode=1 ./<test-binary>
```
3. 若项目使用 ctest，可建议：
```bash
ctest -D ExperimentalMemCheck
```

## 输出解读与问题路由

**lint-check 的职责是验证而非修复**。它期望 0 错误，因为此时代码应已在 `/ky:tdd`、refactor 和 review 阶段被 developer 修复完毕。

若发现问题：
- **编译错误** → 停止提交，返回 developer 修复（通常在 /ky:tdd GREEN 就应消除）
- **clang-tidy 告警** → 返回 developer 修复；确认为误报的可经评估后在 .clang-tidy 中 suppress
- **valgrind 内存错误** → 返回 developer 修复，通常需在 TDD 中补充测试复现后再修复

## Integration

- **前置 Command**: /ky:tdd 或 /ky:refactor
- **执行时机**：
  - 高频（fast 模式）：单个 task 完成后的最终检查（在 git commit 前）
  - 中频（`--full` 模式）：/opsx:apply 的 Q.1 质量收尾阶段、archive 前
  - 自动：H1 pre-commit-lint 拦截存在严重问题的提交
- **问题修复方**：developer（A2）在执行 lint 之前完成修复
- **相关 Rules**: R3 coding-style
