---
name: devforge-lint-check
description: 静态检查与代码质量检测——编译 + 静态分析 + 内存/并发检测，根据 domain-config.yaml 自动适配语言和工具链
allowed-tools: [Read, Bash, Grep, Glob]
---

# devforge-lint-check — 编译检查与静态分析

## 概述

编译通过 → 静态分析 → 内存/并发检测。三层防护，提前拦截问题。

**技能边界**：本 skill 仅执行检测并输出报告，不自动修改代码。

**语言适配**：根据 `.claude/domain-config.yaml` 中的 `languages.primary` 自动选择对应的工具链。

## 何时使用

- 编写或修改 C 代码后（fast 模式）
- 提交前最终检查（fast 模式）
- 代码变更后快速验证（fast 模式）
- 特性级 archive 前或 Q.1 质量收尾（`--full` 模式）

## 检查层级

### L1：编译检查

**目标**：零 warning，零 error。

**策略**：
1. **优先使用项目自身构建脚本**：检测是否存在 `Makefile`、`CMakeLists.txt`、`build.sh`、`meson.build`、`Cargo.toml`、`go.mod` 等，直接调用对应构建命令。
2. **检查结果**：提取输出中的 `error:` 和 `warning:` 数量，确保全部为 0。
3. **编译选项**：强制编译选项（如 C/C++ 的 `-Wformat=2`、`-fstack-protector-strong`，Rust 的 `#![deny(warnings)]`）应直接维护在项目的构建脚本中，由本 skill 通过 `Read` 检查确认存在即可，不在命令行硬编码。

### L2：静态分析

**目标**：捕获潜在 bug 和代码规范问题。

**工具选择**（根据 domain-config.yaml 的 languages.primary）：

| 语言 | 静态分析工具 | 配置文件 | 说明 |
|------|------------|---------|------|
| C/C++ | clang-tidy | .clang-tidy | 需要 compile_commands.json |
| Rust | clippy | clippy.toml | 官方 linter |
| Go | golangci-lint | .golangci.yml | 集成多个 linter |
| Python | pylint / flake8 | .pylintrc / .flake8 | 代码质量检查 |
| Java | SpotBugs / Checkstyle | spotbugs.xml / checkstyle.xml | 静态分析 |

**执行前前置条件检查**（以 C/C++ 为例）：

1. **配置文件**：
   - 检查项目根目录是否存在对���的配置文件（如 `.clang-tidy`）。
   - 若存在，尊重并使用该配置。
   - 若不存在，提示用户创建，并给出推荐内容。

2. **编译数据库**（C/C++ 特有）：
   - clang-tidy 需要 `compile_commands.json` 才能正确解析头文件路径和宏定义。
   - 检查项目根目录或 `build/` 目录下是否存在。
   - 若不存在，停止检查并输出生成命令提示。

**运行命令**：根据语言选择对应工具。

### L3：内存/并发检测

**目标**：运行测试二进制，检测内存错误、泄漏、数据竞争。

**工具选择**（根据 domain-config.yaml 的 languages.primary）：

| 语言 | 内存检查工具 | 并发检查工具 | 说明 |
|------|------------|------------|------|
| C/C++ | valgrind / AddressSanitizer | ThreadSanitizer / helgrind | 内存泄漏、越界访问、数据竞争 |
| Rust | miri | — | unsafe 代码检查（编译期已保证安全） |
| Go | — | race detector (`go test -race`) | 数据竞争检测 |
| Python | memory_profiler | — | 内存使用分析 |
| Java | VisualVM / JProfiler | — | 内存泄漏分析 |

**执行步骤**（以 C/C++ 为例）：

1. 确认测试二进制已存在。
2. 对测试二进制运行：
```bash
valgrind --leak-check=full --error-exitcode=1 ./<test-binary>
```
3. 若项目使用 ctest，可建议：
```bash
ctest -D ExperimentalMemCheck
```

## 输出解读与问题路由

**lint-check 的职责是验证而非修复**。它期望 0 错误，因为此时代码应已在编码和评审阶段被 developer 修复完毕。

若发现问题：
- **编译错误** → 停止提交，返回 developer 修复（通常在 /df:tdd GREEN 就应消除）
- **静态分析告警** → 返回 developer 修复；确认为误报的可经评估后在配置文件中 suppress
- **内存/并发错误** → 返回 developer 修复，通常需在 TDD 中补充测试复现后再修复

## Integration

- **执行时机**：
  - 高频（fast 模式）：单个 task 完成后的最终检查（在 git commit 前）
  - 中频（`--full` 模式）：/opsx:apply 的 Q.1 质量收尾阶段、archive 前
  - 自动：H1 pre-commit-lint 拦截存在严重问题的提交
- **问题修复方**：developer（A2）在执行 lint 之前完成修复
- **相关 Rules**: R3 coding-style（通用 + 语言特定）
