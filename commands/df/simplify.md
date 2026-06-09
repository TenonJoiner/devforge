# /df:simplify

基于 git diff 对批量变更进行三维度（复用/质量/效率）并行评审，由 developer 汇总修复。

## 何时使用

- 一批 task 完成后的跨 scenario 深度重构（提取公共抽象、接口重设计、模块解耦）
- 任务组末尾的 REVIEW 之后，作为代码质量提升环节
- QA 阶段 `DEEP-REFACTOR` 任务的执行
- OpenSpec archive 前的最终整理
- `/df:code-review` 后发现仍有明显异味

## 何时不使用

- **单个 TDD 循环的 REFACTOR 阶段**：由 `/df:tdd` 内置完成
- **轻量代码清理**：由 `/df:tdd` 内置 REFACTOR 处理

## 执行流程

1. 激活 `developer` Agent
2. 分析当前变更范围（git diff），确定重构策略
3. 启动 `devforge-simplify` Skill：
   - Phase 1：识别变更 → Phase 2：三 agent 并行评审 → Phase 3：`developer` 汇总修复
4. 运行全部测试确认绿色
5. 输出重构摘要

## 参数

```
/df:simplify [focus]
```

- `focus`（可选）：限定评审关注维度
  - `dup` / `reuse`：聚焦复用检查
  - `quality`：聚焦代码质量
  - `perf` / `efficiency`：聚焦效率检查

## 使用示例

```
/df:simplify
> 分析 git diff：+380 -120，涉及 5 个文件，2 个 scenario
> 启动三 agent 并行评审...
> 复用 agent：发现 1 处可复用现有 `utils/buffer.c:buf_append()`
> 质量 agent：发现 2 处参数膨胀和 1 处无意义注释
> 效率 agent：发现热路径上新增 `malloc`，建议改为 slab 分配
> 已修复 4/5 个问题，1 个问题标记为后续 TODO
> 全量测试通过，valgrind 0 错误 ✅
```

```
/df:simplify reuse
> 聚焦复用维度评审...
> 发现 scenario A 和 B 的回调签名不一致
> 统一为 `wal_callback_t` 类型
> 测试通过 ✅
```

## 关联

- Skill: `devforge-simplify`
- Agent: `developer`（调度）+ `code-reviewer`（subagent）
- Rules: `coding-style`
