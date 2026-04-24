# /df:code-review

执行三级代码评审管线。

## 何时使用

- task 完成后提交前
- 特性级 `/opsx:verify` 之前
- 任何需要外部视角检查代码质量的时刻

## 执行流程

1. 激活 `code-reviewer` Agent
2. **范围确认**：
   - 日常轻量评审：获取当前工作区 `git diff HEAD` + `git diff --cached` 的变更
   - Q.4 全量收尾：获取 `git diff $(git merge-base HEAD main)..HEAD` 的完整 proposal 变更
3. **模式选择**：基于范围行数和模块数自动选择
   - 轻量评审（< 300 行且模块 ≤ 2）：`code-reviewer` 单 agent 完成 L1+L2+L3
   - 深度评审（≥ 300 行，或 3+ 模块，或 Q.4 收尾）：启动 3 个 `code-reviewer` subagent 并行（通用质量 / C 专项 / 安全审计），主 agent 汇总去重
4. 输出结构化评审报告，写入 `/tmp/code-review-report-<timestamp>.md`
5. `developer` 或 feedback-loop 读取报告并按 CRITICAL → HIGH 顺序修复
6. 修复验证通过后，自动删除该临时报告

## 与 `/opsx:apply` 的衔接

- **N.M.6 REVIEW**：单个 task 完成后执行 `/df:code-review`
- **Q.4 代码评审收尾**：所有实现 task 完成后，由 `code-reviewer`(A3) 执行全量 diff 评审

## 参数

```
/df:code-review [file-pattern]
```

- `file-pattern`（可选）：只评审匹配的文件，如 `src/storage/*.c`

## 使用示例

```
/df:code-review
> 评审 3 个文件，+120 -45
> 发现 1 个 HIGH：wal.c:89 缺少错误返回值检查
> 发现 2 个 MEDIUM：`storage_engine.c:2100` 函数长度 980 行且包含两类资源操作，建议拆分为 `wal_init()` 和 `index_init()`
> 结论：不通过（存在未处理 HIGH）
```

## 关联

- Skill: `code/code-review`
- Agent: `code-reviewer`
- Rules: `coding-style`, `testing`
