# 团队协作与变更同步

## 十一、团队协作机制

### 11.1 Monorepo 模式

团队采用单一代码仓（Monorepo）组织形式，所有子系统代码位于同一仓库中。teamskills 提供统一的 skill/agent/command/rule/hook，通过 `.claude/` 目录直接使用，无需额外安装。

子系统间的接口定义维护在产品级 `docs/interfaces/` 目录中，所有团队成员共享同一套 skills 和规则。

### 11.2 并行开发模式

- **任务独立性标注**：spec-driven-enhanced schema 的 tasks 模板要求每个 task 标注 `[并行: 是/否]`
- **Wave/Checkpoint/Wave**：独立 task 并行执行 → 合并检查 → 依赖 task 继续（参考 SuperClaude 并行引擎）
- **冲突检测**：同文件修改标记为不可并行
- **git worktree 隔离**：每个并行 agent 使用独立 worktree（worktree skill 由 `/opsx:apply` 内部调度，`/ky:switch-worktree` 供手动切换）

### 11.3 使用方式

teamskills 的 `.claude/` 目录直接位于仓库根目录，Claude Code 自动发现并加载其中的 skills、agents、commands、rules 和 hooks。

```
teamskills/
├── .claude/              # Claude Code 扩展目录，直接使用
│   ├── skills/
│   ├── agents/
│   ├── commands/
│   ├── rules/
│   └── hooks.json
├── docs/                 # 产品级文档
├── openspec/             # OpenSpec 扩展
│   ├── schemas/
│   └── config.yaml       # C 语言 + 分布式存储上下文
├── src/                  # 源代码目录
├── tests/                # 测试代码目录
└── ...
```

**配置说明**：
- `openspec/config.yaml` 位于仓库根目录，包含 C 语言和分布式存储的上下文配置
- 所有团队成员使用同一套配置，无需单独设置

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
