#!/bin/bash
ACTIVE_WORKTREE_FILE="$HOME/.claude/projects/$(basename "$PWD")/active-worktree"
[ ! -f "$ACTIVE_WORKTREE_FILE" ] && exit 0

ACTIVE_WORKTREE=$(cat "$ACTIVE_WORKTREE_FILE" | tr -d '[:space:]')
[ -z "$ACTIVE_WORKTREE" ] && exit 0

# 获取当前工作目录
CWD=$(pwd)
# 计算活跃 worktree 的绝对路径
ACTIVE_PATH=$(cd "$ACTIVE_WORKTREE" 2>/dev/null && pwd || echo "")

# 检查当前是否在活跃 worktree 目录内
if [ -n "$ACTIVE_PATH" ] && [[ "$CWD" == "$ACTIVE_PATH"* ]]; then
    exit 0
fi

# 检查是否身处另一个 worktree
CURRENT_WORKTREE=$(git rev-parse --show-toplevel 2>/dev/null || echo "")

if [ -z "$CURRENT_WORKTREE" ] || [ "$CURRENT_WORKTREE" = "$(git -C "$ACTIVE_WORKTREE" rev-parse --show-toplevel 2>/dev/null)" ]; then
    # 在仓库根目录或其他非 worktree 路径
    echo "worktree 守护：当前不在活跃 worktree 内"
    echo "   当前目录：$CWD"
    echo "   活跃 worktree：$ACTIVE_WORKTREE"
    echo "   建议执行 /df:switch-worktree $(basename "$ACTIVE_WORKTREE" | sed 's/^wt-//') 恢复上下文"
else
    # 在另一个 worktree 中
    echo "worktree 守护：当前在另一个 worktree（$CURRENT_WORKTREE），但活跃 worktree 是 $ACTIVE_WORKTREE"
    echo "   建议："
    echo "     1. 执行 /df:switch-worktree $(basename "$ACTIVE_WORKTREE" | sed 's/^wt-//') 切换"
    echo "     2. 若已废弃该 worktree，执行 /df:finish-worktree 完成清理"
fi
exit 1
