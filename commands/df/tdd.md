---
name: tdd
description: 执行 TDD 开发循环（RED-GREEN-REFACTOR）。
---

# /df:tdd

执行 TDD 开发循环（RED-GREEN-REFACTOR）。

## 何时使用

- 实现单个 task 的步骤
- 为现有代码补充测试
- 需要测试保驾护航的重构

## 执行流程

1. 激活 `developer` Agent
2. 读取当前 task 上下文
3. 进入 `devforge-tdd-workflow` Skill：
   - RED：编写失败测试
   - GREEN：写最小实现使测试通过
   - REFACTOR：在测试绿色下简化代码
4. 运行测试确认绿色

## 参数

```
/df:tdd [step-description]
```

- `step-description`（可选）：本次要实现的步骤简述

## 使用示例

```
/df:tdd 实现追加写入逻辑
> RED：编写测试，断言写入后 offset 增加
> 测试失败：assertion failed: offset == 0
>
> GREEN：实现 append，返回更新的 offset
> 测试通过
>
> REFACTOR：提取边界检查到 validate_record
> 测试保持绿色
```

## 关联

- Skill: `devforge-tdd-workflow`（TDD 铁律工作流）
- Reference: `testing-anti-patterns.md`（测试反模式）
- Agent: `developer`
- Rules: `coding-style`, `testing`
