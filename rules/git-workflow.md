# git-workflow — Coding Agent Git 工作流指南

## 适用范围

本规则供 coding agent 执行 Git 操作时使用。所有涉及 commit、branch、worktree、merge/rebase 的操作必须遵守本规则。

## 核心原则

- 每个 git commit 必须 对应一个可独立验证的 task
- 一个 commit 禁止 包含多个不相关 task 的变更
- 临时开发快照 必须 在 task 完成前整理为 atomic commit

## Git commit 与工作项映射

- 需求/任务跟踪系统中的工作项清单是执行拆解粒度，不直接等同于 git commit 粒度
- 一个 git commit 通常对应一个完整可验证的工作单元（功能实现 + 对应测试 + 必要质量保障）
- 单个工作项如果对应一个完整可验证的单元，可单独成 commit
- lint、review、集成测试、重构等质量保障步骤 推荐合并到对应功能 commit；若对应功能已提交或历史不便改写，可单独成 commit，但应在 message 中说明关联
- 当不确定如何分组时，以"独立验证"为判断标准：该 commit 单独应用后能否通过编译和相关测试

> 示例：在使用 OpenSpec 的场景中，一个 git commit 可能对应一个 Requirement 的全部 Scenario 及其 LINT/REVIEW 保障。

## Commit 粒度

### 基本规则

- 创建 commit 前，agent 必须 确认该 commit 只包含一个 task 的变更
- 多个 task 的变更 必须 拆分为多个 commit
- 开发过程中的临时快照允许存在，但 必须 在 task 完成前整理

### Atomic commit 标准

每个 commit 独立应用后 必须 满足：

- 代码可编译
- 相关单元测试通过
- 相关 lint / 静态分析通过
- 不引入未完成的中间状态

### 整理临时 commit

当当前分支存在临时快照时，在创建正式 commit 前执行：

```bash
git rebase -i <base-branch>
```

其中 `<base-branch>` 是切出当前分支的基线（通常为 `main` 或 `release/<version>`）。

rebase 交互式编辑规则：

- 保留第一个 commit 作为 base，使用 `pick`
- 后续属于同一 task 的临时 commit 使用 `fixup` 合并到前一个 commit
- 如需修改 commit message，使用 `reword`
- 不属于当前 task 的变更 必须 先移出当前分支

如果 rebase 发生冲突：

1. 解决冲突
2. `git add <resolved-files>`
3. `git rebase --continue`
4. 如果冲突无法安全解决，执行 `git rebase --abort` 并通知用户

如果临时 commit 已经 push 到远程：

1. 评估是否可以安全 force push
2. 如果该分支只有你一个人开发，执行 `git push --force-with-lease`
3. 如果分支已被他人使用，必须 先询问用户，不得擅自 force push

## Conventional Commits

### 格式

```
<type>[(<scope>)]: <subject>

<body>

[Refs: <project>/<task-id>]
```

### 字段规则

**type** 必须 为以下之一：

- `feat`：新功能
- `fix`：Bug 修复
- `docs`：文档变更
- `style`：不影响代码含义的格式修改
- `refactor`：既不修复 bug 也不添加功能的代码变更
- `test`：测试相关
- `chore`：构建过程或辅助工具的变动

**scope**：

- 单模块仓库或范围不言自明时，省略 scope
- 多模块仓库使用模块/组件名
- 一次变更多个模块时，优先拆分为多个 commit；必须一起提交时，用逗号分隔

**subject**：

- 使用祈使句、现在时
- 首字母小写
- 末尾不加句号
- 不超过 25 个汉字或等效显示宽度

**body**：

- 描述变更动机（why）和与之前行为的差异（what）
- 段落间空行分隔
- 简洁，不限制字数

**Refs**：

- 绑定需求/任务跟踪系统的工作项时，可添加 `Refs: <project>/<task-id>` 等引用
- 日常维护、文档修正等未绑定工作项时，可省略

## 分支策略

### 分支类型

| 分支 | 用途 | 从哪切出 | 合并到哪 | 生命周期 |
|------|------|---------|---------|---------|
| `main` | 主干 | — | — | 永久 |
| `feat/<feature>` | 特性开发 | `main` 或 `release/<version>` | 同切出分支 | 合并后删除 |
| `fix/<issue>` | 修复分支 | `main` 或 `release/<version>` | 同切出分支 | 合并后删除 |
| `chore/<task>` | 构建、工具链、配置、依赖升级等非功能变更 | `main` 或 `release/<version>` | 同切出分支 | 合并后删除；用于持续维护时可在用户确认后保留 |
| `docs/<topic>` | 文档变更 | `main` 或 `release/<version>` | 同切出分支 | 合并后删除；用于持续维护时可在用户确认后保留 |
| `refactor/<scope>` | 不改变外部行为的重构 | `main` 或 `release/<version>` | 同切出分支 | 合并后删除 |
| `test/<scope>` | 测试基础设施或测试用例补充 | `main` 或 `release/<version>` | 同切出分支 | 合并后删除；用于持续维护时可在用户确认后保留 |
| `release/<version>` | 版本发布分支 | `main` | 不直接合并回 `main` | 版本停止维护后删除 |

### 通用规则

- 从目标分支切出对应类型的分支（`feat/<feature>`、`fix/<issue>`、`chore/<task>`、`docs/<topic>`、`refactor/<scope>`、`test/<scope>`）
- 在该分支上完成单一变更单元的所有工作
- 完成后创建 PR/MR 回目标分支
- agent 不检查目标分支是否受平台保护；推送被平台拦截时通知用户处理
- 合并后，对应本地分支和 worktree 应当清理；持续维护型分支可在用户确认后保留

### MR/PR 创建流程

创建 MR/PR 前，必须完成以下步骤：

1. 确认目标分支：默认目标分支为 `main`；从 `release/<version>` 切出的分支，目标分支为对应 `release/<version>`
2. 获取目标分支最新变更：
   ```bash
   git fetch origin
   ```
3. 将目标分支合并到当前分支：
   ```bash
   git merge origin/<target-branch>
   ```
   若提示已是最新，则跳过后续冲突解决，直接推送。
4. 本地解决冲突（如有），确保冲突解决后代码可编译且相关测试通过
5. 将当前分支推送到远程：
   ```bash
   git push origin <current-branch>
   ```
6. 创建 MR/PR，目标分支为 `<target-branch>`

禁止在同步未完成、冲突未本地解决的情况下直接推送并创建 MR/PR。

### Merge 方式

- 默认使用普通 merge（non-squash），保持 atomic commit 历史
- 如果团队约定使用 squash merge，开发分支合并后 必须 删除，禁止在同一分支上继续开发

## Worktree 规范

### 目录与分支映射

- worktree 目录由项目约定（如 `worktrees/` 或 `.claude/worktrees/`），目录名对应 `wt-<branch-shortname>`（如 `wt-auth-refactor`）
- 每个 worktree 内 checkout 该开发分支（通常为 `feat/<feature>` 等）
- worktree 内开发在该分支上进行
- 禁止在 worktree 内直接操作基线分支（`main` / `release/<version>`），这些分支只读

### 并行开发规则

- 默认粒度是一个独立变更单元：一个开发分支使用一个 worktree
- 单个变更单元内无冲突的多 task 可在同一 worktree 内完成
- 多个变更单元并行开发时，每个变更单元一个独立 worktree

### 清理

- worktree 对应变更单元完成并合并后，使用项目约定的清理方式（如对应 skill 命令或脚本）
- 未提供专用命令时，agent 可在用户确认后删除 worktree 目录并移除已合并的本地分支
- 超过 30 天无活动且未关联未合并分支的 worktree 视为废弃，agent 可在用户确认后清理

## 版本发布分支流程

- 版本发布前，从 `main` 当前稳定点切出 `release/<version>`
- `release/<version>` 接收该版本的特性开发与补丁修复
- 为该版本新增特性、修复 bug 或进行其他变更时，从对应 `release/<version>` 切出合适的开发分支（如 `feat/<feature>`、`fix/<issue>`、`chore/<task>` 等）
- 开发完成后，创建 PR/MR 合并回 `release/<version>`
- 除非用户明确说明不需要，否则 必须 将合并到 `release/<version>` 的变更同步到 `main`
- 同步方式优先使用 cherry-pick；无法 cherry-pick 时，在 `main` 上单独实现并关联同一工作项
- 版本停止维护后，`release/<version>` 分支在用户确认后删除

## Agent 自检清单

执行任何 git 操作前，agent 必须 确认：

- 当前 commit 是否只包含一个 task 的变更？
- 当前 commit 是否符合 Conventional Commits 格式？
- 当前 commit 独立应用后是否可编译且相关测试通过？
- 临时快照是否已整理为 atomic commit？
- worktree 目录是否符合项目约定？
- worktree 内是否未直接修改基线分支？
- 当前分支是否已包含目标分支最新提交？

## 人机交互边界

以下情况 agent 必须 先询问用户，不得擅自执行：

- 对已经 push 且可能被他人使用的分支执行 force push
- 删除未合并的分支或 worktree
- rebase 冲突无法安全解决
- 不确定某个变更属于哪个 task 时
