# R2 git-workflow — Git 工作流规范

## 适用范围

所有代码提交。

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
