---
name: devforge-git-worktree
description: Git worktree 隔离并行开发——创建、切换、清理规范
allowed-tools: [Read, Write, Edit, Bash, Grep]
---

# devforge-git-worktree — worktree 隔离并行开发

## 概述

每个独立开发任务使用独立 worktree，避免本地分支污染和并行冲突。

**核心原则**：
- **默认粒度是 proposal**：一个 proposal（含其下属的 10+ 个小 task）使用一个 worktree 完成
- **按需隔离**：单个 proposal 内的 task 串行或同 worktree 内并行；多个 proposal 并行时才拆
- **命名规范**：`wt-<proposal>-<brief-desc>`（默认按 proposal）或 `wt-<proposal>-experiment`（A/B 验证）
- **主干保护**：不在 main 分支直接修改（H3 worktree-guard 守护）

**合并与拆分的判断标准**：
| 场景 | worktree 策略 |
|------|--------------|
| 单个 proposal 内的 task（默认） | 同一 worktree 内串行完成 |
| 单个 proposal 内无冲突的多 agent 并行 | 同一 worktree 内并行，无需拆分 |
| 多个 proposal 并行开发 | 每个 proposal 一个独立 worktree |
| 同一 proposal 的 A/B 验证或高风险重构 | 创建额外隔离 worktree |
| 代码评审需要干净环境 | 临时创建评审 worktree |

## 何时使用

- 启动一个新 proposal 的开发（默认创建一个 worktree）
- 多个 proposal 需要并行开发（每个 proposal 一个 worktree）
- 大型/高风险变更需要独立的隔离环境
- 需要为代码评审创建一个干净的验证环境

## worktree 管理规范

### 创建 worktree

```bash
# 基于当前分支创建新 worktree
git worktree add .claude/worktrees/wt-<name> -b feat/<name>
```

> Git worktree 共享原仓库的 `.git` 对象库，仅额外占用索引和工作目录，创建/切换成本秒级，磁盘开销很小。因此隔离的核心成本是**上下文切换的心智负担**，而非磁盘或性能。

**命名建议**：
| 场景 | 命名示例 |
|------|----------|
| proposal 开发（默认） | `wt-storage-wal` |
| A/B 验证/实验 | `wt-storage-wal-exp1` |
| 评审验证 | `wt-review-storage-wal` |

### 切换 worktree

使用 `/df:switch-worktree <name>` 快速切换：
1. 保存当前 context（可选）
2. `cd .claude/worktrees/wt-<name>`（当前 shell session 的工作目录切换到该 worktree）
3. 更新 `~/.claude/projects/<repo-name>/active-worktree` 状态文件
4. 提示用户当前所在 worktree

**会话中断恢复**：
- Claude 重开后默认 CWD 为仓库根目录，不会自动进入活跃 worktree
- 此时 H3 `worktree-guard` 仍会拦截写操作
- **必须再次执行 `/df:switch-worktree <name>`** 恢复 CWD 和完整上下文

### 清理 worktree

**自动清理入口**：使用 `/df:finish-worktree` 完成开发工作并自动清理。参考 superpowers `finishing-a-development-branch` skill 的流程：
1. **验证测试**：运行全量单元测试，通过后方可继续
2. **呈现选项**：本地 merge / 推送创建 PR / 保持状态 / 丢弃
3. **执行选择**：根据选项执行对应 git 操作
4. **清理 worktree**：本地 merge 或丢弃后，自动执行下述清理命令；创建 PR 时**保留** worktree

**手动清理**（当选择本地 merge 或丢弃时，由 `/df:finish-worktree` 自动执行）：

```bash
git worktree remove .claude/worktrees/wt-<name>
git branch -D feat/<name>          # 如已合并则删除
rm ~/.claude/projects/<repo-name>/active-worktree  # 同步清除状态文件
```

> 若 `active-worktree` 未及时清除，H3 `worktree-guard` 会指向一个不存在的目录，导致后续写操作被错误拦截。

## 并行开发规约

1. **默认粒度是 proposal**：一个 proposal 内的所有 task 在同一个 worktree 中完成
2. **proposal 内并行**：经冲突评估后，不同 agent 可在同一 worktree 内并行修改不同文件；同文件修改则串行
3. **多 proposal 并行**：每个 proposal 必须使用独立 worktree
4. **冲突检测**：worktree 间通过 git fetch + diff 检测潜在冲突
5. **最终合并**：每个 worktree 的修改通过独立 PR/MR 合并到 main
6. **定期清理**：废弃的 worktree 和已合并分支应在当天或当周清理，避免堆积

## 红旗信号

- 在 main 分支直接修改（H3 会拦截）
- worktree 长期不清理，积累大量废弃分支
- 同 proposal 内无冲突却拆成多个 worktree，造成不必要的上下文切换

## Integration

- **前置 Command**: `/opsx:apply`（获取 task 信息）
- **创建/切换 Command**: `/df:switch-worktree`
- **完成/清理 Command**: `/df:finish-worktree`
- **后续 Command**: `/opsx:archive`（必须在 `/df:finish-worktree` 合并代码后执行）
- **Hook**: H3 `worktree-guard`

### 与 OpenSpec workflow 的顺序

一个 proposal 的完整收尾推荐顺序：
1. `/df:finish-worktree` — 代码合并到 `main`，清理本地 worktree
2. （可选）`/opsx:verify` — 验证实现符合规范
3. `/opsx:archive` — 归档 delta specs 到主规范

> 由于三者均为手工执行命令，此处的顺序约束为**引导性**而非强制性。实际项目中可通过 `/opsx:archive` 的前置检查点（如验证对应 feature branch 已不存在或已合并）来增加流程刚性。
