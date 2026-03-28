# 团队协作与变更同步

## 十一、团队协作机制

### 11.1 多仓模型

团队采用多代码仓组织形式，每个子系统一个独立仓库。teamskills 作为产品级统一仓库，各子系统代码仓通过 `scripts/install.sh` 引用本仓的 skill/agent/command/rule/hook。

子系统间的接口定义维护在产品级 `docs/interfaces/` 目录中，团队成员与子系统的对应关系由团队日常协作工具（飞书/Wiki 等）维护。

### 11.2 并行开发模式

- **任务独立性标注**：spec-driven-enhanced schema 的 tasks 模板要求每个 task 标注 `[并行: 是/否]`
- **Wave/Checkpoint/Wave**：独立 task 并行执行 → 合并检查 → 依赖 task 继续（参考 SuperClaude 并行引擎）
- **冲突检测**：同文件修改标记为不可并行
- **git worktree 隔离**：每个并行 agent 使用独立 worktree（worktree skill 由 `/opsx:apply` 内部调度，`/ky:switch-worktree` 供手动切换）

### 11.3 安装机制

各子系统代码仓通过 `scripts/install.sh` 集成 teamskills：

```bash
#!/bin/bash
# scripts/install.sh — 在子系统代码仓中执行
# 用法: /path/to/teamskills/scripts/install.sh
set -euo pipefail

TEAMSKILLS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TARGET_DIR="$(pwd)"

# === 辅助函数：创建相对路径 symlink ===
# 使用 realpath --relative-to 计算相对路径，确保跨机器可移植
make_rel_link() {
  local target="$1"  # symlink 指向的真实目标
  local link="$2"    # symlink 自身的路径
  local link_dir
  link_dir="$(dirname "$link")"
  local rel_path
  rel_path="$(realpath --relative-to="$link_dir" "$target")"
  ln -sfn "$rel_path" "$link"
}

# 0. 前置检查
if [ ! -d "$TEAMSKILLS_DIR/.claude" ]; then
  echo "错误：未找到 teamskills/.claude 目录" >&2
  exit 1
fi

# 1. Claude Code 扩展：相对路径 symlink（跨机器可移植）
mkdir -p "$TARGET_DIR/.claude"
make_rel_link "$TEAMSKILLS_DIR/.claude/skills"    "$TARGET_DIR/.claude/skills"
make_rel_link "$TEAMSKILLS_DIR/.claude/agents"    "$TARGET_DIR/.claude/agents"
make_rel_link "$TEAMSKILLS_DIR/.claude/commands"  "$TARGET_DIR/.claude/commands"
make_rel_link "$TEAMSKILLS_DIR/.claude/rules"     "$TARGET_DIR/.claude/rules"
make_rel_link "$TEAMSKILLS_DIR/.claude/hooks.json" "$TARGET_DIR/.claude/hooks.json"

# 2. OpenSpec schema：相对路径 symlink
mkdir -p "$TARGET_DIR/openspec/schemas"
make_rel_link "$TEAMSKILLS_DIR/openspec/schemas/spec-driven-enhanced" \
              "$TARGET_DIR/openspec/schemas/spec-driven-enhanced"

# 3. OpenSpec config：从模板复制（子仓库需自定义 context）
if [ ! -f "$TARGET_DIR/openspec/config.yaml" ]; then
  cp "$TEAMSKILLS_DIR/openspec/config.yaml.template" "$TARGET_DIR/openspec/config.yaml"
  echo "已创建 openspec/config.yaml，请修改 context 部分以匹配子系统特性"
fi

# 4. 版本感知：记录 teamskills 版本，用于检测版本漂移
TEAMSKILLS_VERSION="$(cd "$TEAMSKILLS_DIR" && git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
echo "$TEAMSKILLS_VERSION" > "$TARGET_DIR/.claude/.teamskills-version"

echo "安装完成（teamskills@$TEAMSKILLS_VERSION）。"
echo "子仓库不自行定义扩展，所有增强统一修改 teamskills。"
echo "运行 scripts/check-version.sh 可检测 teamskills 版本是否需要更新。"
```

**版本漂移检查**（`scripts/check-version.sh`，子仓库中执行）：

```bash
#!/bin/bash
# scripts/check-version.sh — 检查子仓库引用的 teamskills 版本是否过时
# 用法: 在子仓库中执行

VERSION_FILE=".claude/.teamskills-version"
if [ ! -f "$VERSION_FILE" ]; then
  echo "未找到 .claude/.teamskills-version，请先执行 install.sh" >&2
  exit 1
fi

INSTALLED_VERSION="$(cat "$VERSION_FILE")"
# 通过 symlink 反向追溯 teamskills 目录
TEAMSKILLS_DIR="$(realpath .claude/skills/../..)"
CURRENT_VERSION="$(cd "$TEAMSKILLS_DIR" && git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"

if [ "$INSTALLED_VERSION" = "$CURRENT_VERSION" ]; then
  echo "teamskills 版本一致：$CURRENT_VERSION"
else
  echo "⚠ teamskills 版本不一致！已安装: $INSTALLED_VERSION，当前: $CURRENT_VERSION"
  echo "请重新执行: $TEAMSKILLS_DIR/scripts/install.sh"
fi
```

各仓独立维护 `openspec/config.yaml`，注入子系统特定上下文（如存储引擎关注 IO 路径和数据结构，元数据服务关注一致性协议和缓存）。

---

## 十二、变更回溯机制

解决 P5 问题。通过 `/ky:verify`（PS6）按需执行全量双向一致性检查，识别产品级文档与特性级 spec/design/code 之间的不一致，判断同步方向，由人确认后更新。

### 12.1 四种变更类型

| 类型 | 触发场景 | 传播方向 |
|------|---------|---------|
| 需求变更 | 产品需求调整 | 向下（产品 → 特性 → 代码） |
| 设计反馈 | 实现中发现设计问题 | 向上（代码 → 特性 → 产品） |
| 接口变更 | 子系统间接口调整 | 横向 + 向上 |
| 范围变更 | 特性增减/优先级调整 | 向上（特性 → 产品迭代计划） |

### 12.2 `/ky:verify` 驱动的双向一致性检查

变更回溯通过 `/ky:verify` 按需执行全量检查，不依赖自动化 hook 实时检测：

1. 对比所有已实现 feature 的 spec/design/code 与产品级文档
2. 识别不一致点，判断方向：
   - **上行同步**：特性级变更合理（如实现中发现更优方案），建议更新产品级文档
   - **下行修正**：违反产品级设计约束，建议修正特性级文档/代码
3. 输出：不一致清单 + 方向判断 + 修改建议
4. 由人确认后执行修改

**典型触发时机**：
- 一批特性级 proposal 完成实现并合并后
- 产品级文档发生重大调整后
- 迭代周期结束时的回顾检查
- 跨子系统接口变更影响到其他子系统时

### 12.3 向下同步

产品级变更通过 OpenSpec 的 Delta spec 机制自然向下传播：

1. 产品需求变更 → 使用 `/ky:define` 更新 docs/requirements/
2. `/ky:product-review` 检查跨文档一致性 → 识别受影响的特性级 proposal
3. 特性级 spec 更新 → `/opsx:verify` 检查一致性 → tasks 更新

### 12.4 向上同步

特性级实现中发现的问题反馈到产品级：

1. 特性级 spec-driven-enhanced 流程中发现与产品级文档的偏差（proposal/specs/design 的 instruction 均要求标注偏差点）
2. `/ky:verify` 执行全量双向检查，输出不一致清单和方向建议
3. 人确认后更新产品级文档（docs/requirements/、docs/interfaces/、docs/architecture/ 等）
4. 特性级已完成的变更通过 OpenSpec `/opsx:archive` 合并归档
