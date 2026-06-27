# /df:pr-review

对 GitHub Pull Request 或 GitLab Merge Request 执行代码评审。

## 何时使用

- 手动评审指定 PR/MR，或自动检测当前分支对应的 PR/MR
- CI pipeline 自动调用，将评审结论以评论形式贴回 PR/MR 页面

## 参数

```
/df:pr-review [pr-link] [--ci]
```

- `pr-link`（可选）：PR/MR 链接。省略时自动检测当前 git 分支对应的 PR/MR。
- `--ci`（可选）：CI 模式。非交互运行，自动发帖，输出 JSON 结果供 CI 判断是否阻塞合并。

## 使用示例

**手动评审**：

```
/df:pr-review https://gitlab.com/org/repo/-/merge_requests/123
> 平台: GitLab | MR: !123
> [Round 1] CRITICAL: 0 | HIGH: 1 | MEDIUM: 2 | LOW: 1
> 最终结论: REQUEST_CHANGES
```

**CI 自动触发**：

```
claude -p "/df:pr-review --ci <pr-link>"
> 退出码: 1
> 总结评论已贴到 MR !123
```

## 关联

- Skill: `devforge-pr-review`, `devforge-code-review`
- Agent: `product-reviewer`
- Rules: `coding-style`, `testing`
