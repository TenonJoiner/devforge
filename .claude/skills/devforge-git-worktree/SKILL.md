---
name: devforge-git-worktree
description: Git worktree 隔离并行开发——创建、切换、清理规范
allowed-tools: [Read, Write, Edit, Bash, Grep]
---

# devforge-git-worktree — worktree 隔离并行开发

## 概述

每个独立开发任务使用独立 worktree，避免本地分支污染和并行冲突。

**核心原则**：
- **检测已有隔离**：创建前先检查是否已在 worktree 中，避免嵌套
- **默认粒度是 proposal**：一个 proposal（含其下属的 10+ 个小 task）使用一个 worktree 完成
- **按需隔离**：同一 proposal 内共享一个 worktree；不同 proposal 各自独立 worktree

**合并与拆分的判断标准**：
| 场景 | worktree 策略 |
|------|--------------|
| 单个 proposal 内的 task（默认） | 同一 worktree 内串行完成 |
| 单个 proposal 内无冲突的多 agent 并行 | 同一 worktree 内并行，无需拆分 |
| 多个 proposal 并行开发 | 每个 proposal 一个独立 worktree |
| 同一 proposal 的 A/B 验证或高风险重构 | 创建额外隔离 worktree |
| 代码评审需要干净环境 | 临时创建评审 worktree |

## 共享规范

### 命名规范

| 场景 | 命名示例 |
|------|----------|
| proposal 开发（默认） | `wt-storage-wal` |
| A/B 验证/实验 | `wt-storage-wal-exp1` |
| 评审验证 | `wt-review-storage-wal` |

对应分支名：`feat/<proposal-name>`

### 清理约束

1. **先 `cd` 到主仓库根目录**——从 worktree 内部执行 `git worktree remove` 会静默失败
2. **先 remove worktree 再删分支**——`git branch -d` 会因 worktree 引用而失败，必须先移除 worktree
3. **remove 后执行 `git worktree prune`**——自愈清理过期注册
4. **创建 PR 时保留 worktree**——PR 未合并前可能需要修改

**手动清理命令**：

```bash
cd <主仓库根目录>
git worktree remove .claude/worktrees/wt-<name>
git worktree prune
git branch -d feat/<name>                  # 已合并；丢弃用 -D
```

### 常见错误

- **创建嵌套 worktree** — 在已有 worktree 中再创建 worktree。修复：创建前必须执行检测。
- **跳过 gitignore 验证** — worktree 内容被 git 跟踪，污染 git status。修复：创建前检查 `.claude/worktrees/` 是否被忽略。
- **从 worktree 内部执行 `git worktree remove`** — 命令会静默失败。必须先 `cd` 到主仓库根目录。
- **删除分支前未移除 worktree** — `git branch -d` 会失败，因为 worktree 仍引用该分支。必须先 remove worktree，再删分支。
- **合并后未验证测试** — 合并可能引入回归，合并后必须跑测试确认。
- **创建 PR 后清理了 worktree** — PR 未合并时可能需要修改，保留 worktree 供迭代。
- **丢弃前未确认** — 必须要求 typed 确认（输入 `discard`），防止误删。

### 红旗信号

- worktree 长期不清理，积累大量废弃分支
- 同 proposal 内无冲突却拆成多个 worktree，造成不必要的上下文切换
- 跳过检测直接创建 worktree

### 并行开发规约

1. **默认粒度是 proposal**：一个 proposal 内的所有 task 在同一个 worktree 中完成
2. **proposal 内并行**：经冲突评估后，不同 agent 可在同一 worktree 内并行修改不同文件；同文件修改则串行
3. **多 proposal 并行**：每个 proposal 必须使用独立 worktree
4. **冲突检测**：worktree 间通过 git fetch + diff 检测潜在冲突
5. **最终合并**：每个 worktree 的修改通过独立 PR/MR 合并到 main
6. **定期清理**：废弃的 worktree 和已合并分支应在当天或当周清理，避免堆积

## /df:switch-worktree 执行流程

### Step 1: 检测已有隔离

**创建任何 worktree 之前，先检查是否已在隔离工作区中：**

```bash
GIT_DIR=$(cd "$(git rev-parse --git-dir)" 2>/dev/null && pwd -P)
GIT_COMMON=$(cd "$(git rev-parse --git-common-dir)" 2>/dev/null && pwd -P)
```

**子模块守护**：`GIT_DIR != GIT_COMMON` 在 git submodule 中也成立。排除子模块：

```bash
# 如果返回路径，说明在子模块中——按普通仓库处理
git rev-parse --show-superproject-working-tree 2>/dev/null
```

- **如果 `GIT_DIR != GIT_COMMON`（且不是子模块）**：已在 linked worktree 中，跳过创建，直接切换到对应 worktree
- **如果 `GIT_DIR == GIT_COMMON`**：在普通仓库中，可以创建 worktree

### Step 2: 创建 worktree（仅在普通仓库中执行）

```bash
# 基于当前分支创建新 worktree
git worktree add .claude/worktrees/wt-<name> -b feat/<name>
```

> Git worktree 共享原仓库的 `.git` 对象库，仅额外占用索引和工作目录，创建/切换成本秒级，磁盘开销很小。因此隔离的核心成本是**上下文切换的心智负担**，而非磁盘或性能。

**gitignore 验证**（创建前必须检查）：

```bash
git check-ignore -q .claude/worktrees 2>/dev/null
```

**如果未被忽略**：将 `.claude/worktrees/` 加入 `.gitignore` 并提交，防止 worktree 内容被误提交到仓库。

### Step 3: 进入目标 worktree

无论新创建还是已有 worktree，最终都执行：

```bash
cd .claude/worktrees/wt-<name>
```

进入后提示用户当前所在 worktree 和分支。后续开发都在 worktree 内执行。

## /df:finish-worktree 执行流程

### Step 1: 验证测试（合并前检查）

跑**合并前验证测试**，确保代码达到可合并质量。

**测试命令获取优先级**（从项目 CLAUDE.md 中读取）：

1. **`merge_gate`** — MR门禁用例（L1 集成测试），合并前 CI 实际执行的检查。优先跑这个，因为它就是合并前真正要过的关卡。
2. **`unit_test`** — 全量单元测试。如果项目没配 `merge_gate`，兜底跑单元测试。

如果 CLAUDE.md 未配置测试命令，根据项目构建系统推断（Makefile/CMakeLists.txt/Cargo.toml/go.mod/pyproject.toml 等）。测试命令通常包含编译，不需要单独的 build 步骤。

- 测试**失败**：停止，报告失败
- 测试**通过**：继续到 Step 2

### Step 2: 环境检测并呈现选项

先判断当前工作区状态，再根据状态呈现对应选项：

| 状态 | 选项 |
|------|------|
| 主工作区（`GIT_DIR == GIT_COMMON`） | 标准 4 选项，无 worktree 需清理 |
| linked worktree + 命名分支（`GIT_DIR != GIT_COMMON`） | 标准 4 选项 |
| linked worktree + detached HEAD（`GIT_DIR != GIT_COMMON` + 无分支名） | 3 选项（无"本地合并"） |

| 选项 | 操作 |
|------|------|
| 1. 本地合并 | `git checkout main && git merge feat/<name> && git push origin main`，然后删除 worktree 和分支 |
| 2. 推送并创建 PR | `git push origin feat/<name>`，然后从 CLAUDE.md 获取 PR 创建命令（如 `gh pr create`）创建 PR，保留 worktree |
| 3. 保持当前状态 | 不做任何操作 |
| 4. 丢弃 | 删除 worktree 和分支（需 typed 确认） |

### Step 3: 清理（选项 1 和 4 时执行）

按**共享规范 → 清理约束**执行。

选项 1（本地合并）执行后，**在合并结果上再跑一遍测试**确认无回归，测试通过后才执行清理。

## Integration

| 命令 | 作用 | 触发时机 |
|------|------|---------|
| `/opsx:apply` | 获取 task 信息 | switch-worktree 前置 |
| `/df:switch-worktree` | 创建/切换 worktree | 开始开发 |
| `/df:finish-worktree` | 合并/清理 worktree | 开发完成 |
| `/opsx:archive` | 归档 delta specs | finish-worktree 合并代码后 |

一个 proposal 的完整收尾顺序：
1. `/df:finish-worktree` — 代码合并到 `main`，清理本地 worktree
2. （可选）`/opsx:verify` — 验证实现符合规范
3. `/opsx:archive` — 归档 delta specs 到主规范，commit 并 push 文档变更
