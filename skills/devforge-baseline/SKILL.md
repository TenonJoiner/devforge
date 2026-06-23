---
name: devforge-baseline
description: OpenSpec change 文档基线化归档 skill。检查 review.md 中 Tech Leader 决策，将核心文档拷贝到基线仓库的 baseline/<version>/<repo>/<change>/ 目录并提交。
allowed-tools: [Read, Bash, Glob, Grep]
---

# devforge-baseline — 文档基线化归档

## 概述

本 skill 负责把已通过 Tech Leader 评审的 OpenSpec change 文档归档到独立基线仓库。

归档前提：change-dir 下的 `review.md` 中 Tech Leader 最终决策为 `PASS` 或 `PASS WITH CONDITIONS`。

归档动作：将 change 核心文档拷贝到基线仓库的 `baseline/<version>/<repo-name>/<change-name>/` 目录，执行 git commit 并 push。

## 参数

- `--change-dir <path>`：change 工作目录，无参数时默认当前工作目录
- `--version <version>`：基线版本号，必填
- `--repo-url <url>`：基线仓库 git URL，必填

## 工作目录约定

- **change-dir**：被归档的 OpenSpec change 目录，预期包含 `proposal.md`、`specs/`、`design.md`、`review.md`
- **本地基线仓库根目录**：`~/.local/share/devforge/baseline-repos/<repo-dir>/`
  - `<repo-dir>` 由 `--repo-url` 派生，优先使用 URL 最后一级去掉 `.git` 后的名称；冲突时用 16 位哈希后缀
- **归档目标目录**：`<本地基线仓库根目录>/baseline/<version>/<repo-name>/<change-name>/`

## 前置检查

1. 验证 `--version` 和 `--repo-url` 已提供，缺失则报错停止。
2. 验证 change-dir 下存在 `review.md`，不存在则停止。
3. 读取 `review.md` 的「Tech Leader 最终决策」区域：
   - 决策为 `PASS` 或 `PASS WITH CONDITIONS` → 继续
   - 决策为 `REJECT`、为空或未填写 → 停止并提示：「review.md 中 Tech Leader 最终决策未通过，禁止基线化归档」
4. 验证 change-dir 下至少存在 `proposal.md`、`specs/`、`design.md` 中的核心文档；缺失时停止并提示补充。

## 执行流程

### [1] 解析名称

- **repo-name**：
  1. 在 change-dir 的 git 仓库中执行 `git remote get-url origin`，解析 URL 最后一级去掉 `.git` 作为 repo-name
  2. 无 git 仓库或 remote 不存在时，使用 change-dir 所在 git 仓库根目录名
  3. 仍无法解析时使用当前工作目录名
- **change-name**：取 change-dir 路径的最后一级目录名

### [2] 准备本地基线仓库

- 计算本地基线仓库路径：`~/.local/share/devforge/baseline-repos/<repo-dir>/`
- 目录不存在 → `git clone <repo-url> <本地路径>`
- 目录已存在 → `git -C <本地路径> pull --ff-only`
- clone/pull 失败 → 停止并报告错误

### [3] 拷贝核心文档

- 在本地基线仓库中创建目录：`baseline/<version>/<repo-name>/<change-name>/`
- 从 change-dir 拷贝以下核心文档：
  - `proposal.md`
  - `design.md`
  - `specs/` 目录及其下所有 `.md` 文件
- 目标目录已存在时停止并提示：「归档目标已存在，请确认是否覆盖或更换 version」

### [4] 提交并推送

- `git -C <本地路径> add baseline/<version>/<repo-name>/<change-name>/`
- `git -C <本地路径> commit -m "baseline: archive <change-name> to baseline/<version>/<repo-name>/<change-name>"`
- `git -C <本地路径> push`
- 任一步骤失败 → 停止并报告错误

### [5] 完成汇报

- 输出归档目标路径
- 输出 commit hash
- 提示用户检查基线仓库远程状态

## 失败处理

- 任一步骤失败后立即停止，不向基线仓库写入不完整状态
- 若 commit 成功但 push 失败，提示用户手动在本地基线仓库执行 push

## 与其他 skill 的协作

- **上游**：`devforge-spec-review` 生成 review.md，Tech Leader 填写最终决策
- **下游**：无；归档后 change 进入冻结状态
