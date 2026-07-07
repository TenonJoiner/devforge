---
name: devforge-lint-check
description: 编译检查与 Lint 分析——零 warning 验证
allowed-tools: [Read, Bash, Grep, Glob, Edit]
parameters:
  - name: autofix
    description: 检测后自动修复问题（默认只检测不修复）
    required: false
    default: false
---

# devforge-lint-check — 编译检查与 Lint 分析

## 概述

编译通过（零 warning）→ Lint 分析（工具化静态检查）。两层防护，提前拦截问题。

默认只检测并输出报告。带 `autofix` 参数时自动派遣 developer 修复并回归检查，最多 5 轮。

### 职责边界

- ✅ Lint 工具执行 + 告警分类（误报/有意为之/历史遗留/需修复）
- ✅ `autofix` 模式下派遣 developer 修复需修复项
- ❌ 不做深度代码审查（语义 bug、架构问题、设计缺陷）→ 归属 `/df:code-review`
- ❌ 不引入 Skill 未定义的检查工具或步骤
- ❌ Lint 零告警时直接通过，不扩展检查范围

## L1：编译检查

1. **获取构建命令**
   - 在当前会话上下文中查找已知的构建方法（CLAUDE.md、README、项目 rules、先前对话等），如找到则直接使用
   - 若未找到，探测项目中存在的构建系统文件（Makefile、`build.sh`、`CMakeLists.txt`、`go.mod`、`package.json` 等），确定构建系统类型
   - 自行探测结果需**向用户确认**后再使用。确认后将命令写入 `.claude/domain-config.yaml`：
     ```yaml
     build:
       command: "<用户确认的命令>"
     ```

2. **执行构建**，捕获完整输出

3. **处理结果**

   | 结果 | `autofix` 未设置 | `autofix` 已设置 |
   |------|-----------------|-------------------|
   | 零 error、零 warning | 通过，进入 L2 | 通过，进入 L2 |
   | 存在 error 或 warning | 输出错误/警告清单，结束 | 派遣 developer 修复，修复后回归编译验证，最多 5 轮 |

## L2：Lint 分析

1. **获取 Lint 命令**
   - 在当前会话上下文中查找已知的 lint 方法（CLAUDE.md、README、项目 rules、先前对话等），如找到则直接使用
   - 若未找到，探测项目中存在的 lint 脚本（Makefile `lint` target、`package.json` `lint` script、`lint.sh`、`scripts/lint.sh` 等）
   - 自行探测结果需**向用户确认**后再使用。确认后将命令写入 `.claude/domain-config.yaml`：
     ```yaml
     lint:
       command: "<用户确认的命令>"
     ```

2. **执行 Lint**，捕获 stdout。若 stdout 为空，分析该脚本找到输出重定向的目标文件并读取；仍无法获取则提示用户确认输出位置

   **若 lint 输出零告警（零 warning、零 error），输出通过信息后结束，不进入步骤 3。**

3. **分析 Lint 报告**（仅 lint 存在告警时执行）

   将 lint 输出按文件分组，派遣多个 developer 并行分析。禁止派遣 code-reviewer 或其他 agent 类型替代 developer。每个 developer 读取对应源码，结合上下文判断每条告警的归属：

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
L1 编译检查
  ✓ <构建命令>: PASSED

L2 Lint 分析
  ✓ <lint命令>: 零告警通过
```

L2 存在告警时：

```
L1 编译检查
  ✓ <构建命令>: PASSED

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
L1 编译检查
  ✗ <构建命令>: FAILED
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
| 🚩 构建命令未知 | 上下文无记录 + 探测无结果 + 用户无法确认 | 停止，提示用户配置构建命令 |
| 🚩 Lint 命令未知 | 上下文无记录 + 探测无结果 + 用户无法确认 | 停止，提示用户配置 lint 命令 |
| 🚩 agent 自行扩展检查范围 | agent 引入 Skill 未定义的检查工具、步骤或 agent 类型 | 停止，回退到 Skill 定义的流程 |
| 🚩 修复引入新问题 | developer 修复后出现新的编译 error | 继续修复循环（消耗轮次），若同时触发 5 轮上限则停止 |
