## Integration

| 命令 | 作用 | 触发时机 |
|------|------|---------|
| `/df:switch-worktree` | 创建/切换 worktree | 开始开发 |
| `/df:finish-worktree` | 合并/清理 worktree | 开发完成 |

一个 proposal 的完整收尾顺序：
1. `/df:finish-worktree` — 代码合并到 `main`，清理本地 worktree
2. （可选）验证实现符合规范
3. 归档 delta specs 到主规范，commit 并 push 文档变更
