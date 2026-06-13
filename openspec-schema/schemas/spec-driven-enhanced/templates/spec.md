## Requirements Overview

<!-- 1-2 段，让读者快速理解"这份 spec 管什么"。说明本 spec 基于 proposal 中哪个 capability 展开，分解为哪些需求方向及理由。 -->

[1-2 段：从 capability 描述过渡到具体需求分解。]

## ADDED Requirements

<!-- 必备元素：
□ 能力定义清晰，服务于具体 Scenario
□ 边界明确（不做什么 + 理由）
□ Requirement 描述可验证行为，功能/非功能均可；NFR 具体指标必须在此落地
□ 每条 Requirement 至少一个 Scenario，Scenario 用 #### 标题 + WHEN/THEN
□ 如涉及状态转换或复杂流程，可附加 Mermaid 图 -->

### Requirement: [需求名称]

[1 段说明：本 Requirement 解决什么问题，为什么重要]。

[被测系统] MUST/SHALL [具体行为]。

#### Scenario: [正常路径场景名称]

- **WHEN** [具体的前置状态和触发动作]
- **THEN** [可验证的预期结果]

#### Scenario: [异常路径场景名称]

- **WHEN** [具体的异常条件]
- **THEN** [可验证的异常处理结果]

## MODIFIED Requirements

<!-- 工作流：
1. 在 openspec/specs/<capability>/spec.md 中定位已有 Requirement
2. 复制完整 Requirement block（从 ### Requirement: 到所有 Scenario）
3. 粘贴到此处并修改
4. 确保 header 文本精确匹配 -->

### Requirement: [需求名称]

[修改后的需求正文，必须包含 SHALL/MUST]。

#### Scenario: [正常路径场景名称]

- **WHEN** [具体的前置状态和触发动作]
- **THEN** [可验证的预期结果]

#### Scenario: [异常路径场景名称]

- **WHEN** [具体的异常条件]
- **THEN** [可验证的异常处理结果]

## REMOVED Requirements

### Requirement: [需求名称]

**Reason**: [为什么移除，如"该功能已被新方案替代，维护成本高且使用率低"]

**Migration**: [现有用户如何迁移，如"升级到 v2.0 后自动使用替代 API，无需手动修改"]

## RENAMED Requirements

FROM: [旧名称]
TO: [新名称]

---

## Non-Functional Requirements

<!-- capability 级别的非功能需求规格汇总。
五类中需要关注的，必须在本章节写出具体量化指标，并引用其在 ADDED/MODIFIED Requirements 中的落地位置；
不涉及的，必须写明「本期不涉及：[具体原因]」。
所有指标必须可验证、可度量。 -->

### Performance

- **指标**：[具体量化要求，如 P99 写入延迟 < 10 ms]
- **落地**：[ADDED/MODIFIED Requirement: <名称>]

<!-- 如本期不涉及性能约束，替换为：本期不涉及：[具体原因] -->

### Reliability

- **指标**：[具体量化要求，如 RPO = 0，自动恢复时间 < 5 min]
- **落地**：[ADDED/MODIFIED Requirement: <名称>]

<!-- 如本期不涉及可靠性约束，替换为：本期不涉及：[具体原因] -->

### Compatibility

- **指标**：[具体量化要求，如 v2.x 客户端可读写 v1.x 服务端]
- **落地**：[ADDED/MODIFIED Requirement: <名称>]

<!-- 如本期不涉及兼容性约束，替换为：本期不涉及：[具体原因] -->

### Observability

- **指标**：[具体量化要求，如暴露 `feature_x_requests_total` 指标]
- **落地**：[ADDED/MODIFIED Requirement: <名称>]

<!-- 如本期不涉及可观测性增强，替换为：本期不涉及：[具体原因] -->

### Upgrade Compatibility

- **指标**：[具体量化要求，如支持从 v1.2 滚动升级到 v1.3]
- **落地**：[ADDED/MODIFIED Requirement: <名称>]

<!-- 如本期不涉及升级兼容性约束，替换为：本期不涉及：[具体原因] -->
