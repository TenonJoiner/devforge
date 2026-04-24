# /df:plan

制定迭代计划和 proposal 清单。

## 何时使用

- 从零开始制定产品迭代计划
- 继续推进当前阶段的规划（自动识别下一步）
- 滚动更新已有计划

## 使用示例

```
/df:plan
> 启动检测中...
> 进入对应阶段规划...
> 评审通过，下一步：/opsx:new 启动特性开发
```

## 输出物

```
docs/iteration-plan/
├── milestone-plan.md      # 第 1 阶段：里程碑计划 + Backlog 清单
├── iteration-m1-i1.md     # 第 2 阶段：迭代执行计划
└── ...
```

## 关联

- Skill: `product/plan`
- Rules: `workflow`
