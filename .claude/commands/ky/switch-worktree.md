# /ky:switch-worktree

切换或创建 Git worktree，实现隔离并行开发。

## 何时使用

- 启动新 proposal 的开发
- 在不同 proposal 的 worktree 之间切换
- 创建干净的评审环境

## 执行流程

1. 激活 `developer` Agent
2. 检测现有 worktree 列表：`git worktree list`
3. 如果用户指定了存在的 worktree → 直接切换
4. 如果不存在 → 询问是否创建，并自动按 proposal 命名
5. 进入 `code/git-worktree` Skill 完成切换

## 参数

```
/ky:switch-worktree [proposal-name]
```

- `proposal-name`（可选）：目标 proposal 名称，对应 worktree 为 `wt-<proposal-name>`

## 使用示例

```
/ky:switch-worktree storage-wal
> 已切换到 .claude/worktrees/wt-storage-wal
> 当前分支：feat/storage-wal
```

## 关联

- Skill: `code/git-worktree`
- Agent: `developer`
- Hooks: `worktree-guard`
