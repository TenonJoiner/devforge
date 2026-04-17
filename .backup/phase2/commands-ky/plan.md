# /ky:plan

制定迭代计划和 proposal 清单。

## 何时使用

- 制定产品迭代计划
- 分解需求为 proposal 清单
- 识别关键路径和里程碑
- 协调多子系统并行开发
- 调整计划应对变更
- **滚动更新已有计划**

## 执行流程

1. 激活 `architect` Agent
2. 检测现有计划状态（docs/iteration-plan.md）
3. 询问用户意图：
   - 全新规划
   - 滚动更新
   - 快速调整
4. 进入 `product/plan` Skill 流程：
   - MVP 识别
   - Proposal 分解
   - 依赖分析
   - Wave 分组
   - 复杂度估算
   - 测试相关 Proposal 生成
5. 输出保存到 docs/iteration-plan.md
6. 询问是否需要调整其他部分

## 参数

无参数。交互式引导。

## 使用示例

```
/ky:plan
> 检测到现有迭代计划：
> 1. 滚动更新 —— 基于当前进展调整
> 2. 新增迭代周期 —— 规划下一阶段
> 3. 重新规划 —— 重大变更时重新制定
```

```
/ky:plan
> 迭代周期：3个月
> 主要目标：完成核心存储引擎
> 可用资源：5人（存储团队3人，元数据团队2人）
```

## 输出物

- docs/iteration-plan.md

## 关联

- Skill: `product/plan`
- Agent: `architect`
- Rules: `workflow`

## 与特性级衔接

iteration-plan.md 的 proposal 名称使用 kebab-case，团队通过特性级 workflow 启动开发。
