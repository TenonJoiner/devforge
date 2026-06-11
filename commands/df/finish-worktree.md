---
name: finish-worktree
description: 完成当前 worktree 的开发工作：验证测试 → 呈现合并选项 → 执行选择 → 清理。
---

# /df:finish-worktree

完成当前 worktree 的开发工作：验证测试 → 呈现合并选项 → 执行选择 → 清理。

## 何时使用

- proposal 开发完成，需要合并回 main
- 需要创建 PR 并清理关联 worktree
- 需要丢弃废弃的 worktree

## 执行流程

1. 激活 `developer` Agent，进入 `devforge-git-worktree` Skill
2. 前置状态检测：检查当前分支是否已合并到 base branch
3. 环境检测：判断工作区状态（普通仓库 / linked worktree / detached HEAD）
4. 验证测试：运行 `./run-tests.sh ut`，失败则停止
5. 确定 base branch，呈现选项（本地合并 / 推送创建 PR / 保持状态 / 丢弃）
6. 执行选择，按 Skill 中定义的清理约束执行清理
7. 后序引导：提示继续代码评审和清理

## 参数

```
/df:finish-worktree    # 处理当前所在 worktree
```

## 产出物

- 本地合并：代码合并到 main，worktree 和分支已清理
- 创建 PR：PR 链接，worktree 保留
- 丢弃：worktree 和分支已删除

## 关联

- Skill: `devforge-git-worktree`
- Agent: `developer`
