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

> 临时快照的整理命令见 [MR/PR 创建流程](#mrpr-创建流程) 第 3 步及 [整理临时 commit](#整理临时-commit) 小节。

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

### 分支创建权限

**agent 禁止自主创建分支。** 只有在以下任一条件下，agent 才可创建分支：

1. 用户明确要求创建分支（如"拉个分支"、"创建 fix/xxx 分支"）
2. 用户要求执行的操作隐式需要新分支（如"用 worktree 隔离开发"、"在独立分支上做这个变更"）

以下场景不满足上述条件，**禁止**创建分支：

- agent 自行判断"应该用分支隔离"而用户未提及分支或 worktree
- agent 为"保持工作干净"而主动切分支
- 当前分支已是 `main`，agent 认为"不应该直接在 main 上改"而自行切分支

**违规判定**：只要用户指令中没有分支/隔离关键词，agent 自行执行了 `git checkout -b`、`git switch -c`、`git branch` 创建新分支、或通过 worktree 间接创建分支，均属违规。

### 通用规则

- 经用户确认需要分支时，从目标分支切出对应类型的分支（`feat/<feature>`、`fix/<issue>`、`chore/<task>`、`docs/<topic>`、`refactor/<scope>`、`test/<scope>`）
- 在该分支上完成单一变更单元的所有工作
- 完成后创建 PR/MR 回目标分支
- agent 不检查目标分支是否受平台保护；推送被平台拦截时通知用户处理
- 合并后，对应本地分支和 worktree 应当清理；持续维护型分支可在用户确认后保留

### MR/PR 创建流程

创建 MR/PR 前，必须完成以下步骤：

1. 确认目标分支：默认目标分支为 `main`；从 `release/<version>` 切出的分支，目标分支为对应 `release/<version>`

   > `origin/HEAD` 或 IDE 提示的 "Main branch" 均不可作为目标分支依据，必须以本规则为准。

2. 获取目标分支最新变更：
   ```bash
   git fetch origin
   ```

3. 整理临时 commit：
   若当前分支存在开发过程中的临时快照，按「整理临时 commit」小节的非交互方式整理为 atomic commit。复杂情况询问用户。
   例如所有快照属于同一 task 时：
   ```bash
   git reset <base-branch>
   git add .
   git commit -m "<type>[(<scope>)]: <subject>"
   ```
   `<base-branch>` 为切出当前分支的基线（通常与目标分支一致）。

4. 确定当前分支独有提交，用于 MR/PR 描述和变更归因：
   ```bash
   git log --oneline --left-right origin/<target-branch>...HEAD
   ```
   - 输出左侧 `<` 的提交属于目标分支；右侧 `>` 的提交属于当前分支。
   - MR/PR 描述和变更归因只应基于右侧 `>` 的提交。

   > 禁止使用双点 `..`（如 `git log origin/<target-branch>..HEAD`）。当当前分支历史上包含 merge commit 时，双点语法可能把目标分支侧提交也纳入结果，导致 MR/PR 描述错误归因。

5. 将当前分支变基到目标分支：
   ```bash
   git rebase origin/<target-branch>
   ```
   若提示已是最新，则跳过后续冲突解决，直接推送。

6. 本地解决冲突（如有）：
   若 `git rebase` 发生冲突：
   1. 解决冲突
   2. `git add <resolved-files>`
   3. `git rebase --continue`
   4. 如果冲突无法安全解决，执行 `git rebase --abort` 并通知用户

   冲突解决后，确保代码可编译且相关测试通过。

7. 将当前分支推送到远程：
   ```bash
   git push --force-with-lease origin <current-branch>
   ```

8. 创建 MR/PR，目标分支为 `<target-branch>`。

禁止在 rebase 未完成、冲突未本地解决的情况下直接推送并创建 MR/PR。

### MR/PR 合并方式

本节指平台接受 MR/PR 时采用的合并方式，与开发者本地同步目标分支的 rebase 策略无关。

- 默认使用普通 merge（non-squash），保持 atomic commit 历史
- 如果团队约定使用 squash merge，开发分支合并后 必须 删除，禁止在同一分支上继续开发

### 整理临时 commit

开发过程中允许存在临时快照。在提交 MR/PR 前，必须将临时快照整理为 atomic commit。

AI 自动执行时，禁止使用交互式 `git rebase -i`。

#### 所有临时快照属于同一 task

重置到基线，一次性提交为单个 atomic commit：

```bash
git reset <base-branch>
git add .
git commit -m "<type>[(<scope>)]: <subject>"
```

其中 `<base-branch>` 是切出当前分支的基线（通常为 `main` 或 `release/<version>`）。

#### 需要拆分为多个 atomic commit 或复杂整理

以下情况必须询问用户，不得擅自执行交互式 rebase：

- 当前分支包含多个 task 的变更，需要拆分成多个 atomic commit
- 无法通过非交互方式安全完成整理

向用户提出拆分方案：

> 我计划将当前分支拆分为以下 N 个 atomic commit：
> 1. `type(scope): subject` — 变更范围说明
> 2. ...
>
> 请确认该方案，或说明需要调整的地方。

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

- 当前操作是否涉及创建新分支？若是，是否已获得用户明确授权？
- 当前 commit 是否只包含一个 task 的变更？
- 当前 commit 是否符合 Conventional Commits 格式？
- 当前 commit 独立应用后是否可编译且相关测试通过？
- 临时快照是否已整理为 atomic commit？
- worktree 目录是否符合项目约定？
- worktree 内是否未直接修改基线分支？
- 当前分支是否已包含目标分支最新提交？

## 人机交互边界

以下情况 agent 必须 先询问用户，不得擅自执行：

- 创建新分支（包括 `git checkout -b`、`git switch -c`、`git branch`、或通过 worktree 间接创建）
- 删除未合并的分支或 worktree
- rebase 冲突无法安全解决
- 不确定某个变更属于哪个 task 时
