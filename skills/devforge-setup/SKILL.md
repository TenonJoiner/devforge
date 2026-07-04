---
name: devforge-setup
description: 一键检测并安装 DevForge plugin 运行所需的全部系统工具。检测 Linux 发行版，扫描缺失的 CLI 工具，生成报告，用户确认后自动安装。
allowed-tools: [Read, Bash, AskUserQuestion]
---

# devforge-setup

一次性完成 DevForge plugin 运行环境的检测与安装。支持所有主流 Linux 发行版。

## 全部工具清单（17 个，4 组）

### 必备基础 (4)
`python3` `git` `jq` `docker`

### 代码格式化 (4)
`clang-format` `gofmt` `black` `npx`

### 静态检查 (6)
`shellcheck` `clang-tidy` `bear` `golangci-lint` `ruff` `eslint`

### 平台集成 (3)
`gh` `glab` `zentao`

---

## 第 1 阶段：环境识别 + 工具检测

### 1.1 识别发行版

读取 `/etc/os-release`，通过 `ID` 和 `ID_LIKE` 判定包管理器家族：

```bash
source /etc/os-release && echo "ID=$ID ID_LIKE=$ID_LIKE"
```

判定规则（按优先级）：

1. 若 `ID` 或 `ID_LIKE` 包含 `debian` 或 `ubuntu` → **apt 系**，包管理器 `apt-get`
2. 若 `ID` 或 `ID_LIKE` 包含 `rhel`、`fedora`、`centos` 中的任一 → **dnf/yum 系**
   - 优先用 `dnf`（`command -v dnf` 存在时）
   - 回退 `yum`
3. 以上均不匹配 → 告知用户当前仅验证过 apt 和 dnf/yum 系发行版，尝试继续按 `yum` 处理

常见发行版归类：

| 家族 | 发行版示例 | 包管理器 |
|------|----------|---------|
| apt 系 (Debian) | Ubuntu, Debian, Linux Mint, Pop!_OS, Kali, Deepin, UOS | `apt-get` |
| dnf/yum 系 (RHEL) | RHEL, CentOS, Rocky, AlmaLinux, Fedora, Oracle Linux, Amazon Linux, openEuler | `dnf`（优先）/ `yum` |

输出检测结果，例如：`发行版: Ubuntu 22.04 (apt 系)`。

### 1.2 逐个检查全部 17 个工具

用 `command -v <name>` 逐个检查，静默执行，记录两组结果：

- **已安装列表**（每项 `✅`）
- **缺失列表**（每项 `❌`，记录工具名和对应的安装方式）

注意：`npx` 通过 `command -v npx` 检测；`gofmt` 通过 `command -v gofmt` 检测；`golangci-lint` 通过 `command -v golangci-lint` 检测。

---

## 第 2 阶段：生成报告

按 4 组输出报告，每组列出 `✅` 和 `❌`。末尾统计总数。示例格式：

```
## DevForge 环境检测报告

发行版: Ubuntu 22.04 (apt 系)

### 必备基础 (2/4)
✅ python3  ✅ git
❌ jq  ❌ docker

### 代码格式化 (2/4)
✅ gofmt  ✅ black
❌ clang-format  ❌ npx

### 静态检查 (1/6)
✅ shellcheck
❌ clang-tidy  ❌ bear  ❌ golangci-lint  ❌ ruff  ❌ eslint

### 平台集成 (0/3)
❌ gh  ❌ glab  ❌ zentao

---
共检测 17 个工具，已安装 5 个，缺失 12 个。
```

## 第 3 阶段：确认安装

报告输出后，**必须调用 AskUserQuestion 工具**向用户确认。未收到用户选择前，不得进入第 4 阶段。

| 字段 | 值 |
|------|-----|
| question | "是否安装全部缺失工具？" |
| header | "确认安装" |
| options[0].label | **确认安装** |
| options[0].description | 安装全部 N 个缺失工具（N 替换为实际缺失数量） |
| options[1].label | **跳过安装** |
| options[1].description | 仅查看报告，不执行安装 |

用户选择"跳过安装"则流程结束。选择"确认安装"则进入第 4 阶段。

---

## 第 4 阶段：自动安装

用户选择"确认安装"后执行。

### 4.0 安装原则

执行安装时严格遵循以下原则：

**独立安装**：每个工具的安装作为独立单元执行，单个工具安装失败不影响其他工具。系统包管理器每次调用只安装一个包，禁止将多个包合并到一条 `apt-get/dnf install` 命令中。

**PATH 刷新**：npm global 安装后需刷新 PATH：`export PATH="$HOME/.local/bin:$PATH"`。若使用 pip --user 安装（black fallback），同样执行此刷新。

### 4.1 安装顺序与并发策略

所有系统包各自独立，可**并行安装**（用 `&` 后台 + `wait` 汇聚）。同组内仍逐个安装（避免包管理器锁冲突）。

唯一依赖链：`nodejs npm` → `zentao`（zentao 通过 npm global 安装，需等 npm 就绪）。

**执行流程**：
1. 确保 EPEL 可用（dnf/yum 系且非 Fedora）
2. **并行**安装所有系统包（`jq`、`clang-format`、`golang`、`black`、`nodejs npm`、`shellcheck`、`clang-tidy`、`bear`、`gh`、`glab`、`docker`）
3. 等待步骤 2 完成，刷新 PATH
4. **并行**安装 npm/pip 工具（`zentao`、`eslint`、`ruff`）
5. 安装 `golangci-lint`（curl 安装脚本）
6. 输出结果报告

### 4.2 包名映射表

按发行版选择正确的包名/安装命令。每个工具先尝试主方案，失败则按错误类型动态应用恢复策略。

| 工具 | 安装方式 | 安装命令 |
|------|---------|---------|
| `jq` | 系统包 | `sudo apt-get/dnf/yum install -y jq` |
| `clang-format` | 系统包 | apt 系: `sudo apt-get install -y clang-format` / dnf/yum 系: `sudo dnf/yum install -y clang-tools-extra` |
| `clang-tidy` | 系统包 | apt 系: `sudo apt-get install -y clang-tidy` / dnf/yum 系: `sudo dnf/yum install -y clang-tools-extra`（与 clang-format 同包） |
| `bear` | 系统包 | `sudo apt-get/dnf/yum install -y bear` |
| `golang` (go, gofmt) | 系统包 | `sudo apt-get/dnf/yum install -y golang` |
| `golangci-lint` | 安装脚本 | `curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh \| sh -s -- -b $(go env GOPATH)/bin` |
| `black` | 系统包 > pip | 先尝试系统包：apt 系 `sudo apt-get install -y black`，dnf/yum 系 `sudo dnf/yum install -y python3-black`；失败则 `pip install black` |
| `ruff` | pip | `pip install ruff` |
| `nodejs` + `npm` (npx) | 系统包 | `sudo apt-get/dnf/yum install -y nodejs npm` |
| `eslint` | npm global | `npm install -g eslint` |
| `shellcheck` | 系统包 | `sudo apt-get/dnf/yum install -y shellcheck` |
| `gh` | 系统包 | `sudo apt-get/dnf/yum install -y gh` |
| `glab` | 系统包 | `sudo apt-get/dnf/yum install -y glab` |
| `zentao` | npm global | `npm install -g @singee/zentao-cli` |
| `docker` | 系统包 | `sudo apt-get/dnf/yum install -y docker` |

### 4.3 错误分类与恢复策略

安装失败时，根据实际 stderr 匹配对应策略，动态应对。不硬编码 fallback 路径。

| 错误特征 | 诊断 | 恢复策略 |
|---------|------|---------|
| `Unable to locate package` / `No match for argument` | 包名错误或缓存过期 | Ubuntu: `sudo apt-get update` 后重试；Rocky/CentOS: `sudo dnf makecache` 后重试。仍失败则尝试修正包名。若为单个包不存在于当前源，跳过并提示添加第三方源或手动下载 |
| `Permission denied` / `EACCES` / `read-only` | 权限不足 | 系统包补 `sudo`；pip 加 `--user`；npm 加 `--prefix ~/.local` |
| `Could not resolve host` / `timeout` / `Connection refused` / `Operation timed out` | 网络不通或下载超时 | 重试 1 次（大文件重试 2 次，每次间隔递增）。仍失败则跳过，记录错误并附手动安装提示和替代下载源 |
| `command not found: pip` / `npm` / `go` / `curl` | 工具链缺失 | 先安装缺失的工具链管理器，再重试原命令 |
| `unmet dependencies` / `held broken packages` / `depends on.*but.*not installable` / `nothing provides` | 包存在但依赖不可满足 | 1) `apt-get install -f` 修复依赖；2) 逐层安装缺失的依赖包；3) 若依赖包也不可安装，尝试从官方源下载 .deb/.rpm 手动安装；4) 均失败则跳过，给出编译安装指引 |
| 多层依赖解析失败 / 循环依赖 / 底层库版本不兼容 | 依赖链断裂，包管理器无法自行修复 | 跳过包管理器，直接从官方 GitHub Releases 下载预编译静态二进制（如 `clang-format` → `https://github.com/llvm/llvm-project/releases`）。下载后校验 sha256，解压/拷贝到 `~/.local/bin/` 并确保在 PATH 中。若静态二进制也不可用，跳过并给出编译安装指引 |
| `conflict` / `trying to overwrite` | 文件冲突或版本冲突 | 系统包：尝试 `--fix-broken` 或 `--force-overwrite`；pip：尝试 `--break-system-packages` 或 `--ignore-installed`；npm：尝试 `--force` |
| `SSL` / `certificate` / `TLS` / `peer's certificate` | 证书或代理问题 | 网络类错误特殊处理：跳过并给排查建议（检查代理、CA 证书、系统时间） |
| 其他未知错误 | 无法分类 | 保留完整 stderr（≤5 行），跳过并提示用户手动排查 |

恢复后仍失败 → 记录工具名 + 失败原因，继续下一个。不中断整体流程。

### 4.4 安装结果报告

安装完成后，输出每项安装结果：

```
## 安装结果

✅ jq                       ✅ docker
✅ clang-format             ✅ gofmt
✅ black                    ✅ shellcheck
✅ clang-tidy               ✅ bear
✅ golangci-lint            ✅ ruff
✅ gh                       ✅ glab
✅ eslint
❌ zentao — npm 全局安装失败，已跳过
   手动安装: npm install -g @singee/zentao-cli

成功 13/14，失败 1/14
```

对失败的项，给出手动安装的链接或命令。
