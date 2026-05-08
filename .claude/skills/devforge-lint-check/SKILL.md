---
name: devforge-lint-check
description: 编译检查与静态分析——零 warning 验证 + 多语言静态分析工具链，按项目配置自动探测
allowed-tools: [Read, Bash, Grep, Glob]
---

# devforge-lint-check — 编译检查与静态分析

## 概述

编译通过（零 warning）→ 静态分析（深层缺陷检测）。两层防护，提前拦截问题。

**技能边界**：本 skill 仅执行检测并输出报告，不自动修改代码。

**职责划分**：
- **lint skill（本文件）**：编译检查 + 静态分析
- **测试验证级**：内存检测（valgrind/asan）、并发检测（tsan/helgrind）——需要编译 + 运行测试二进制，属于动态分析，不在 lint 中执行

## 何时使用

- 编写或修改代码后快速验证（fast 模式）
- 提交前最终检查（fast 模式）
- `/df:tdd` 后的补充验证（fast 模式）
- 特性级 archive 前或 QA 阶段质量收尾

## 检查层级

### L1：编译检查（零 warning 验证）

**目标**：编译通过且 zero warning。

**为什么需要编译检查**：
1. 编译器警告能发现大量实际问题（未使用变量、隐式转换、类型不匹配等）
2. C/C++ 的 `clang-tidy` 需要 `compile_commands.json`，而生成它需要项目能编译——L1 是 L2 的**前置条件**
3. 但 lint 的编译检查**不是替代构建系统**，而是验证编译输出零 warning

**执行策略**：

1. **探测构建系统**（按优先级）：
   - `Makefile` → `make`
   - `CMakeLists.txt` → `cmake --build build`
   - `build.sh` → `./build.sh`
   - `Cargo.toml` → `cargo build`
   - `go.mod` → `go build`
   - `pyproject.toml` / `setup.py` → 按需

2. **检查结果**：提取输出中的 `error:` 和 `warning:` 数量，确保 warning 为 0

3. **compile_commands.json**（C/C++ 特有）：
   - 检查项目根目录或 `build/` 目录下是否存在
   - 若不存在且项目使用 CMake，建议运行 `cmake -DCMAKE_EXPORT_COMPILE_COMMANDS=ON ...`
   - `clang-tidy` / `cppcheck` 依赖此文件解析头文件路径和宏定义

### L2：静态分析

**目标**：捕获编译器未发现的深层缺陷和代码规范问题。

**工具链探测**（按项目配置文件自动选择）：

| 语言 | 探测信号 | 静态分析工具 | 说明 |
|------|---------|------------|------|
| C/C++ | `.clang-tidy` / `compile_commands.json` | `clang-tidy` + `cppcheck` | 两者互补，clang-tidy 偏 AST 分析，cppcheck 偏数据流分析 |
| Rust | `Cargo.toml` | `clippy` | 官方 linter，需要 `cargo clippy` |
| Go | `go.mod` / `.golangci.yml` | `golangci-lint` | 集成多个 linter |
| Python | `pyproject.toml` / `.pylintrc` | `ruff check` / `pylint` | ruff 速度优先，pylint 深度优先 |
| JS/TS | `package.json` / `biome.json` / `.eslintrc*` | `biome check` / `eslint` | biome 为 format+lint 二合一 |

**配置文件策略**：
- **存在项目配置**（如 `.clang-tidy`、`.golangci.yml`）→ 尊重并使用该配置
- **不存在项目配置** → 提示用户创建，给出推荐模板（参考 `.claude/rules/coding-style-<lang>.md`）

**cppcheck 执行参数（C/C++）**：
```bash
# 基础检查
# 启用所有检查类别，抑制系统头文件缺失警告
# 需要 compile_commands.json 以正确解析包含路径
cppcheck --enable=all --suppress=missingIncludeSystem \
  --project=compile_commands.json \
  --error-exitcode=1 \
  .
```

**clang-tidy 与 cppcheck 互补性**：

| 工具 | 擅长发现 | 不擅长 |
|------|---------|--------|
| clang-tidy | 现代 C++ 风格、API 误用、性能优化建议、可读性问题 | 跨函数数据流分析、资源泄漏路径 |
| cppcheck | 空指针解引用、缓冲区溢出、资源泄漏、死代码、整数溢出 | 代码风格、命名规范 |

## 输出格式

逐项输出通过/失败状态，简洁明了：

```
L1 编译检查
  ✓ make: 0 error, 0 warning
  ✓ compile_commands.json 已生成

L2 静态分析
  ✓ clang-tidy: 0 error, 1 warning (readability-identifier-naming)
  ✓ cppcheck: 0 error, 0 warning

总计: 0 error, 1 warning
```

**问题路由**：
- **编译 error** → 停止提交，developer 修复（通常在 `/df:tdd` GREEN 阶段就应消除）
- **编译 warning** → 返回 developer 修复
- **静态分析 error** → 返回 developer 修复；确认为误报的可经评估后在配置文件中 suppress
- **静态分析 warning** → 按严重程度处理，低优先级 warning 可记录待后续清理

## Integration

- **执行时机**：
  - 高频（fast 模式）：单个 task 完成后的最终检查（在 git commit 前）
  - 中频：`/opsx:apply` 的 LINT/QA 阶段、archive 前
  - 自动：H1 pre-commit-lint 拦截存在严重问题的提交
- **问题修复方**：developer（A2）在执行 lint 之前完成修复
- **相关 Rules**: `.claude/rules/coding-style.md`（通用）、`.claude/rules/coding-style-<lang>.md`（语言特定）
