---
name: code/simplify
description: 复用/质量/效率三维度深度清理——基于 git diff 的批量 code review 与修复
version: 1.0.0
allowed-tools: [Read, Bash, Grep, Glob, Agent]
---

# code/simplify — 三维度深度清理

## 概述

复用检查 → 质量检查 → 效率检查。基于 git diff 对批量变更做三 agent 并行评审，并由 developer 汇总修复。

## 何时使用

- 单个 task 或一组 task 的变更量较大（>200 行）
- archive 前最终整理
- `/ky:refactor` 后发现仍有明显异味
- 特性级 `/opsx:apply` 的 Q.4 阶段（全量 diff 评审后）

## 执行流程

### Phase 1：识别变更

**目标**：获取本次 proposal 的全部代码变更，而非仅最近一个 commit。

**策略**：
1. 优先获取当前 feature branch 相对于 `main` 的完整 diff：
   ```bash
   BASE=$(git merge-base HEAD main)
   git diff $BASE..HEAD
   ```
2. 若无法获取（如未从 main 分岔、分支未 push），fallback 到：
   - `git log --oneline -n 5` 推断最近几个 commit 是否同属本次 proposal
   - 或读取当前 worktree 关联的 proposal 信息，定位 `/opsx:apply` 的初始 commit
3. 最后检查是否有未提交的 staged/unstaged 变更，一并纳入

> 避免直接使用无参数的 `git diff`——那只会看到最近一次 commit 以内的变更，前面的 tasks 会被漏掉。

### Phase 2：启动三评审 Agent 并行

同时启动 3 个 subagent，各获得完整 diff 和以下指令约束。

#### Agent 1：复用检查（Code Reuse Review）

**目标**：检查新来的代码是否重复造轮子。

1. 搜索现有 utilities / helpers / 公共模块（重点关注 `src/utils/`、`src/common/`、相邻模块）
2. 指出与已有函数仅参数/命名略有差异的新增函数
3. 指出手造的字符串/路径/环境处理逻辑，检查是否可用现有工具替代
4. 指出重复出现的 >3 行逻辑块（出现 >2 处）

**输出格式**：
```markdown
### 复用问题
- `[file:line]` 问题描述
  - **现有替代**：`src/xxx/yyy.c:func_name()`
  - **建议**：直接调用现有函数 / 提取公共辅助函数
```

#### Agent 2：质量检查（Code Quality Review）

**目标**：发现 hacky 模式、过度设计、坏味道。

1. **冗余状态**：新加的 state 是否可由已有 state 派生
2. **参数膨胀**：是否通过新增参数解决，而非重构数据结构
3. **复制粘贴**：仅命名/条件略有差异的重复代码块
4. **泄露抽象**：暴露了内部细节，或破坏了已有抽象边界
5. **过度包装**：无意义的中间层、冗余宏、空函数转发
6. **无意义注释**：解释了 WHAT 而非 WHY 的注释，或带任务编号的注释

**C 语言特有加项**：
- 检查是否引入了新的 `malloc`/`free` 模式，而项目内已有统一内存池
- 检查锁/无锁结构的使用是否已有更成熟的内部封装可用
- 检查错误处理是否混用了不同风格（如有的用 `goto cleanup`，有的用 `return rc`）

**输出格式**：
```markdown
### 质量问题
- `[file:line]` 问题描述
  - **类型**：冗余状态 / 参数膨胀 / 复制粘贴 / 泄露抽象 / 过度包装 / 无意义注释
  - **建议**：...
```

#### Agent 3：效率检查（Efficiency Review）

**目标**：发现性能陷阱和不必要的开销。

1. **不必要的工作**：循环内重复计算、重复文件读取、重复内存分配
2. **热路径膨胀**：新的阻塞调用/锁/分配是否加在了每次请求/IO 都走的路径上
3. **锁粒度**：全局锁保护细粒度操作、锁内嵌套过深
4. **批处理机会**：逐条 IO/请求是否可改为批量提交
5. **内存**：循环内的大缓冲区分配、无界数据结构增长、泄漏风险
6. **IO 开销**：预检查文件存在性再操作（TOCTOU）、读全文件只需部分

**C 语言/分布式存储特有加项**：
- 检查 `memcpy` 是否可用零拷贝替代
- 检查大锁是否保护了无共享状态的路径
- 检查序列化/反序列化是否可被延迟或批量
- 检查故障恢复路径是否引入了全量扫描而非增量

**输出格式**：
```markdown
### 效率问题
- `[file:line]` 问题描述
  - **场景**：热路径 / 初始化路径 / 故障恢复路径
  - **影响**：延迟增加 / 吞吐下降 / 内存膨胀
  - **建议**：...
```

### Phase 3：汇总与修复

主 Agent（`developer`）等待三个 subagent 返回后：
1. 去重合并相同位置的问题
2. 评估每个问题的修复价值和风险
3. 逐个修复（保持测试绿色）
4. 运行全量测试 + valgrind 确认无回归
5. 对 false positive 简单标注并跳过，不展开争论

## 红旗信号

- 三个 agent 同时指出同一文件有问题（高置信度）
- 热路径上出现了 `malloc` 或锁
- 新文件/新函数的 50% 以上代码在别处已存在

## 与 `code/code-refactor` 的关系

| | `code/code-refactor` | `code/simplify` |
|---|---|---|
| 触发时机 | 每个 task 后 | 一批变更后 / archive 前 |
| 检查方式 | 单 agent，聚焦结构 | 3 subagent 并行，复用+质量+效率 |
| 成本 | 秒级–分钟级 | 分钟级 |
| 使用节奏 | 日常高频 | 低频深度 |

## Integration

- **前置 Command**: `/ky:code-review` 或 `/ky:refactor`（本 Skill 由 `/ky:refactor --deep` 触发）
- **后续 Command**: `/ky:lint`
- **Agent**: `developer` 调度，`code-reviewer` 作为 subagent
