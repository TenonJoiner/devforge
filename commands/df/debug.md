---
name: debug
description: 遇到任何 bug、测试失败或意外行为时使用，在提出修复方案之前。
---

# /df:debug

遇到任何 bug、测试失败或意外行为时使用，在提出修复方案之前。

## 何时使用

- 测试失败、构建中断、运行时异常
- 行为不符合预期、性能回归
- bug 报告、日志/控制台错误

## 参数

```
/df:debug [description]
```

- `description`（可选）：bug 现象简述

## 使用示例

```
/df:debug 测试 test_wal_append 间歇性失败
> Phase 1：TSan 报 data race → 反向追溯发现 fast-path 未持锁
> Phase 2：对比持锁路径 → 确认 fast-path 缺锁是差异
> Phase 3：假设"fast-path 缺锁"→ 最小验证：加锁后复现消失
> Phase 4：修根因 + 回归测试 + defense-in-depth + TSan CI 常态化
```

## 产出物

- 修复后的代码文件
- 回归测试（防止复发）

## 关联

- Skill: `devforge-debug`
- Rules: `testing.md`
- 配套文件:
  - `root-cause-tracing.md` — 调用栈反向追溯技术
  - `defense-in-depth.md` — 在数据流经的每一层添加验证
  - `condition-based-waiting.md` — 用条件轮询替代任意超时
