---
name: devforge-pr-review
description: 对 GitHub Pull Request 或 GitLab Merge Request 执行代码评审。手动模式输出结构化报告；CI 模式自动将结论以评论形式贴回 PR/MR 页面，并输出 JSON 结果供 CI 判断是否阻塞合并。
allowed-tools: [Read, Write, Bash, Grep, Agent, Skill]
parameters:
  - name: pr-link
    description: PR/MR 链接，省略时自动检测当前分支
    required: false
  - name: ci
    description: CI 模式，非交互运行并自动发帖
    required: false
    default: false
  - name: only
    description: 仅运行指定下游检查，逗号分隔（code-review / lint / log-audit），用于调试 pr-review 或下游 skill 时加速。默认空表示全部运行
    required: false
---

# devforge-pr-review — PR/MR 代码评审

## 概述

本 skill 对 GitHub Pull Request 或 GitLab Merge Request 执行评审，包括：
- **MR 元数据检查**：大小、描述、标题等 MR 自身属性
- **代码评审入口**：调用 `devforge-code-review` 完成 diff 级代码评审
- **Lint 检查入口**：调用 `devforge-lint-check` 完成编译检查与 lint 分析
- **日志审计入口**：调用 `devforge-log-audit` 完成 diff 级日志审计（级别合理性 + 打印频率）
- **MR 级结论合成**：结合元数据、代码评审、lint 检查和日志审计结果，输出最终结论

**快速调试**：`--only` 参数可指定仅运行 code-review / lint / log-audit 之一或组合（逗号分隔），跳过其余下游检查以加速调试。默认空表示全部运行。

**两种运行模式**：
- **手动模式**：评审人员指定 PR/MR 链接，或自动检测当前 git 分支对应的 PR/MR，AI 输出结构化评审报告。
- **CI 模式**：CI pipeline 自动调用，AI 将评审结论以单条总结评论形式贴回 PR/MR 页面，并输出 JSON 结果供 CI 判断是否阻塞合并。

**与下游 skill 的关系**：
- `devforge-code-review` 是通用代码评审 skill，负责代码/脚本/配置文件的五维度评审。
- `devforge-lint-check` 是编译检查与 lint 分析 skill，负责编译通过验证与 lint 告警分析。
- `devforge-log-audit` 是日志审计 skill，负责 diff 内日志语句的级别合理性与打印频率两维度审计。
- `devforge-pr-review` 是 MR 入口 skill，负责平台交互、MR 上下文准备、MR 元数据检查、文件类型分流：
  - 含代码类文件时并行调用 `devforge-code-review`、`devforge-lint-check` 和 `devforge-log-audit`
  - 纯文档变更时派遣 `devforge:product-reviewer` agent（不跑 code-review、lint 和日志审计）
  - 最后合并结果，合成 MR 级报告。

## 何时使用

- 评审人员拿到 PR/MR 链接，需要快速 AI 预审。
- 批量变更完成后，在合并前做最终代码质量把关。
- CI pipeline 中在 PR/MR 创建/更新后自动执行质量门禁。

## 工作流程

### 第 1 阶段：平台检测与 MR 信息获取

**步骤 1：解析 `pr-link` 或自动检测当前 PR/MR**

- 若用户提供了 `pr-link`，从 URL 中提取平台、owner、repo、number。
- 若未提供 `pr-link`，使用当前分支自动检测：
  - GitHub：`gh pr view --json number,url,baseRefName,headRefName,title,body`
  - GitLab：`glab mr view -F json`
- 若 `gh`/`glab` 未安装或认证失败，报错并停止。

**步骤 2：获取 MR 元数据**

根据平台调用对应 CLI：

```bash
# GitHub
gh pr view <number> --json number,title,body,baseRefName,headRefName,changedFiles,additions,deletions

# GitLab
glab mr view <number> -F json
```

提取字段：number、title、body、base_branch、head_branch、changed_files、additions、deletions。

### 第 2 阶段：MR 非代码内容检查（MR 元数据检查）

主会话基于上一步获取的 MR 元数据执行轻量检查，结果作为结论合成的输入：

| 检查项 | 阈值 | 未通过时的处理 |
|--------|------|---------------|
| 描述非空 | body 为空或 < 50 字符 → 不合格 | 输出 MEDIUM 问题 |
| 标题规范 | 标题为空或仅为 "fix bug" 等无信息标题 → 不合格 | 输出 MEDIUM 问题 |

这些检查不阻塞代码评审，但会影响最终结论（verdict）。例如描述不合格时，最终结论从 APPROVE 降级为 COMMENT。

### 第 3 阶段：Diff 范围准备

**步骤 3：计算 diff 范围**

优先顺序：

1. **GitLab CI 环境变量**：若 `CI_MERGE_REQUEST_TARGET_BRANCH_NAME` 存在（GitLab MR pipeline 自动注入），使用：
   ```bash
   git diff origin/${CI_MERGE_REQUEST_TARGET_BRANCH_NAME}...HEAD
   ```
2. **GitHub Actions 环境变量**：若 `GITHUB_BASE_REF` 存在（GitHub PR workflow 自动注入），使用：
   ```bash
   git diff origin/${GITHUB_BASE_REF}...HEAD
   ```
3. **手动模式**：使用第 1 阶段步骤 2 获取的 `base_branch`，计算：
   ```bash
   git fetch origin <base_branch> --quiet
   git diff origin/<base_branch>...<head_branch>
   ```

**步骤 4：边界处理与文件类型分流**

- diff 为空 → 输出 "本次 PR/MR 无代码变更需要检视"，最终结论（verdict）= COMMENT，直接结束。
- 分析 diff 中的文件类型：
  - 若存在代码/脚本/配置文件（如 `.go`、`.c`、`.py`、`.sh`、`.yml`、`.json`、`.toml` 等）→ 进入第 4 阶段分支 A，调用 `devforge-code-review`
  - 若只有文档类文件（如 `.md`、`.txt`、`.rst`、`.adoc` 等）→ 进入第 4 阶段分支 B，由 `devforge:product-reviewer` agent 执行文档评审
- 上下文不足 → 评审 agent 自行标注并建议作者补充信息。

### 第 3.5 阶段：分支就绪（Worktree）

确保下游 skill 能读到 MR 源分支的正确源码。

**步骤 4.5：检测当前分支**

```bash
WORKTREE_PATH=""
current_branch=$(git branch --show-current)
```

- 若 `$current_branch == <head_branch>`：`WORKTREE_PATH` 保持空字符串，跳过 worktree 创建，直接进入第 4 阶段
- 若不同：创建 detached worktree

**步骤 4.6：创建 Worktree**（仅分支不匹配时）

```bash
WORKTREE_PATH="/tmp/pr-review-worktree-<mr_number>"
ORIGINAL_DIR=$(pwd)
git worktree add --detach "$WORKTREE_PATH" "origin/<head_branch>"
```

**主会话保持在 `$ORIGINAL_DIR`（原始仓库目录），不进入 worktree。**worktree 仅作为 MR 源码的只读目录供下游 skill 通过 `--worktree-path` 访问。

路径职责：
- **CWD**：基础设施——CLAUDE.md、规则文件、lint 脚本及其规则配置（`.clang-tidy`、`.golangci.yml` 等）。调用方应从基础设施最新（通常为 main）的分支发起 pr-review
- **`--worktree-path`**：MR 源码——待审查/待检查的代码与构建脚本（Makefile、CMakeLists.txt 等）

若 worktree 已存在（上次残留），先 `rm -rf "$WORKTREE_PATH" && git worktree prune` 再重新创建。

### 第 4 阶段：变更内容评审

根据步骤 4 的文件类型分流结果，选择对应评审分支。

#### 分支 A：代码/脚本/配置文件评审

**`--only` 门控**：若 `--only` 已提供，仅执行其指定的下游 skill，其余跳过。例如 `--only lint` 仅执行步骤 5b，跳过 5a 和 5c。`--only` 未提供时三步全部执行。

**步骤 5a：调用 `devforge-code-review` skill**（`--only` 未提供或包含 `code-review` 时执行）

使用已计算的 diff 范围调用 `devforge-code-review`，将中间评审报告写到 MR 专属路径：

```
/df:code-review --diff-range "git diff origin/<base_branch>...<head_branch>" --report-output-path /tmp/code-review-report-<mr_number>.md --worktree-path "$WORKTREE_PATH"
```

主会话通过 Skill 工具调用 `devforge-code-review`。**严禁使用 Agent 工具直接派发 agent 替代 Skill 工具调用**。pr-review 不干预 `devforge-code-review` 的内部 agent 调度。

**步骤 5b：调用 `devforge-lint-check` skill（与 5a 并行）**（`--only` 未提供或包含 `lint` 时执行）

对本次 MR 执行编译检查与 lint 分析。将已计算的 diff 范围传递给 `devforge-lint-check`，报告写入独立路径：

```
/df:lint --diff-range "git diff origin/<base_branch>...<head_branch>" --report-output-path /tmp/lint-report-<mr_number>.md --worktree-path "$WORKTREE_PATH"
```

主会话通过 Skill 工具调用 `devforge-lint-check`。**严禁使用 Agent 工具直接派发 agent 替代 Skill 工具调用**。不传 `autofix`（默认 false），PR review 场景仅检测不修复。pr-review 不干预 `devforge-lint-check` 的内部 agent 调度。

**步骤 5c：调用 `devforge-log-audit` skill（与 5a、5b 并行）**（`--only` 未提供或包含 `log-audit` 时执行）

对本次 diff 范围内的日志语句执行两维度审计。使用已计算的 diff 范围调用 `devforge-log-audit`，将审计报告写入独立路径：

```
/df:log-audit --diff-range "git diff origin/<base_branch>...<head_branch>" --report-output-path /tmp/log-audit-<mr_number>.md --worktree-path "$WORKTREE_PATH"
```

主会话通过 Skill 工具调用 `devforge-log-audit`。**严禁使用 Agent 工具直接派发 agent 替代 Skill 工具调用**。无需 `--log-dir`——CI 场景下频率维度自动跳过，仅审级别合理性。pr-review 不干预 `devforge-log-audit` 的内部 agent 调度。

#### 分支 B：纯文档变更评审

**步骤 5d：派遣 `devforge:product-reviewer` agent**

对纯文档 MR 进行深入文档评审，注入字段：

| 字段 | 说明 | 示例 |
|------|------|------|
| `任务模式` | 文档变更评审 | `文档变更评审` |
| `diff_range` | 已计算的 diff 命令 | `git diff origin/main...HEAD` |
| `report_output_path` | 评审报告写入路径 | `/tmp/doc-review-report-<mr_number>.md` |

评审维度：
- **完整性**：变更是否说明了背景、目的、影响范围
- **准确性**：技术描述、命令、参数、链接是否正确
- **一致性**：术语、命名是否与项目现有文档保持一致
- **可读性**：结构是否清晰，段落是否易于理解
- **关联性**：是否关联了相关 issue、PR、设计文档

输出要求：按 CRITICAL / HIGH / MEDIUM / LOW 分级，每个问题包含文件路径、问题说明、改进建议。

**步骤 6：读取并合并中间评审报告**

pr-review 的报告产出取决于分支：

**分支 A（含代码文件）**：最多三份报告

| 来源 | 路径 | 触发条件 |
|------|------|---------|
| 代码评审 | `/tmp/code-review-report-<mr_number>.md` | 分支 A |
| Lint 检查 | `/tmp/lint-report-<mr_number>.md` | 分支 A |
| 日志审计 | `/tmp/log-audit-<mr_number>.md` | 分支 A |

**分支 B（纯文档）**：仅一份报告

| 来源 | 路径 | 触发条件 |
|------|------|---------|
| 文档评审 | `/tmp/doc-review-report-<mr_number>.md` | 分支 B |

分支 B 无代码评审、lint 和日志审计报告。

**步骤 6.0：报告格式验证闸门**

在提取报告内容之前，主会话必须验证每份报告的文件格式符合下游 skill 的输出规范。**此步为硬门控——任一份报告格式不符则中止，不得继续合并。**

| 报告 | 验证项 | 不合规信号 |
|------|--------|-----------|
| 代码评审 | 按 CRITICAL/HIGH/MEDIUM/LOW 四级编排，非 D1-D5 维度结构 | 报告中出现 `D1:` `D2:` `D3:` `D4:` `D5:` 章节标题、维度内独立编号、或"同类缺陷扫描"等中间产物特征 |
| Lint 检查 | 按模板自检清单通过后的格式 | 报告中出现"静态编码规范检查""逐规则审查"等非 L1/L2 章节、或级别字段使用工具原始级别（P0-P4 等） |
| 日志审计 | 按模板自检清单通过后的格式 | 报告中出现"待确认""疑似"等未完成结论 |

- 通过 → 进入"从各报告提取"
- 不通过 → **驳回**：报告格式不符说明下游 skill 的流水线未正确执行（通常是因为 Skill 工具被绕过、改用 Agent 工具直接派发 agent）。**不得**手动修正报告或直接提取内容——必须回到步骤 5a/5b/5c，通过 Skill 工具重新调用对应下游 skill，让它完整执行内部流水线后重新生成报告

从各报告提取：
- 各份报告的问题统计：CRITICAL / HIGH / MEDIUM / LOW 数量
- 各份报告的完整内容：分别折叠在独立的 `<details>` 块中

**合并规则**：
- 各级别计数为各份报告对应级别之和
- 三份报告在 CI 评论中各自一个 `<details>` 折叠块，代码评审在前、lint 检查居中、日志审计在后
- 任一报告不存在或为空，对应折叠块省略，不计入统计

**注意**：`/tmp` 下的 `code-review-*-d*.md` 等文件是 `devforge-code-review` 的 subagent 中间产物，**不要用于生成 MR 评论**，应被忽略。

若预期路径上的报告均不存在或为空，报错并停止。

### 第 5 阶段：结论合成与输出

**步骤 7：合成 MR 级最终结论（verdict）**

综合 MR 元数据检查结果和步骤 6 合并后的问题统计，给出最终结论：

| 最终结论（verdict） | 条件 | 含义 |
|------|------|------|
| **APPROVE** | 无 CRITICAL/HIGH，元数据检查全部通过 | 批准合并 |
| **COMMENT** | 无 CRITICAL/HIGH，但存在元数据问题或少量 MEDIUM/LOW | 仅评论，不阻止合并 |
| **REQUEST_CHANGES** | 存在 CRITICAL 或 HIGH | 请求修改，阻塞合并 |

**步骤 8：按模式输出**

根据 `ci` 参数二选一执行：

- **手动模式（`ci` 未设置或 false）**：
  输出结构化评审报告到会话，包含：
  - MR 元数据摘要（变更文件数、+/- 行数、代码/文档/其他分类统计）
  - MR 元数据检查结果
  - 步骤 6 合并后的问题统计与关键发现概述（含代码评审、lint 检查与日志审计）
  - 最终结论（verdict）

- **CI 模式（`ci` 为 true）**：
  
  **步骤 8a：生成评论正文并自检**
  
  1. 读取评论格式模板。模板定义了评论正文的固定结构、占位符替换规则和自检清单。**必须先读取模板再生成评论**，禁止凭记忆或推测格式。

     模板查找（按优先级）：
     - `<skill_base_dir>/templates/pr-review-comment.md`（skill 基础目录由 skill launch 时的 base_dir 确定）
     - `find ~/.claude/plugins/ -name pr-review-comment.md`（兜底定位）
     - 仍未找到 → 报错终止，报两个候选路径供人工确认
  
  2. 生成 MR 变更分类统计：
     - 使用 `git diff --numstat <diff_range>` 获取本次 diff 每个文件的增删行数。
     - 按扩展名分类：
       - **文档**：`.md`、`.txt`、`.rst`、`.adoc`
       - **代码**：其余源码/脚本/配置文件（如 `.c`、`.go`、`.py`、`.sh`、`.yml`、`.json` 等）
       - **其他**：不属于以上两类的文件
     - 汇总填入模板的变更统计表格。
  
  3. 按步骤 1 读取的模板严格填充各占位符，写入 `/tmp/pr-review-comment-<mr_number>.md`：
     - 外层摘要只展示数量，不展示具体问题的标题、文件位置或描述
     - 中间报告的完整内容**原样粘贴**进对应 `<details>` 块，禁止概括、删减、改写、只摘录部分
     - 分支 A：代码评审折叠块在前，lint 检查居中，日志审计折叠块在后；问题计数为三份报告之和
     - 分支 B：仅文档评审折叠块；问题计数为文档评审报告的数量
  
  4. **自检闸门**：逐项执行模板末尾的自检清单。任一项不通过 → 修正文件后重新自检，禁止跳过自检直接发送。
  
  **步骤 8b：发送评论**
  
  1. CLI 命令**白名单**——只允许以下命令之一，**单次调用**：
     ```bash
     # GitHub
     gh pr comment <number> --body-file /tmp/pr-review-comment-<mr_number>.md
     
     # GitLab
     glab mr note create <number> < /tmp/pr-review-comment-<mr_number>.md
     ```
     **严禁使用** `gh pr review`（评论会贴到代码行而非评论区）、`gh api`（可绕过约束拆分评论）、或任何其他评论方式。**严禁多次调用**——一次 MR 评审只产生一条评论。违者会导致报告拆分、格式丢失、或评论出现在错误位置。
  
  2. 执行命令，验证 CLI 返回成功。仅此一次调用，不追加、不修改。
  
  **步骤 8c：输出 JSON 与退出码**
  
  1. 输出 JSON 结果到标准输出，供 CI 解析并判断是否阻塞合并：
     ```json
     {
       "verdict": "REQUEST_CHANGES",
       "platform": "gitlab",
       "mr_number": 123,
       "critical": 0,
       "high": 1,
       "medium": 2,
       "low": 1,
       "code_review_report_path": "/tmp/code-review-report-<mr_number>.md",
       "lint_report_path": "/tmp/lint-report-<mr_number>.md",
       "log_audit_report_path": "/tmp/log-audit-<mr_number>.md",
       "doc_review_report_path": "/tmp/doc-review-report-<mr_number>.md",
       "comment_posted": true
     }
     ```
  
  2. 退出码：
     - `0`：最终结论（verdict）为 APPROVE 或 COMMENT
     - `1`：最终结论（verdict）为 REQUEST_CHANGES

**步骤 9：清理 Worktree**

若第 3.5 阶段创建了 worktree：

```bash
rm -rf "$WORKTREE_PATH"
git worktree prune
```

## CI 模式评论策略

### 评论格式

- **模板驱动**：评论正文严格按照 `templates/pr-review-comment.md` 生成。步骤 8a 必须先读取模板再填充，禁止凭记忆或推测格式。
- **单条总结评论**：外层摘要包含 MR 标题、变更分类统计表格、评审结论与各级别计数；中间报告的完整内容在 `<details>` 折叠块内，禁止露到外层。
- **自检闸门**：评论正文写入文件后，必须执行 `templates/pr-review-comment.md` 末尾的自检清单，全部通过才能进入步骤 8b。
- **每次发新评论**：每次 CI 运行都发一条新评论，不更新已有评论。
- 分支 A：`/tmp/code-review-report-<mr_number>.md`、`/tmp/lint-report-<mr_number>.md`、`/tmp/log-audit-<mr_number>.md` 作为 CI artifact 保存。使用 `--only` 时仅保存被选中 skill 对应的报告。
- 分支 B：`/tmp/doc-review-report-<mr_number>.md` 作为 CI artifact 保存。

### CLI 白名单

只允许以下命令发送评论，**单次调用**：

- GitHub：`gh pr comment <number> --body-file /tmp/pr-review-comment-<mr_number>.md`
- GitLab：`glab mr note create <number> < /tmp/pr-review-comment-<mr_number>.md`

### 反模式（严禁）

| 错误行为 | 后果 | 正确做法 |
|---------|------|---------|
| 使用 `gh pr review` 发评论 | 评论出现在代码行（Changes 页）而非评论区 | 用 `gh pr comment --body-file` |
| 使用 `gh api` 发送 | 可绕过约束，拆分评论或贴错位置 | 用白名单中的命令 |
| 多次调用 CLI 拆成多条评论 | CRITICAL/HIGH/MEDIUM/LOW 各一条，页面混乱 | 一条评论包含所有内容 |
| 外层摘要暴露具体问题 | 评论页面过长，未折叠 | 具体发现全部放在 `<details>` 内 |
| 改写/概括中间报告内容 | 丢失细节，与原始报告不一致 | 原样粘贴完整内容 |
| 跳过自检直接发送 | 格式错误、折叠缺失 | 逐项自检通过后再发 |
| 用 Agent 工具直接派发 agent 替代 Skill 工具调用下游 skill | 绕过 skill 内部流水线（汇总/去重/误报审核），产出中间格式报告（如 D1-D5 维度结构）而非最终报告 | 使用 Skill 工具调用下游 skill，让它完整执行内部流水线 |

## 关联

- **相关 Skill**: `devforge-code-review`、`devforge-lint-check`、`devforge-log-audit`
- **相关 Agent**: `devforge:code-reviewer`（通过 `devforge-code-review` 间接使用）、`devforge:lint-analyst`（通过 `devforge-lint-check` 间接使用）、`devforge:developer`（通过 `devforge-lint-check` autofix 模式间接使用）、`devforge:product-reviewer`、`devforge:log-auditor`（通过 `devforge-log-audit` 间接使用）
- **相关 Rules**: `coding-style`, `testing`
- **相关 Hooks**: 无
