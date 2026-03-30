# DevForge

面向分布式存储团队的 AI 辅助开发工作流体系。

## 项目定位

覆盖产品规划到代码交付全流程的 skill 体系，解决团队级 AI 辅助开发的标准化问题。

**核心目标**：
- 团队整体提效和高效协作，减少并行开发冲突
- 上层约束下层，下层变更反馈上层的四层闭环
- 单代码仓库（Monorepo）组织，所有子系统在同一仓库中管理

## 设计思路

### 1. 分层驱动

| 层级 | 驱动方式 | 关注重点 |
|------|----------|----------|
| 产品级 | 启发式 Skills | 输出质量（explore/define/plan/review/test-design/verify） |
| 特性级 | OpenSpec 引擎 | 流程控制（proposal → specs → design → tasks → implement → archive）|
| 代码级 | Claude Code 原生 | 写对代码（单元测试/TDD/代码检视） |
| 测试验证级 | 自动化工具链 | 集成正确（集成/系统/性能测试） |

产品级是持续数月的创意迭代过程，**重输出质量**；特性级是短期交付闭环，**重流程控制**。

### 2. 四层闭环

```
产品级文档 ──约束──┐
    ▲              ▼
  反馈           特性级 Spec
    │              │
  追踪             ▼
    │           代码实现
    │              │
    └────────── 测试验证
```

- 上层约束下层：产品级文档指导特性级设计，特性级 spec 约束代码实现
- 下层反馈上层：代码变更触发 spec 更新，特性调整同步到产品级规划

### 3. 团队协作为核心

所有设计围绕多人并行开发场景：
- Git worktree 隔离并行开发
- 多 Agent 代码检视与重构
- 统一规范避免代码冲突

### 4. 不造轮子

所有 skill/hook/command/agent 使用现成工具：
- Claude Code 内置能力
- Linux 系统工具（gcc/make/git/grep/sed/awk 等）
- 外部成熟工具（cppcheck、valgrind、clang-format、perf 等）

**不自研工具链**，避免长期维护负担。

### 5. 面向 C + Linux + 分布式存储

针对分布式存储的核心诉求设计：

**数据一致性**：强一致/最终一致、副本一致性、故障后数据完整性
**性能指标**：低延迟、高吞吐、高并发
**代码质量**：内存安全（无泄漏、无越界）、并发正确性（锁序、无锁结构、竞态检测）、错误处理完备性（每个返回值必须检查）

## 目录结构

- .claude/ - Claude Code 配置
  - agents/ - 自定义 Agent
  - commands/ - 自定义命令
  - skills/ - 自定义 Skills
  - rules/ - 规则文件
- docs/ - 产品级文档
- openspec/ - OpenSpec 配置和 schema
- src/ - 各子系统源代码
- tests/ - 测试代码
- reference/ - 参考仓库（不上传，见 .gitignore）

## 使用方式

本仓库采用 Monorepo 模式，所有子系统代码位于同一仓库中。teamskills 提供统一的 skill/agent/command/hook，通过 `.claude/` 目录直接使用。

