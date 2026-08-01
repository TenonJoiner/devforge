---
name: devforge-lint-check
description: 编译检查与 Lint 分析——零 warning 验证，支持本地开发和 CI 两种模式
allowed-tools: [Read, Bash, Grep, Glob, Edit]
parameters:
  - name: autofix
    description: 检测后自动修复问题（默认只检测不修复）
    required: false
    default: false
  - name: diff-range
    description: 显式指定 git diff 范围（CI 模式由外部调用方注入），优先级高于本地开发模式
    required: false
---

# devforge-lint-check — 编译检查与 Lint 分析

## 概述

编译通过（零 warning）→ Lint 分析（工具化静态检查）。两层防护，提前拦截问题。

本 skill 是项目 lint 脚本的调度器——**不自行拼凑 lint 参数，不根据 git diff 自行筛选文件**。具体查什么、怎么查由项目自己的构建/lint 脚本决定，skill 只负责根据当前模式选择调用哪条命令。

默认只检测并输出报告。带 `autofix` 参数时自动派遣 developer 修复并回归检查，最多 5 轮。

## 模式

两种模式决定 L1/L2 命令的选择偏好。具体命令始终从项目上下文中发现，**参数不绑死**。

| 模式 | 触发 | 语义 | 命令发现偏好 |
|------|------|------|-------------|
| 本地开发（默认） | `/df:lint` | 本地分支相对主干的差异代码 | 优先查找增量检查命令（如 `make lint-changed`、pre-commit hook 脚本）；若无则回退到全量命令 |
| CI | `/df:lint --diff-range <range>` | CI 流水线对比 MR 两个分支差异 | 优先查找 CI 脚本（如 `ci/lint.sh`、`make lint-ci`）；若无则回退到全量命令 |

**diff-range 优先级**：
1. `diff-range` 参数存在（CI 模式）：直接使用，透传给项目脚本
2. 都不传（默认，本地开发）：自动检测 trunk 后计算 `git diff $(git merge-base HEAD <trunk>)..HEAD`。trunk 检测失败时提示用户显式指定 `--diff-range`

## 职责边界

- ✅ Lint 工具执行 + 告警分类（误报/有意为之/历史遗留/需修复）
- ✅ `autofix` 模式下派遣 developer 修复需修复项
- ❌ 不做深度代码审查（语义 bug、架构问题、设计缺陷）→ 归属 `/df:code-review`
- ❌ 不引入 Skill 未定义的检查工具或步骤
- ❌ Lint 零告警时直接通过，不扩展检查范围
- ❌ 禁止使用 `which <tool>` 发现 Skill 未定义的检查工具并自行拼凑命令
- ❌ 禁止根据 git diff 自行筛选文件或拼凑 lint 参数——范围控制由项目脚本负责
- ✅ 允许使用 `which <tool>` 检查已确认的 lint 脚本所需的运行时工具是否可用

## L1：编译检查

1. **获取构建命令**（模式感知）
   - 在当前会话上下文中查找已知的构建方法（CLAUDE.md、README、项目 rules、先前对话等）
   - 根据当前模式选择偏好：
     - **本地开发模式**：优先查找增量构建命令（如 `make build-changed`、`make build-debug`），若无则回退到全量构建
     - **CI 模式**：优先查找 CI 构建脚本（如 `ci/build.sh`、`make build-ci`），若无则回退到全量构建
   - 若未找到，探测项目中存在的构建系统文件（Makefile、`build.sh`、`CMakeLists.txt`、`go.mod`、`package.json` 等）。项目可能包含多语言/多模块，逐一列出所有探测到的构建命令
   - 自行探测结果需**向用户确认**后再使用。确认后将命令写入 `.claude/rules/building.md`（不存在则创建），需同时记录模式映射。后续直接从该文件读取
       - **阻断规则**：若构建命令来自自行探测且未经用户确认，禁止进入步骤 2。必须使用 `AskUserQuestion` 向用户确认后方可继续
       - 禁止根据变更文件（`git diff`、`git log` 输出）自行推断或拼凑构建命令

2. **逐一执行所有构建命令**，分别捕获完整输出
       - 必须原样执行步骤 1 确定的构建命令，禁止根据变更文件类型自行判断跳过、缩减或替换构建命令
       - 禁止在此步骤执行 `git diff`、`git log` 等变更范围分析——L1 的职责是执行构建，不是判断是否需要构建
       - 构建命令的执行范围由 Skill 使用者（通过上下文配置或确认）决定，不由 agent 决定

3. **处理结果**

   | 结果 | `autofix` 未设置 | `autofix` 已设置 |
   |------|-----------------|-------------------|
   | 零 error、零 warning | 通过，进入 L2 | 通过，进入 L2 |
   | 存在 error 或 warning | 输出错误/警告清单，结束 | 派遣 developer 修复，修复后回归编译验证，最多 5 轮 |

## L2：Lint 分析

1. **获取 Lint 命令**（模式感知）
   - 在当前会话上下文中查找已知的 lint 方法（CLAUDE.md、README、项目 rules、先前对话等）
   - 根据当前模式选择偏好：
     - **本地开发模式**：优先查找增量 lint 命令（如 `make lint-changed`、pre-commit hook 脚本、`golangci-lint run --new-from-rev=...` 对应的项目封装脚本），若无则回退到全量 lint
     - **CI 模式**：优先查找 CI lint 脚本（如 `ci/lint.sh`、`make lint-ci`），若无则回退到全量 lint
   - 若未找到，探测项目中存在的可执行 lint 脚本。项目可能包含多语言/多模块，逐一列出所有探测到的 lint 命令
   - 自行探测结果需**向用户确认**后再使用。确认后将命令写入 `.claude/rules/linting.md`（不存在则创建），需同时记录模式映射。后续直接从该文件读取
       - **阻断规则**：若 lint 命令来自自行探测且未经用户确认，禁止进入步骤 2。必须使用 `AskUserQuestion` 向用户确认后方可继续
       - 禁止根据变更文件（`git diff`、`git log` 输出）自行推断或拼凑 lint 命令

   **可执行 lint 脚本 vs 工具配置文件**：

   以下文件是工具规则配置，**不是**可执行 lint 脚本，禁止作为 lint 命令来源：
   - `.clang-tidy`、`.clang-format`
   - `.flake8`、`.pylintrc`、`pyproject.toml [tool.pylint]`
   - `.golangci.yml`
   - `.eslintrc.*`、`.prettierrc.*`

   仅以下类型可视为可执行 lint 脚本：
   - `Makefile` 的 `lint` / `check` target
   - `package.json` 的 `lint` / `check` script
   - 项目根目录或 `ci/`、`scripts/`、`utils/` 下的 `lint.sh`、`lint.py` 等独立脚本
   - `utils/githooks/` 下的 pre-commit hook 脚本

2. **逐一执行所有 Lint 命令**，分别捕获 stdout。若某个命令 stdout 为空，分析对应脚本找到输出重定向的目标文件并读取；仍无法获取则提示用户确认输出位置

   若某 lint 命令因**环境不可用**而失败（缺少依赖、工具未安装、容器镜像不可达等，非代码告警），记录原因后继续执行其余 lint 命令，不阻塞后续流程。

   **所有 lint 命令均零告警时，输出通过信息后结束，不进入步骤 3。**

3. **分析 Lint 报告**（仅部分 lint 命令存在告警时执行）

   **3a. 快速预分类**

   先对告警做快速预分类，满足以下条件之一可直接判定为误报，无需派遣 developer：
   - 告警工具与文件类型明确不匹配（如 clang-format 对非 C/C++/ObjC 文件）
   - 告警规则在项目配置文件中已显式 disable
   - 其他可通过简单规则匹配直接判定的场景

   预分类无法确定归属的告警，进入 3b。

   **3b. 派遣 developer 分析**

   将预分类后剩余的告警按文件分组：
   - 告警 ≤ 3 条且集中在 ≤ 2 个文件时：agent 自行分析（仅做分类判定，不做深度修复分析）
   - 超过上述阈值：派遣多个 developer 并行分析。禁止派遣 code-reviewer 或其他 agent 类型替代 developer

   每个 developer 读取对应源码，结合上下文判断每条告警的归属：

   | 分类 | 判定 | 处理 |
   |------|------|------|
   | 误报 | 工具对当前代码模式的误判 | 排除，建议在项目配置中 suppress |
   | 有意为之 | 兼容性、性能优化等合理原因 | 排除，建议加注释说明 |
   | 非本次变更引入 | 非本次变更引入 | 排除，记录备忘（不阻塞本次合并） |
   | 需修复 | 本次变更引入的实际问题 | 保留，需提供问题说明和修复建议 |

4. **汇总分析报告**

   主会话收集各 developer 的分析结果，生成报告：

   | 模式 | 行为 |
   |------|------|
   | `autofix` 未设置 | 输出完整分析报告后结束 |
   | `autofix` 已设置 | 需修复列表为空 → 通过；否则派遣 developer 逐项修复，修复后回归 lint 验证，最多 5 轮 |

## 输出格式

L1 + L2 均通过（零告警）时：

```
模式: <本地开发 / CI>
L1 编译检查
  ✓ <命令1>: PASSED
  ✓ <命令2>: PASSED

L2 Lint 分析
  ✓ <命令1>: 零告警通过
  ✓ <命令2>: 零告警通过
```

L2 存在告警时：

```
模式: <本地开发 / CI>
L1 编译检查
  ✓ <命令1>: PASSED
  ✓ <命令2>: PASSED

Lint 分析报告
  需修复 M 条：
    1. [文件:行号] <告警内容> — <问题说明> — <修复建议>
    2. ...
  排除 N 条：
    [文件:行号] <告警内容> — <排除原因：误报/有意为之/非本次变更引入>
    ...
```

L1 失败时（直接退出，不进入 L2）：

```
模式: <本地开发 / CI>
L1 编译检查
  ✓ <命令1>: PASSED
  ✗ <命令2>: FAILED
    error: [文件:行号] <错误信息>
    warning: [文件:行号] <警告信息>
```

## 出口标准

- [ ] L1 编译通过
- [ ] L2 需修复列表为空
- [ ] `autofix` 模式下修复循环不超过 5 轮

## 红旗清单

| 红旗 | 触发条件 | 处理方式 |
|------|---------|---------|
| 🚩 修复死循环 | 5 轮修复后仍有未解决问题 | 停止，输出完整问题清单 |
| 🚩 构建命令未知 | 上下文无记录 + 探测无结果 + 用户无法确认 | 停止，提示用户配置构建命令，禁止自行拼凑 |
| 🚩 Lint 命令未知 | 上下文无记录 + 探测无结果 + 用户无法确认 | 停止，提示用户配置 lint 命令，禁止自行拼凑 |
| 🚩 agent 自行扩展检查范围 | agent 引入 Skill 未定义的检查工具、步骤或 agent 类型 | 停止，回退到 Skill 定义的流程 |
| 🚩 修复引入新问题 | developer 修复后出现新的编译 error | 继续修复循环（消耗轮次），若同时触发 5 轮上限则停止 |
| 🚩 agent 自行跳过检查 | agent 根据变更范围分析跳过 L1/L2 检查步骤 | 停止，提示 agent 无权限自行裁量检查范围 |
