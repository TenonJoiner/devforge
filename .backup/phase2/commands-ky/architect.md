# /ky:architect

探索产品架构方案、竞品分析、子系统分解。

## 何时使用

- 系统架构设计
- 重大技术决策
- 竞品分析和方案对比
- 架构重构评估
- 子系统分解调整
- **继续完善已有架构文档**

## 执行流程

1. 激活 `architect` Agent
2. 检测现有文档状态（docs/architecture/, docs/adr.md）
3. 询问用户意图：
   - 从零开始探索新架构
   - 继续完善现有文档
   - 对比回顾已有决策
4. 进入 `product/architect` Skill 流程：
   - 发散思考（生成 ≥3 候选方案）
   - 多方案对比（五维质量属性评估）
   - 收敛记录（根据置信度选择产出形式）
5. 输出保存到 docs/architecture/ 和 docs/adr.md
6. 询问是否继续完善其他方向

## 参数

无参数。交互式引导。

## 使用示例

```
/ky:architect
> 检测到现有架构文档：
> 1. 继续完善 [storage-engine.md] —— 迭代更新
> 2. 探索新方向 —— 启动新的架构讨论
> 3. 对比回顾 —— 检视现有决策
```

```
/ky:architect
> 你想探索什么方向？
> 1. 新的存储引擎架构
> 2. 一致性协议选择
> 3. 子系统分解调整
```

## 输出物

- docs/architecture/<subsystem>.md（子系统架构）
- docs/architecture/exploration/（探索笔记）
- docs/adr.md（架构决策记录）

## 关联

- Skill: `product/architect`
- Agent: `architect`
- Rules: `workflow`
