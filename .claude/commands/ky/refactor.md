# /ky:refactor

执行测试护航下的代码简化重构。支持轻量重构（默认）和深度清理（`--deep`）两种模式。

## 何时使用

- TDD 循环的 REFACTOR 阶段
- 代码评审后的修改清理
- 特性级 archive 前的最终整理

## 执行流程

1. 激活 `developer` Agent
2. **模式选择**：
   - **轻量模式**（默认）：变更量 ≤200 行，或未指定 `--deep`
   - **深度模式**：变更量 >200 行，或用户指定 `--deep`，或处于 Q.1 全量收尾阶段。此时自动进入 `code/simplify` Skill，启动三 agent 并行评审（复用 / 质量 / 效率），由 `developer` 汇总去重并修复问题
3. 运行全部测试并确认绿色
4. 进入对应 Skill 执行重构/清理：
   - 轻量模式：`code/code-refactor`，每次处理一种最明显异味，循环 until 无明显异味
   - 深度模式：`code/simplify`，Phase 1 识别变更 → Phase 2 三 agent 并行评审 → Phase 3 `developer` 汇总修复
5. 再次运行测试确认绿色（深度模式完成后可接 `/ky:lint --full` 跑 valgrind）
6. 输出重构摘要

## 参数

```
/ky:refactor [--deep] [focus]
```

- `--deep`：强制进入深度模式，调用 `code/simplify` Skill 进行复用/质量/效率三维度清理
- `focus`（可选，轻量模式适用）：`dup`（消除重复）/`length`（缩短函数）/`name`（澄清命名）/`complexity`（降低复杂度）

## 使用示例

```
/ky:refactor
> 轻量模式
> 测试绿色 ✅
> 发现 wal.c 有两处重复的错误处理逻辑
> 提取为 wal_handle_io_error()
> 测试保持绿色 ✅
```

```
/ky:refactor --deep
> 深度模式（变更量 +380 -120，涉及 5 个文件）
> 启动三 agent 并行评审...
> 复用 agent：发现 1 处可复用现有 `utils/buffer.c:buf_append()`
> 质量 agent：发现 2 处参数膨胀和 1 处无意义注释
> 效率 agent：发现热路径上新增 `malloc`，建议改为 slab 分配
> 已修复 4/5 个问题，1 个问题标记为后续 TODO
> 全量测试通过，valgrind 0 错误 ✅
```

## 关联

- Skill: `code/code-refactor`（轻量模式）, `code/simplify`（深度模式）
- Agent: `developer`（调度）+ `code-reviewer`（深度模式 subagent）
- Rules: `coding-style`
