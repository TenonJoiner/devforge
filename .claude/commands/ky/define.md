# /ky:define

定义产品需求、制定验收标准。采用多 agent 深度思考模式，强调标杆研究先行、Feature-Scenario 分层展开、独立评审验证。禁止快速产出，强制螺旋式迭代完善。

## 何时使用

- 定义产品需求规格
- 制定功能验收标准
- 量化非功能需求
- **继续完善已有需求文档**（螺旋式迭代）

## 核心原则

1. **标杆先行**：不研究业界同类产品的需求规格，不允许定义自研 Feature
2. **Actor 驱动**：先识别所有交互角色，再围绕角色定义场景
3. **Feature 为主**：正常场景是需求的核心，故障/异常/运维场景从完整性维度补充
4. **分层产出**：先产出 Actor-Feature 清单并评审定稿，再进入 Scenario 挖掘
5. **长时间迭代**：需求文档需要 3-10 轮迭代才能定稿，禁止一次对话定需求
6. **多 agent 协作**：`product-manager` 主导，`researcher` 标杆研究，`pm-reviewer` + `architect-reviewer` 双质疑

## 执行流程（多轮迭代）

### 第 0 步：状态检测

1. 检测现有文档状态（`docs/requirements/` 下的 `README.md`、`overview.md`、特性域文档、`reference/`）
2. 汇报当前状态：已完成标杆数、当前轮次、置信度

```
=== 状态汇报 ===
已完成标杆研究：2/3（vLLM ✓, LMCache ✓, MoonCake ⏳）
当前轮次：第 2 轮（Actor-Feature 识别）
当前置信度：中（Feature 框架较清晰，2 个 Actor 边界待确认）

=== 本次重点 ===
完成 MoonCake 标杆需求分析验收
识别隐性 Actor（安全审计、合规检查）

确认开始？（是/调整重点）
```

### 第 1 轮：产品定位确认 + 标杆研究（强制，不可跳过）

- 前置定位确认（5-10 分钟启发式提问）
- 标杆研究（并行 researcher，每个标杆 10-15 分钟）
- product-manager 验收研究深度（≥0.80 分才准入下一轮）

### 第 2 轮：Actor-Feature 识别与定稿（强制）

- Step 2.1：Actor 识别（并行 researcher 补充竞品 Actor 映射）
- Step 2.2：Feature 识别（支持多 domain 并行 product-manager）
- Step 2.3：pm-reviewer + architect-reviewer 双质疑（按复杂度分级，核心表格强制针对性质疑）
- Step 2.4：修正定稿（≥0.85 分才准入下一轮）

### 第 3 轮：Scenario 挖掘与特性域定稿（强制）

- Phase A：分域并行 product-manager 挖掘 Scenario（20-30 分钟 / domain）
- Phase B：双质疑（按复杂度分级，核心表格强制针对性质疑）
- Phase C：修正定稿（≥0.85 分才准入下一轮）

### 第 4 轮：需求维护与扩展（用户驱动）

**快速通道**（小修不走完整轮次）：
- **文档一致性修正**：`overview.md` 与 `feature-domain.md` 间 Feature 名称/优先级不一致
- **单 Feature 补充**：直接补充某个 Feature 的 Scenario
- **单篇标杆补充**：researcher 产出 → product-manager 验收 → 落盘

**大变更回退到局部子流程**：
- 新增 Feature → 进入第二轮 Step 2.2 → Step 2.3 → Step 2.4 → 第三轮
- 推翻已有 Scenario 假设 → 进入第三轮 Phase A → Phase B → Phase C
- 新增特性域 → 第三轮 Phase A → Phase B → Phase C

## 禁止事项

- ❌ 单次对话内完成"定位→标杆→Actor→Feature→Scenario"
- ❌ 标杆研究 < 2 个即定义 Feature
- ❌ Feature 只有名称没有价值论证
- ❌ Actor-Feature 未定稿就进入 Scenario 挖掘
- ❌ 验收标准无法量化（"高性能""高可用""稳定"）
- ❌ 需求文档未经 pm-reviewer 和 architect-reviewer 双质疑直接定稿
- ❌ Agent 产出内容未写入项目文件（仅存在于对话中）
- ❌ 向用户汇报"本轮完成"但文件未落盘

## 参数

无参数。交互式引导。

## 使用示例

```
/ky:define

=== 状态汇报 ===
已完成标杆研究：2/3（vLLM ✓, LMCache ✓, MoonCake ⏳）
当前轮次：第 1 轮（标杆研究）
当前置信度：低（研究不充分）

=== 本次重点 ===
继续完成 MoonCake 深度需求分析
预计时间：15 分钟

=== 产出 ===
docs/requirements/reference/product-mooncake.md

确认开始？（是/调整重点）
```

```
/ky:define

=== 状态汇报 ===
已完成标杆研究：3/3 ✓
当前轮次：第 2 轮（Actor-Feature 识别）
当前置信度：中（Actor 框架清晰，Feature 边界待确认）

=== 本次重点 ===
产出 Actor-Feature 初稿，启动双评审
建议：后续通过用户确认隐性 Actor 边界

确认开始？（是/继续完善 Actor）
```

```
/ky:define

=== 状态汇报 ===
已完成标杆研究：3/3 ✓
当前轮次：第 4 轮（需求维护）
当前状态：cache-offloading.md 中 Feature-3 验收标准不可量化，overview.md 中 Feature-3 优先级与特性域文档不一致

=== 您本次希望做什么？ ===
1. 修正 Feature-3 验收标准
2. 同步 overview.md 与特性域文档的优先级
3. 补充新标杆调研
4. 其他（请描述）
```

## 输出物

- `docs/requirements/README.md` — 目录导航 + 当前轮次看板
- `docs/requirements/overview.md` — 全局需求总纲
- `docs/requirements/<feature-domain>.md` — 按特性域组织
- `docs/requirements/reference/<product>.md` — 标杆需求分析

## 关联

- Skill: `product/define`
- Agent: `product-manager`, `researcher`, `pm-reviewer`, `architect-reviewer`
- Rules: `workflow`
