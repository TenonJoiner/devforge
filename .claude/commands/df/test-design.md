# /df:test-design

制定测试策略和各级测试方案。

## 何时使用

- 架构和需求初步就绪后，制定测试策略
- 架构或需求重大变更后，同步调整测试策略
- `/df:plan` 前，为集成测试 proposal 提供输入依据

## 执行流程

1. 激活 `architect` Agent
2. 检测现有测试策略（docs/test-strategy.md）
3. 读取架构文档（docs/architecture/）和需求文档（docs/requirements/）
4. 进入 `devforge-test-design` Skill 流程：
   - **不存在** → 完整制定：测试分层定义 → 覆盖率目标 → 各级测试方案
   - **已存在** → 增量更新：识别架构/需求变更 → 调整受影响的测试方案
5. 输出保存到 docs/test-strategy.md
6. 询问是否需要调整

## 参数

无参数。交互式引导。

## 使用示例

```
/df:test-design
> 检测到架构文档和需求文档已就绪。
> 未检测到现有测试策略，开始完整制定：
>
> 【测试分层定义】
>   单元测试：单函数/模块逻辑（包含在特性 proposal 中）
>   集成测试：多节点部署 + 组件交互 + 故障注入 + 一致性验证 + 端到端（独立 proposal）
>   性能测试：基准 + 压力 + 回归（独立 proposal）
>
> 【覆盖率目标】
>   单元 ≥80% | 集成覆盖关键路径和故障恢复 | 性能建立基准线
>
> 已写入 test-strategy.md。是否需要调整？
```

## 输出物

- docs/test-strategy.md

## 关联

- Skill: `devforge-test-design`
- Agent: `architect`
- Rules: `workflow`
