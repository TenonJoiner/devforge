# R2 git-workflow — Git 工作流规范

## 适用范围

所有代码提交。

## Commit 粒度

**基本单位是 task group（Requirement）**。

- 每个 Requirement 任务组（含所有 Scenario 实现 + LINT 修复 + REVIEW 修复）完成后，整理为一个正式 commit
- task 内部 developer 可自由 commit 作为工作快照，task group 完成前使用 `git rebase -i` 整理为单一 atomic commit
- 禁止一个 commit 包含多个 Requirement 的变更
- 禁止多个 task group 不 commit 攒在一起

**为什么以 task group 为粒度**：
- 与代码评审（N.M.6 REVIEW）的粒度对齐——REVIEW 评审的是整个 Requirement 的变更
- 保持对外 commit 历史简洁，同时允许开发过程中频繁快照
- 每个 commit 对应一条可独立验证的 Requirement

## Conventional Commits

提交信息格式：

```
<type>(<scope>): <subject>

<body>

Refs: <proposal-name>/<task-id>
```

**type**：
- `feat`: 新功能
- `fix`: Bug 修复
- `docs`: 文档变更
- `style`: 不影响代码含义的格式修改
- `refactor`: 既不修复 bug 也不添加功能的代码变更
- `test`: 测试相关
- `chore`: 构建过程或辅助工具的变动

**scope**：子系统名，如 `storage`、`metadata`、`network`

**Refs**：关联的 OpenSpec proposal 或 task（如 `Refs: storage-wal-impl/step-2`）

**commit message 中的 `task-id`**：使用 tasks.md 中的任务组编号（如 `1`、`2a`），表示该 commit 对应哪个 Requirement 任务组

## 分支策略

- **main**：只接受合并，不接受直接推送
- **feat/<proposal>**：特性开发分支
- **fix/<issue>**：热修复分支
- **wt-<proposal>**：worktree 专用分支

## worktree 规范

- **默认粒度是 proposal**：一个 proposal 使用一个 worktree
- worktree 目录统一放在 `.claude/worktrees/`
- 单个 proposal 内无冲突的多 agent 并行可在同一 worktree 内完成
- 多个 proposal 并行开发时，每个 proposal 一个独立 worktree
- 废弃 worktree 及时清理
