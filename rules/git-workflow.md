# git-workflow — Git 工作流规范

## 适用范围

所有代码提交。

## Commit 粒度

**基本单位是一个 task（代码级工作单元）**。

- 每个 task 完成后，整理为一个正式 commit
- task 开发过程中可提交临时快照，task 完成前使用 `git rebase -i` 整理为单一 atomic commit
- 禁止一个 commit 包含多个 task 的变更
- 禁止多个 task 不 commit 攒在一起

**atomic commit 验证标准**：该 commit 独立应用后，代码可编译、相关单元测试通过。

**为什么以 task 为粒度**：
- 与代码评审的粒度对齐——评审的是单个 task 的变更
- 保持对外 commit 历史简洁，同时允许开发过程中频繁快照
- 每个 commit 对应一条可独立验证的变更单元

## Conventional Commits

提交信息格式：

```
<type>[(<scope>)]: <subject>

<body>

[Refs: <proposal-name>/<task-id>]
```

**type**：
- `feat`: 新功能
- `fix`: Bug 修复
- `docs`: 文档变更
- `style`: 不影响代码含义的格式修改
- `refactor`: 既不修复 bug 也不添加功能的代码变更
- `test`: 测试相关
- `chore`: 构建过程或辅助工具的变动

**scope**（可选）：
- 仓库职责单一、或本次变更范围不言自明时，省略 scope
- 单仓库多模块时，用模块/组件名标识影响范围，如 `wal`、`metadata`、`network`
- 一次提交涉及多个模块时，优先拆分为多个单一模块的 commit；必须一起提交时，用逗号分隔，如 `wal,recovery`

**subject**：
- 使用祈使句，现在时
- 首字母小写
- 末尾不加句号
- 不超过 25 个汉字（或等效显示宽度）

**body**（必填）：
- 描述变更动机（why）和与之前行为的差异（what）
- 按段落组织，段落间空行分隔
- 内容简洁扼要，不限制字数与单行长度

**Refs**（可选）：
- 走 OpenSpec 流程时，关联 proposal 与 task，如 `Refs: storage-wal-impl/step-2`
- 日常维护、文档修正等未绑定 proposal/task 的提交，可省略

**示例**：

```
feat: 为 WAL 追加记录添加 CRC32 校验

实现预写日志追加操作，并对记录头和负载计算 CRC32 校验和，以在读取时检测数据损坏。

此前 WAL 记录没有完整性校验，静默损坏会传播到恢复逻辑。

Refs: storage-wal-impl/step-2
```

```
fix(wal): 修复日志切换时的边界计算错误

原实现以当前段剩余空间判断是否需要切换，但未考虑记录头部长度，导致最后一条记录被拆分到两个段。现在在计算剩余空间时包含记录头部，避免跨段拆分。

Refs: storage-wal-impl/step-4
```

## 分支策略

### 分支类型

| 分支 | 用途 | 从哪切出 | 合并到哪 | 生命周期 |
|------|------|---------|---------|---------|
| `main` | 主干 | — | — | 永久 |
| `feat/<proposal>` | 特性开发分支；从目标分支切出并合并回目标分支 | `main` 或 `release/<version>` | 同切出分支 | 合并后由平台或用户删除 |
| `fix/<issue>` | 修复分支；从目标分支切出并合并回目标分支 | `main` 或 `release/<version>` | 同切出分支 | 合并后由平台或用户删除 |
| `release/<version>` | 版本发布分支，接收该版本特性开发与补丁 | `main` | 不直接合并回 `main` | 版本停止维护后由用户删除 |

### 通用规则

- agent 不检查目标分支是否受平台保护，统一按本规范执行提交；推送被平台拦截时由用户处理

### 默认流程（推荐）

- 从目标分支（通常为 `main`，版本相关时为 `release/<version>`）切出 `feat/<proposal>` 或 `fix/<issue>`
- 在该分支上完成单一 proposal / issue 的所有 task
- 完成后创建 PR/MR 回目标分支，由人工审核后在平台触发合并

### 版本发布分支流程

- 版本发布前，从 `main` 的当前稳定点切出 `release/<version>`
- `release/<version>` 用于接收该版本的特性开发与补丁修复，不直接合并回 `main`
- 为该版本新增特性或修复 bug 时，从对应的 `release/<version>` 切出 `feat/<proposal>` 或 `fix/<issue>`
- 开发完成后，创建 PR/MR 合并回 `release/<version>`，由人工审核后在平台触发合并
- 除非用户明确说明不需要，否则应将合并到 `release/<version>` 的变更同步到 `main`：优先 cherry-pick；无法 cherry-pick 时，在 `main` 上单独实现并关联同一 proposal/issue
- 版本停止维护后，对应的 `release/<version>` 分支由用户删除；agent 可协助

## worktree 规范

### 目录与分支映射

- worktree 目录统一放在 `.claude/worktrees/`，目录名对应 `wt-<proposal>`
- 每个 worktree 内 checkout 该 proposal 的开发分支（通常为 `feat/<proposal>`）
- worktree 内开发在该分支上进行；完成后，由 `/df:finish-worktree` 收尾流程处理，默认创建 PR 由人工审核后合并并清理 worktree；用户明确要求本地合并时除外

### 并行开发规则

- **默认粒度是 proposal**：一个 proposal 使用一个 worktree
- 单个 proposal 内无冲突的多 task 并行可在同一 worktree 内完成
- 多个 proposal 并行开发时，每个 proposal 一个独立 worktree
- 禁止在 worktree 内直接操作基线分支（如 `main` 或 `release/<version>`）；该分支只读，仅用于 rebase 基准

### 清理

- worktree 对应 proposal 完成并合并后，执行 `/df:finish-worktree` 清理；未使用该命令时，由 agent 在用户确认后删除 worktree 目录并移除已合并的本地分支
- 超过 30 天无活动且未关联未合并分支的 worktree 视为废弃，应在用户确认后由 agent 清理；agent 不得主动删除

## 检查清单

### 提交前

- [ ] 一个 commit 只包含一个 task 的变更？
- [ ] commit message 格式符合 Conventional Commits？
- [ ] 已确认该 commit 独立应用后代码可编译？
- [ ] 已确认该 commit 独立应用后相关单元测试通过？
- [ ] 临时快照已用 `git rebase -i` 整理为单一 atomic commit？

### worktree 管理

- [ ] worktree 目录在 `.claude/worktrees/` 下？
- [ ] worktree 内 checkout 的是当前 proposal 的开发分支（通常为 `feat/<proposal>`）？
- [ ] worktree 内未直接修改基线分支（如 `main` / `release/<version>`）？
- [ ] 已使用 `/df:finish-worktree` 或在用户确认后清理完成合并的 worktree？
- [ ] 废弃 worktree 已在用户确认后清理？

### 版本分支变更

- [ ] 分支从对应的 `release/<version>` 切出？
- [ ] 已创建 PR/MR 回对应的 `release/<version>`？
- [ ] 该变更已同步到 `main`（cherry-pick 或单独实现）？
- [ ] 已运行该版本对应的全量测试并通过？
