---
name: devforge-setup
description: 一键检测并安装 DevForge plugin 运行所需的全部系统工具。检测 Linux 发行版，扫描缺失的 CLI 工具，生成报告，用户确认后自动安装。
allowed-tools: [Read, Bash, AskUserQuestion]
---

# devforge-setup

一次性完成 DevForge plugin 运行环境的检测与安装。支持所有主流 Linux 发行版。

## 全部工具清单（39 个，4 组）

### 必备基础 (12)
`python3` `git` `tar` `ps` `sed` `tr` `date` `basename` `grep` `mktemp` `awk` `jq`

### 代码格式化 (4)
`clang-format` `gofmt` `black` `npx`

### 语言工具链 (20)
`clang-tidy` `cppcheck` `bear` `cmake` `make` `go` `golangci-lint` `mypy` `pyright` `ruff` `pylint` `tsc` `biome` `eslint` `npm` `pnpm` `bun` `mvn` `gradle` `shellcheck`

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

### 1.2 检测工具链管理器

检查 `pip` / `pip3`、`npm`、`go` 是否可用（`command -v`）。缺失的工具链管理器本身也需要安装，但先记录状态，安装阶段再处理。

### 1.3 逐个检查全部 42 个工具

用 `command -v <name>` 逐个检查，静默执行，记录两组结果：

- **已安装列表**（每项 `✅`）
- **缺失列表**（每项 `❌`，记录工具名和对应的安装方式）

注意：`npx` 通过 `command -v npx` 检测；`gofmt` 通过 `command -v gofmt` 检测。

---

## 第 2 阶段：生成报告

按 4 组输出报告，每组列出 `✅` 和 `❌`。末尾统计总数。示例格式：

```
## DevForge 环境检测报告

发行版: Ubuntu 22.04 (apt 系)

### 必备基础 (10/12)
✅ python3  ✅ git  ✅ tar  ✅ ps  ✅ sed  ✅ tr
✅ date     ✅ basename  ✅ grep  ✅ mktemp
❌ awk      ❌ jq

### 代码格式化 (3/4)
✅ gofmt  ✅ black
❌ clang-format  ❌ npx

### 语言工具链 (4/22)
✅ go  ❌ clang-tidy  ❌ cppcheck  ❌ bear  ...（列出所有 ❌）

### 平台集成 (0/3)
❌ gh  ❌ glab  ❌ zentao

---
共检测 39 个工具，已安装 17 个，缺失 22 个。
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

### 4.1 安装顺序

先装工具链管理器，再装具体工具：

1. 确保 EPEL 可用（dnf/yum 系且非 Fedora）：`sudo dnf install -y epel-release`（或 `yum`）。Fedora 自带足够软件源，跳过此步
2. 确保 pip 可用：`sudo apt/dnf install -y python3-pip`
3. 确保 npm 可用：`sudo apt/dnf install -y nodejs npm`
4. 确保 go 可用：`sudo apt/dnf install -y golang`（如缺失）
5. 逐个安装其余缺失工具

### 4.2 包名映射表

按发行版选择正确的包名/安装命令。每个工具先尝试主方案，失败则按错误类型动态应用恢复策略。

| 工具 | 安装方式 | 安装命令 |
|------|---------|---------|
| `jq` | 系统包 | `sudo apt-get/dnf/yum install -y jq` |
| `clang-format` | 系统包 | apt 系: `sudo apt-get install -y clang-format` / dnf/yum 系: `sudo dnf/yum install -y clang-tools-extra` |
| `clang-tidy` | 系统包 | apt 系: `sudo apt-get install -y clang-tidy` / dnf/yum 系: `sudo dnf/yum install -y clang-tools-extra`（与 clang-format 同包） |
| `cppcheck` | 系统包 | `sudo apt-get/dnf/yum install -y cppcheck` |
| `bear` | 系统包 | `sudo apt-get/dnf/yum install -y bear` |
| `cmake` | 系统包 | `sudo apt-get/dnf/yum install -y cmake` |
| `make` | 系统包 | `sudo apt-get/dnf/yum install -y make` |
| `golang` (go, gofmt) | 系统包 | `sudo apt-get/dnf/yum install -y golang` |
| `golangci-lint` | 安装脚本 | `curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh \| sh -s -- -b $(go env GOPATH)/bin` |
| `black` | 系统包 > pip | 先尝试系统包：apt 系 `sudo apt-get install -y black`，dnf/yum 系 `sudo dnf/yum install -y python3-black`；失败则 `pip install black` |
| `mypy` | pip | `pip install mypy` |
| `ruff` | pip | `pip install ruff` |
| `pylint` | pip | `pip install pylint` |
| `pyright` | pip | `pip install pyright` |
| `nodejs` + `npm` (npx) | 系统包 | `sudo apt-get/dnf/yum install -y nodejs npm` |
| `typescript` (tsc) | npm global | `npm install -g typescript` |
| `biome` | npm global | `npm install -g @biomejs/biome` |
| `eslint` | npm global | `npm install -g eslint` |
| `pnpm` | npm global | `npm install -g pnpm` |
| `bun` | curl 安装 | `curl -fsSL https://bun.sh/install \| bash` |
| `maven` (mvn) | 系统包 | `sudo apt-get install -y maven` / `sudo dnf/yum install -y maven` |
| `gradle` | 系统包 | `sudo apt-get/dnf/yum install -y gradle` |
| `gh` | 系统包 | `sudo apt-get/dnf/yum install -y gh` |
| `glab` | 系统包 | `sudo apt-get/dnf/yum install -y glab` |
| `shellcheck` | 系统包 | `sudo apt-get/dnf/yum install -y shellcheck` |
| `zentao` | npm global | `npm install -g @singee/zentao-cli` |

### 4.3 错误分类与恢复策略

安装失败时，根据实际 stderr 匹配对应策略，动态应对。不硬编码 fallback 路径。

| 错误特征 | 诊断 | 恢复策略 |
|---------|------|---------|
| `Unable to locate package` / `No match for argument` | 包名错误或缓存过期 | Ubuntu: `sudo apt-get update` 后重试；Rocky/CentOS: `sudo dnf makecache` 后重试。仍失败则尝试修正包名 |
| `Permission denied` / `EACCES` / `read-only` | 权限不足 | 系统包补 `sudo`；pip 加 `--user`；npm 加 `--prefix ~/.local` |
| `Could not resolve host` / `timeout` / `Connection refused` | 网络不通 | 重试 1 次；仍失败则跳过，记录错误并附手动安装提示 |
| `command not found: pip` / `npm` / `go` / `curl` | 工具链缺失 | 先安装缺失的工具链管理器，再重试原命令 |
| `conflict` / `dependency` / `unmet dependencies` | 版本冲突 | 系统包：尝试 `--fix-broken`；pip：尝试 `--break-system-packages`；npm：尝试 `--force` |
| `SSL` / `certificate` / `TLS` | 证书或代理问题 | 网络类错误特殊处理：跳过并给排查建议（检查代理、CA 证书） |
| 其他未知错误 | 无法分类 | 保留完整 stderr（≤5 行），跳过并提示用户手动排查 |

恢复后仍失败 → 记录工具名 + 失败原因，继续下一个。不中断整体流程。

### 4.4 安装结果报告

安装完成后，输出每项安装结果：

```
## 安装结果

✅ jq                       ✅ clang-format
✅ cmake                    ✅ black
❌ gh — 网络错误，已跳过
   手动安装: https://github.com/cli/cli/releases
✅ gradle                   ...

成功 23/25，失败 2/25
```

对失败的项，给出手动安装的链接或命令。
