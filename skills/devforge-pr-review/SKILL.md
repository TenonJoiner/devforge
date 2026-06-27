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
---

# devforge-pr-review — PR/MR 代码评审

## 概述

本 skill 对 GitHub Pull Request 或 GitLab Merge Request 执行评审，包括：
- **MR 元数据检查**：大小、描述、标题等 MR 自身属性
- **代码评审入口**：调用 `devforge-code-review` 完成 diff 级代码评审
- **MR 级结论合成**：结合元数据和代码评审结果，输出最终结论

**两种运行模式**：
- **手动模式**：评审人员指定 PR/MR 链接，或自动检测当前 git 分支对应的 PR/MR，AI 输出结构化评审报告。
- **CI 模式**：CI pipeline 自动调用，AI 将评审结论以单条总结评论形式贴回 PR/MR 页面，并输出 JSON 结果供 CI 判断是否阻塞合并。

**与 `devforge-code-review` 的关系**：
- `devforge-code-review` 是通用代码评审 skill，负责代码/脚本/配置文件的五维度评审。
- `devforge-pr-review` 是 MR 入口 skill，负责平台交互、MR 上下文准备、MR 元数据检查、文件类型分流：
  - 含代码类文件时调用 `devforge-code-review`
  - 纯文档变更时派遣 `product-reviewer` agent
  - 最后合成 MR 级报告。

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
| MR 大小 | additions + deletions > 1000 行 → 过大 | 输出 INFORMATIONAL 提示，建议拆分 |
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
  - 若只有文档类文件（如 `.md`、`.txt`、`.rst`、`.adoc` 等）→ 进入第 4 阶段分支 B，由 `product-reviewer` agent 执行文档评审
- 上下文不足 → 评审 agent 自行标注并建议作者补充信息。

### 第 4 阶段：变更内容评审

根据步骤 4 的文件类型分流结果，选择对应评审分支。

#### 分支 A：代码/脚本/配置文件评审

**步骤 5a：调用 `devforge-code-review` skill**

使用已计算的 diff 范围调用 `devforge-code-review`，将中间评审报告写到 MR 专属路径：

```
/df:code-review --diff-range "git diff origin/<base_branch>...<head_branch>" --report-output-path ai-review-report-<mr_number>.md
```

主会话通过 Skill 工具加载 `devforge-code-review`，传入 `diff-range` 和 `report-output-path` 参数。代码评审由 `devforge-code-review` 独立完成，pr-review 不干预其内部 agent 调度。

#### 分支 B：纯文档变更评审

**步骤 5b：派遣 `product-reviewer` agent**

对纯文档 MR 进行深入文档评审，注入字段：

| 字段 | 说明 | 示例 |
|------|------|------|
| `任务模式` | 文档变更评审 | `文档变更评审` |
| `diff_range` | 已计算的 diff 命令 | `git diff origin/main...HEAD` |
| `report_output_path` | 评审报告写入路径 | `ai-review-report-<mr_number>.md` |

评审维度：
- **完整性**：变更是否说明了背景、目的、影响范围
- **准确性**：技术描述、命令、参数、链接是否正确
- **一致性**：术语、命名是否与项目现有文档保持一致
- **可读性**：结构是否清晰，段落是否易于理解
- **关联性**：是否关联了相关 issue、PR、设计文档

输出要求：按 CRITICAL / HIGH / MEDIUM / LOW 分级，每个问题包含文件路径、问题说明、改进建议。

**步骤 6：读取中间评审报告**

无论是从 `devforge-code-review` 还是 `product-reviewer` 产出，均从**项目根目录下的 `ai-review-report-<mr_number>.md`**（即 `--report-output-path` 指定的路径）提取：
- 完整问题统计：CRITICAL / HIGH / MEDIUM / LOW 数量，用于生成外层摘要
- 完整报告内容：折叠在 `<details>` 块中，不重复出现在外层摘要里

**注意**：`/tmp` 下的 `code-review-*-d*.md` 等文件是 `devforge-code-review` 的 subagent 中间产物，**不要用于生成 MR 评论**，应被忽略。

若 `ai-review-report-<mr_number>.md` 不存在或为空，报错并停止。

### 第 5 阶段：结论合成与输出

**步骤 7：合成 MR 级最终结论（verdict）**

综合 MR 元数据检查结果和 `ai-review-report-<mr_number>.md` 中的问题统计，给出最终结论：

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
  - `ai-review-report-<mr_number>.md` 摘要（问题统计 + 关键发现概述）
  - 最终结论（verdict）

- **CI 模式（`ci` 为 true）**：
  1. 生成 MR 变更分类统计：
     - 使用 `git diff --numstat <diff_range>` 获取本次 diff 每个文件的增删行数。
     - 按扩展名分类：
       - **文档**：`.md`、`.txt`、`.rst`、`.adoc`
       - **代码**：其余源码/脚本/配置文件（如 `.c`、`.go`、`.py`、`.sh`、`.yml`、`.json` 等）
       - **其他**：不属于以上两类的文件
     - 汇总写入摘要表格：总文件数、总行数（+/-）、代码/文档/其他分类文件数及行数。
  2. 从 `ai-review-report-<mr_number>.md` 生成总结评论正文 `ai-review-comment-<mr_number>.md`：
     - **外层严格只放摘要**：MR 标题、变更统计表格、评审结论、问题计数表。
     - 完整报告的问题详情**必须**放在 `<details>`/`<summary>` 折叠块内，不能散落在外层。
     - 摘要格式固定如下（计数必须与完整报告一致）：

       ```markdown
       ## MR 评审摘要：<MR 标题>

       本次 MR 变更统计如下：

       | 分类 | 文件数 | 新增行数 | 删除行数 |
       |---|---|---|---|
       | 代码 | Nc | +Xc | -Yc |
       | 文档 | Nd | +Xd | -Yd |
       | 其他 | No | +Xo | -Yo |
       | **总计** | **N** | **+X** | **-Y** |

       **评审结论：** 请求修改（REQUEST_CHANGES）

       | 级别 | 数量 | 语义 |
       |---|---|---|
       | CRITICAL | N | 阻塞合并 |
       | HIGH | N | 强烈建议修改 |
       | MEDIUM | N | 优化建议 |
       | LOW | N | 轻微问题 / 变体分析 |

       <details>
       <summary>展开查看完整评审报告</summary>

       [ai-review-report-<mr_number>.md 完整内容]

       </details>
       ```
  3. 通过平台 CLI 将总结评论贴到 PR/MR 页面：
     ```bash
     # GitHub
     gh pr comment <number> --body-file ai-review-comment-<mr_number>.md

     # GitLab
     glab mr note <number> -m "$(cat ai-review-comment-<mr_number>.md)"
     ```
  4. 输出 JSON 结果到标准输出，供 CI 解析并判断是否阻塞合并：
     ```json
     {
       "verdict": "REQUEST_CHANGES",
       "platform": "gitlab",
       "mr_number": 123,
       "critical": 0,
       "high": 1,
       "medium": 2,
       "low": 1,
       "report_path": "ai-review-report-<mr_number>.md",
       "comment_posted": true
     }
     ```
  5. 退出码：
     - `0`：最终结论（verdict）为 APPROVE 或 COMMENT
     - `1`：最终结论（verdict）为 REQUEST_CHANGES

## CI 模式评论策略

- **单条总结评论 + 折叠完整报告**：外层摘要包含 MR 标题、变更分类统计表格、评审结论与各级别计数；完整报告用 `<details>`/`<summary>` 折叠块展示，不重复出现在摘要中。
- **每次发新评论**：每次 CI 运行都发一条新评论，不更新已有评论（第一期简化实现）。
- `ai-review-report-<mr_number>.md` 同时作为 CI artifact 保存。

## 关联

- **相关 Skill**: `devforge-code-review`
- **相关 Agent**: `code-reviewer`（通过 `devforge-code-review` 间接使用）、`product-reviewer`
- **相关 Rules**: `coding-style`, `testing`
- **相关 Hooks**: 无
