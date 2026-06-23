---
name: devforge-baseline
description: OpenSpec change 文档基线化归档 skill。检查 review.md 中 Tech Leader 决策，将核心文档拷贝到基线仓库的 baseline/<product-version>/<repo>/<change>/ 目录并提交。
allowed-tools: [Read, Write, Bash, Glob, Grep]
---

# devforge-baseline

把已通过 Tech Leader 评审的 OpenSpec change 文档归档到独立基线仓库。

**核心约束**

- 仅当 `review.md` 中 Tech Leader 最终决策为 `PASS` 或 `PASS WITH CONDITIONS` 时才归档。
- 仅使用 `Read` / `Write` / `Bash` / `Glob` / `Grep`。`Write` 仅用于保存用户级配置。
- 任一失败立即停止，不向基线仓库写入不完整状态。

## 1. 获取参数

参数优先级：命令行参数 > 仓库级配置 `.claude/devforge-baseline.yaml` > 用户级配置 `~/.local/share/devforge/baseline-config.yaml` > 交互式询问。

用户级配置在首次运行时自动创建；后续运行读取并提示确认。仓库级配置用于项目特定覆盖。

### change

change 根目录固定为 `openspec/changes/`。

1. 若当前工作目录位于 `openspec/changes/<change-name>/` 下，取当前目录名作为 `<change-name>`，提示：「归档 change '<change-name>'？」，确认则使用，否则要求输入名称。
2. 若当前工作目录不在 change 目录下，列出 `openspec/changes/` 下的子目录供选择，或让用户直接输入 change 名称。
3. 命令行传入 `--change <name>` 时跳过询问，直接使用。

change 完整路径为 `openspec/changes/<change-name>/`。

### repo-url

1. 依次检查命令行参数 `--repo-url`、`.claude/devforge-baseline.yaml` 的 `baseline.repo-url`、`~/.local/share/devforge/baseline-config.yaml` 的 `baseline.repo-url`。
2. 找到有效值 → 提示：「使用基线仓库 `<repo-url>`？（回车确认，或输入新 URL 覆盖）」
3. 未找到 → 询问：「请输入基线仓库 git URL：」
4. 用户输入新值后，保存到 `~/.local/share/devforge/baseline-config.yaml` 的 `baseline.repo-url`。

### version

1. 依次检查命令行参数 `--version`、仓库级配置、用户级配置的 `baseline.active-versions` / `baseline.default-version`。
2. 只有一个活跃版本 → 提示：「归档到 `<version>`？（回车确认，或输入新版本）」
3. 多个活跃版本 → 列出选项：「选择归档版本：1) V2R1C01  2) V2R1C02  3) 输入新版本」
4. 未配置 → 询问：「请输入产品版本（如 V2R1C01）：」
5. 用户输入的新版本追加到用户级配置的 `baseline.active-versions`，并更新 `baseline.default-version`。

### 保存配置

确认后的 `repo-url` 和 `version` 写入 `~/.local/share/devforge/baseline-config.yaml`。`change` 不写入配置。

## 2. 前置检查

1. 确认 `openspec/changes/<change-name>/review.md` 存在；不存在则停止。
2. 读取 `review.md`，定位「Tech Leader 最终决策」：
   - `PASS` 或 `PASS WITH CONDITIONS` → 继续
   - `REJECT`、为空、未填写 → 停止并提示：「review.md 中 Tech Leader 最终决策未通过，禁止基线化归档」
3. 检查 `openspec/changes/<change-name>/` 下是否存在 `proposal.md`、`design.md`、`specs/`。列出缺失项并提示用户；若三项不全，询问：「缺失 <list>，是否继续归档？」用户确认则继续，否则停止。

## 3. 解析名称

- **repo-name**：
  1. 在 `openspec/changes/<change-name>/` 下执行 `git remote get-url origin`，解析 URL 最后一级去掉 `.git`
  2. 无 remote 时，执行 `git rev-parse --show-toplevel` 获取项目根目录，使用根目录名
  3. 仍无法解析时使用当前工作目录名
- **change-name**：由 `--change` 参数或交互确认得到

## 4. 准备本地基线仓库

- 计算本地路径：`~/.local/share/devforge/baseline-repos/<repo-dir>/`
  - `repo-dir` 由 `--repo-url` 派生，取 URL 最后一级去掉 `.git` 后的名称
- 目录不存在 → `git clone <repo-url> <本地路径>`
- 目录已存在 → `git -C <本地路径> pull --ff-only`
- clone/pull 失败 → 停止并报告错误

## 5. 拷贝核心文档

- 目标目录：`<本地基线仓库根目录>/baseline/<version>/<repo-name>/<change-name>/`
- 目标目录已存在 → 停止并提示：「归档目标已存在，请确认是否覆盖或更换 version」
- 从 `openspec/changes/<change-name>/` 拷贝：
  - `proposal.md`
  - `design.md`
  - `specs/` 目录及其下所有 `.md` 文件

## 6. 提交并推送

1. `git -C <本地路径> add baseline/<version>/<repo-name>/<change-name>/`
2. 执行 `git -C <本地路径> diff --cached` 分析本次归档的变更内容，生成简洁变更概述。
3. 构造 commit message 并提交：
   ```
   baseline: archive <change-name> to <version>/<repo-name>/<change-name>

   Change: <proposal-title>
   Review decision: <decision>
   Source repo: <repo-name>

   Summary:
   <变更概述>
   ```
   - `<proposal-title>`：从 `openspec/changes/<change-name>/proposal.md` 第一行读取
   - `<decision>`：从 `review.md` 中读取的 Tech Leader 最终决策
   - `<变更概述>`：基于 `git diff --cached` 输出提炼，例如新增/修改/删除的文件及核心差异点
4. `git -C <本地路径> push`
5. 任一步骤失败 → 停止并报告错误；若 commit 成功但 push 失败，提示用户在本地基线仓库手动执行 push

## 7. 完成汇报

输出：

- 归档目标路径
- commit hash
- 提示用户检查基线仓库远程状态
