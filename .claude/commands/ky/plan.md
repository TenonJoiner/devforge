# /ky:plan

制定迭代计划和 proposal 清单。

## 何时使用

- 制定产品迭代计划
- 分解需求为 Proposal Backlog
- 识别关键路径和里程碑
- 协调多子系统并行开发
- 调整计划应对变更
- **滚动更新已有计划**

## 执行流程

1. 激活 `project-manager` Agent
2. 检测现有计划状态（docs/iteration-plan.md）
3. 询问用户意图：
   - **不存在** → 初始规划（模式 A）
   - **已存在** → 滚动更新(B) / 快速调整(C) / 里程碑调整(D) / 迭代执行规划
4. 进入 `product/plan` Skill 流程（根据选择的模式）：

   **模式 A：初始规划**：
   - 第一层：里程碑划分 + 当前里程碑 proposal 分解 + 迭代主题分配
   - 第二层：当前迭代从 Backlog 选择 proposal + Wave 分组 + 就绪检查
   - 输出到 iteration-plan.md

   **模式 B：滚动更新**：
   - 估算校准（实际 vs 估算偏差率）
   - 延期根因分析
   - 调整当前迭代 Wave 和 Backlog
   - 更新 Velocity 和风险状态

   **模式 C：快速调整**：
   - 评估突发变更影响
   - 调整 Wave 分组
   - 更新文档

   **模式 D：里程碑调整**：
   - 重新划分里程碑/迭代分配
   - 仅保留最近迭代详情，后续清空

   **迭代执行规划**（迭代启动前）：
   - 从 Backlog 选择本次迭代的 proposal
   - Wave 分组 + 风险评估 + 并行就绪检查
   - 输出执行计划到 iteration-plan.md

5. 输出保存到 docs/iteration-plan.md
6. 询问是否需要调整其他部分

## 参数

无参数。交互式引导。

## 使用示例

```
/ky:plan
> 未检测到现有计划，开始初始规划（模式 A）：
>
> 【第一层：里程碑/迭代规划】
> 里程碑划分：
>   - MVP（约 80 点，预计 4 个迭代）：端到端写读流程
>   - Alpha（约 100 点，预计 5 个迭代）：单集群功能完整
>   - Beta（约 70 点，预计 4 个迭代）：多集群可扩展
>
> 已写入 iteration-plan.md。是否继续制定迭代 1 的执行计划？
```

```
/ky:plan
> 检测到现有计划：
>   里程碑：MVP/Alpha/Beta ✅
>   迭代主题：MVP 迭代 1-4 ✅
>   执行计划：迭代 1 ✅ | 迭代 2 待规划
>
> 选择操作：
> 1. 制定迭代 2 执行计划
> 2. 滚动更新（基于进展调整）
> 3. 快速调整（应对突发）
> 4. 里程碑调整（重大变更）
```

## 输出物

- docs/iteration-plan.md

## 关联

- Skill: `product/plan`
- Agent: `project-manager`
- Rules: `workflow`

## 与特性级衔接

iteration-plan.md 的 proposal 名称使用 kebab-case，团队通过特性级 workflow 启动开发。
