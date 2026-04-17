# /ky:define

定义产品需求、Actor 识别、验收标准。

## 何时使用

- 定义产品需求规格
- 制定验收标准
- 量化非功能需求
- **继续完善已有需求文档**

## 执行流程

1. 激活 `architect` Agent
2. 检测现有文档状态（docs/requirements/）
3. 询问用户意图：
   - 新增 Feature
   - 完善现有定义
   - 重构文档结构
4. 进入 `product/define` Skill 流程：
   - 使用场景与上下文（产品定位、部署环境、典型流程）
   - Actor 识别与定义（人类/外部系统/内部组件）
   - Feature 识别（围绕 Actor 分组）
   - Scenario 挖掘（每个 Scenario 必须指定 Actor，覆盖正常+故障模式）
   - 非功能需求量化
5. 输出保存到 docs/requirements/
6. 询问是否继续完善其他 Feature

## 参数

无参数。交互式引导。

## 使用示例

```
/ky:define
> 检测到现有需求文档：
> 1. 新增 Feature —— 扩展现有文档
> 2. 完善现有定义 —— 迭代更新
> 3. 重构结构 —— 调整组织方式
```

```
/ky:define
> 你想定义什么？
> 1. 新 Feature 的需求规格（含 Actor 定义）
> 2. 修改现有需求
```

## 输出物

- docs/requirements/<feature-domain>.md

## 关联

- Skill: `product/define`
- Agent: `architect`
- Rules: `workflow`
