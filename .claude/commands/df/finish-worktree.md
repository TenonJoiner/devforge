# /df:finish-worktree

完成当前 worktree 的开发工作：验证测试 → 呈现合并选项 → 执行选择 → 清理。

## 何时使用

- proposal 开发完成，需要合并回 main
- 需要创建 PR 并清理关联 worktree
- 需要丢弃废弃的 worktree

## 执行流程

1. 激活 `developer` Agent
2. **前置状态检测**：检查当前分支是否已合并到 base branch（如 `main`）
   - **若已合并**：直接提示"分支已合并，是否清理关联 worktree？"
     - 确认后自动执行 `git worktree remove` + 删除分支 + 清除 `~/.claude/projects/<repo-name>/active-worktree`
     - 跳过后续选项展示
   - **若未合并**：继续下一步
3. **验证测试**：运行 `./run-tests.sh ut`（或项目定义的测试命令），确认通过；失败则停止
4. **确定 base branch**：通常为 `main`
5. **呈现选项**：
   - **选项 1**：本地合并回 `main`，成功后清理 worktree
   - **选项 2**：推送分支并创建 Pull Request，**保留** worktree（PR 未合并前可能需要修改）
   - **选项 3**：保持当前状态，以后再处理
   - **选项 4**：丢弃当前分支和 worktree（需 typed 确认）
6. **执行选择**：执行对应 git 操作
7. **清理 worktree**（选项 1、4）：执行 `git worktree remove` 并删除 `~/.claude/projects/<repo-name>/active-worktree`
   - **选项 2 的后续**：PR 合并后再次执行 `/df:finish-worktree`，将通过前置状态检测自动进入快速清理流程
8. **后序引导**：清理完成后提示用户继续执行 `/opsx:verify`（如需）→ `/opsx:archive`

## 参数

```
/df:finish-worktree    # 处理当前所在 worktree
```

## 使用示例

```
/df:finish-worktree
> 测试通过 ✅
> 选择：2. 推送并创建 PR
> PR 已创建：#42
> worktree 保留在 .claude/worktrees/wt-storage-wal
```

## 关联

- Skill: `code/git-worktree`
- Agent: `developer`
- Hooks: `worktree-guard`
