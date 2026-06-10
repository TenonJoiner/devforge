---
name: devforge-lint-check
description: 编译检查与静态分析——零 warning 验证 + 多语言静态分析工具链，按项目配置自动探测
allowed-tools: [Read, Bash, Grep, Glob, Edit]
parameters:
  - name: autofix
    description: 检测后自动修复问题（默认只检测不修复）
    required: false
    default: false
---

# devforge-lint-check — 编译检查与静态分析

## 概述

编译通过（零 warning）→ 静态分析（深层缺陷检测）。两层防护，提前拦截问题。

**技能边界**：默认只检测不修复，输出检查报告后结束；带 `autofix` 参数时，发现问题后自动派遣 developer 修复并回归检查，最多 5 轮。

## 启动检测

读取当前 git 状态判定检查范围：

```
git diff --name-only HEAD
  ├─ 有输出 → 增量（未提交变更）
  └─ 无输出 → 分支全量（feature 分支相对于 main 的变更）
```

由 `/df:lint` 参数覆盖上述自动判定（`--full` 强制分支全量、`<target>` 指定目标）。

## 执行范围

### 手动执行

默认根据当前 git 状态自动判定：

```
git diff --name-only HEAD
  ├─ 有输出（工作区存在未提交变更）→ 增量
  └─ 无输出（工作区干净）          → 分支全量
```

| 范围 | 检查内容 |
|------|---------|
| **增量** | 工作区中已修改但未提交的文件 |
| **分支全量** | 当前 feature 分支相对于 main 的所有变更文件 |

显式参数覆盖（跳过自动判定）：
- `--full` → 强制分支全量（feature 分支相对于 main 的所有变更文件）。⚠ 不是"全项目"——只检查当前分支引入的变更。
- `<file-or-dir>` → 只检查指定目标

### Workflow 执行

由 tasks.md 中的阶段定义直接指定范围，不依赖 git 状态自动判定：

| 阶段 | 范围 | 调用方式 | 说明 |
|------|------|---------|------|
| Requirement LINT（tasks.md 1.3 / 2.2） | 增量 | `/df:lint` | 开发中，工作区通常有未提交变更 |
| QA FULL-LINT（tasks.md QA.1） | **分支全量** | `/df:lint --full` | **必须显式指定** |
| pre-commit | 增量 | `/df:lint` | H1 hook 自动调用 |

**范围铁律**：
- L1 编译始终由构建系统自然处理，不做人为文件过滤
- L2 静态分析严格按指定范围执行，只分析范围内的源文件
- 头文件变更时，应确保其影响被静态分析工具捕获（如 C/C++ 的 `clang-tidy --header-filter` 等语言特定机制）

## 执行流程

### `autofix` 未设置（默认）— 只检测

1. **执行 L1 编译检查**
   - 通过 → 进入步骤 2
   - 失败（存在 error/warning）→ 输出问题清单，结束
2. **执行 L2 静态分析**（L2a Type Check + L2b Lint）
   - 通过 → 输出通过报告，结束
   - 发现问题 → 输出问题清单，结束

### `autofix` 已设置 — 检测 + 自动修复

```
执行检查 → 发现问题 → 派遣 developer 修复 → 再次检查 → ... → 全部通过
```

1. **执行 L1 编译检查**
   - 通过 → 进入步骤 2
   - 失败（存在 error/warning）→ 进入步骤 4
2. **执行 L2 静态分析**（L2a Type Check + L2b Lint）
   - 通过 → 结束，输出通过报告
   - 发现问题 → 进入步骤 4
3. **结束**，输出通过报告
4. **派遣修复**
   - 激活 `developer` Agent
   - 传入问题详情（文件、行号、错误类型、建议修复）
   - developer 修复后，回到步骤 1（最多 5 轮，超过需人工介入）

## 检查层级

### L1：编译检查（零 warning 验证）

**目标**：编译通过且 zero warning。

**为什么需要编译检查**：
1. 编译器警告能发现大量实际问题（未使用变量、隐式转换、类型不匹配等）
2. C/C++ 的 `clang-tidy` 需要 `compile_commands.json`，而生成它需要项目能编译——L1 是 L2 的**前置条件**
3. 但 lint 的编译检查**不是替代构建系统**，而是验证编译输出零 warning

**步骤**：

1. **获取构建命令**
   - 先查 `CLAUDE.md` 中是否已记录构建命令（搜索 BUILD_COMMAND、编译、构建等关键词）
   - 若无，按以下优先级探测构建系统文件，生成候选命令：
     `Cargo.toml` → `cargo build` | `go.mod` → `go build`
     `build.sh` → `./build.sh` | `CMakeLists.txt` → `cmake --build build`
     `Makefile` → `make` | `pyproject.toml` / `setup.py` → 按需
     `package.json` → `npm run build` / `pnpm build`
     `pom.xml` → `mvn compile` | `build.gradle` → `gradle build`
   - **向用户确认**候选命令（是否需要额外参数、指定目录等）
   - 确认后 **记录到 CLAUDE.md**，后续直接使用

2. **执行构建**
   - 运行确认后的构建命令，捕获完整输出

3. **处理结果**

   | 结果 | 处理 |
   |------|------|
   | 存在 error | 停止，派遣 developer 修复 |
   | 存在 warning | 返回 developer 修复（通常在 `/df:tdd` GREEN 阶段就应消除） |
   | 零 error、零 warning | 通过，进入 L2 |

**C/C++ 特有：compile_commands.json**

`clang-tidy` / `cppcheck` 依赖此文件解析头文件路径和宏定义。**L1 构建时必须同步确保此文件存在**。

| 场景 | 操作 |
|------|------|
| 已存在 | 直接使用，进入 L2 |
| CMake 项目 | L1 构建命令追加 `-DCMAKE_EXPORT_COMPILE_COMMANDS=ON`，构建完成后检查是否生成 |
| Makefile 项目 | L1 构建命令改用 `bear -- make`（需提前检测 bear 是否安装，未安装则提示安装） |
| 生成失败 | L2 降级：仅分析变更的 `.c`/`.cpp` 源文件，跳过头文件影响分析（准确率降低，需人工复核） |

### L2：静态分析

**目标**：捕获编译器未发现的深层缺陷和代码规范问题。

**工具链探测**（按项目配置文件自动选择）：

| 语言 | 探测信号 | 类型检查 | 静态分析 |
|------|---------|---------|---------|
| C/C++ | `.clang-tidy` / `compile_commands.json` | 编译器内置（L1） | `clang-tidy` + `cppcheck` |
| Rust | `Cargo.toml` | 编译器内置（L1） | `clippy` |
| Go | `go.mod` / `.golangci.yml` | 编译器内置（L1） | `golangci-lint` / `go vet` |
| Python | `pyproject.toml` / `mypy.ini` | `mypy` / `pyright` | `ruff check` / `pylint` |
| JS/TS | `package.json` / `tsconfig.json` | `tsc --noEmit` | `biome check` / `eslint` |

**执行顺序（L2 内部）**：

1. **L2a Type Check**（仅对需要显式类型检查的语言）：
   - Python: `mypy .` 或 `pyright`
   - JS/TS: `tsc --noEmit`（需要 `tsconfig.json`）
   - C/C++/Rust/Go: 编译器已覆盖，跳过

2. **L2b Lint / 静态分析**：
   - 按语言调用对应工具（见上表）

**配置文件策略**：
- **存在项目配置**（如 `.clang-tidy`、`.golangci.yml`）→ 尊重并使用该配置
- **不存在项目配置** → 使用工具默认规则继续执行，但输出中**强制标注降级状态**（作为输出总结的一部分，不可忽略）：
  > ⚠ 项目未配置 `<config-file>`，L2 使用工具默认规则，部分检查项可能未覆盖。建议落地项目创建对应配置文件（如 `.clang-tidy`、`.golangci.yml` 等）。

**Type Check 执行示例**：

```bash
# Python
mypy --strict src/          # 或 pyright

# TypeScript
tsc --noEmit                # 需要 tsconfig.json
# JavaScript（带 // @ts-check）
tsc --noEmit --allowJs --checkJs
```

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

## 问题路由

### `autofix` 未设置（默认）— 只检测

所有问题输出到问题清单，不执行修复。

### `autofix` 已设置 — 检测 + 自动修复

所有问题统一处理：派遣 developer 修复 → 回归检查。

| 问题类型 | 处理方式 |
|---------|---------|
| 编译 error | 派遣 developer 修复，修复后回归 |
| 编译 warning | 派遣 developer 修复，修复后回归 |
| 静态分析 error | 派遣 developer 修复，修复后回归 |
| 静态分析 warning | 派遣 developer 修复，修复后回归 |

**修复循环上限**：自动修复最多 5 轮，超过仍未通过需人工介入。

**关于 suppress**：若某条规则对项目不适用，通过修改配置文件（如 `.clang-tidy`）suppress，该变更作为正常代码修改参与 lint。

## 文档写入铁律

本 skill 不产出独立文件。但以下变更必须写入持久化位置：

- **构建命令确认后**：记录到 `CLAUDE.md`（搜索关键词：`BUILD_COMMAND`、`编译`、`构建`）
- **降级标注**：无项目配置时使用工具默认规则，在输出总结中强制标注 ⚠ 降级状态
- 每轮执行记录：问题类型、文件、行号、修复建议，在对话中逐轮输出

## 出口标准

### `autofix` 未设置（默认）— 只检测

- 检查完成即输出报告，无论是否通过
- 报告包含所有发现的问题（文件、行号、错误类型）

### `autofix` 已设置 — 检测 + 自动修复

检查通过必须同时满足：

- [ ] L1 编译零 error、零 warning
- [ ] L2 静态分析零 error（warning 按问题路由处理）
- [ ] 修复循环不超过 5 轮
- [ ] 所有修复经回归验证通过

**自动推进**：全部满足 → 输出通过报告 → 结束。
**等待人工决策**：5 轮后仍未通过 → 输出当前问题清单 → 等待用户介入。

## 红旗清单

以下情况立即停止自动修复，等待人工决策：

| 红旗 | 触发条件 | 处理方式 |
|------|---------|---------|
| 🚩 修复死循环 | 5 轮修复后仍有 error/warning | 停止，输出完整问题清单 |
| 🚩 构建系统未知 | CLAUDE.md 无记录 + 探测无结果 + 用户无法确认 | 停止，提示用户配置构建命令 |
| 🚩 C/C++ 编译数据库缺失 | `compile_commands.json` 生成失败 | L2 降级执行，强制标注准确率下降，建议人工复核 |
| 🚩 修复引入新问题 | developer 修复后 L1 出现新的编译 error | 继续修复循环（消耗轮次），若同时触发 5 轮上限则停止 |

## Integration

- **执行时机**：
  - 高频：单个 task 完成后的最终检查（在 git commit 前）— 自动带 `autofix`
  - 中频：LINT/QA 阶段、archive 前 — 自动带 `autofix`
  - 自动：H1 pre-commit-lint 拦截存在严重问题的提交 — 自动带 `autofix`
  - 手动：`/df:lint`（只检测）或 `/df:lint autofix`（检测+修复）
- **问题修复方**：developer（A2）自动修复并回归检查（仅 `autofix` 模式），最多 5 轮
