# /df:tdd

执行 TDD 开发循环（RED-GREEN-REFACTOR）。

## 何时使用

- 实现单个 OpenSpec task 的步骤
- 为现有代码补充测试
- 需要测试保驾护航的重构

## 执行流程

1. 激活 `developer` Agent
2. 读取当前 task 上下文（如由 `/opsx:apply` 触发）
3. 进入 `code/tdd-workflow` Skill：
   - RED：编写失败测试（对应 tasks.md N.M.1 ~ N.M.2）
   - GREEN：写最小实现使测试通过（对应 tasks.md N.M.3 ~ N.M.4）
   - REFACTOR：调用 `/df:refactor` 简化代码（对应 tasks.md N.M.5）
5. 运行测试确认绿色（valgrind 留到 proposal 收尾或 `/df:lint --full` 阶段）

## 参数

```
/df:tdd [step-description]
```

- `step-description`（可选）：本次要实现的步骤简述

## 使用示例

```
/df:tdd 实现 WAL 写入接口的追加逻辑
> RED：编写 test_wal_append.c，断言写入后 offset 增加
> 测试失败：assertion failed: offset == 0
>
> GREEN：实现 wal_append，返回更新的 offset
> 测试通过 ✅
>
> REFACTOR：提取边界检查到 wal_validate_record
> 测试保持绿色 ✅
```

## 关联

- Skill: `code/tdd-workflow`
- Agent: `developer`
- Rules: `coding-style`, `testing`
