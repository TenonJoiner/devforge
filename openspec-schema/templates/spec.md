## ADDED Requirements

<!-- 必备结构性元素清单（生成时遵循、评审时检查）：
□ 能力定义清晰
□ 服务于哪些场景（关联 Scenario 列表）
□ 边界（明确不做什么 + 不做的理由）
□ 未来扩展点（如有；无则显式标注「本期无演进性需求」） -->

### Requirement: <!-- 需求名称 -->

**追溯**：`docs/requirements/<文件>#<条目>` 或 `不适用：<原因>`

<!-- 需求正文，必须包含 SHALL 或 MUST -->

#### Scenario: <!-- 正常路径场景名称 -->
<!-- Scenario 必备结构性元素：
□ 前置状态显式化（具体哪些条件成立，避免「系统正常」这种粗粒度）
□ 触发动作的具体路径（哪个 API、哪条调用链、哪个事件）
□ 期望结果的多维度断言（返回值 + 副作用 + 性能 + 可观测信号）
□ 与基线行为的对比（说明改进点；新功能可标注「无基线，本特性首次引入」） -->
- **WHEN** <!-- 具体的前置状态和触发动作 -->
- **THEN** <!-- 可验证的预期结果 -->

#### Scenario: <!-- 异常路径场景名称 -->
- **WHEN** <!-- 具体的异常条件 -->
- **THEN** <!-- 可验证的异常处理结果 -->

## MODIFIED Requirements

<!-- MODIFIED 工作流：
1. 在 openspec/specs/<capability>/spec.md 中定位已有 Requirement
2. 复制 ENTIRE requirement block（从 ### Requirement: 到所有 Scenario）
3. 粘贴到此处并修改
4. 确保 header 文本精确匹配 -->

## REMOVED Requirements

<!-- 废弃功能——MUST 包含 Reason 和 Migration -->
<!-- ### Requirement: <name>
**Reason**: <为什么移除>
**Migration**: <现有用户如何迁移> -->

## RENAMED Requirements

<!-- 仅改名——使用 FROM:/TO: 格式 -->
<!-- FROM: <旧名称>
TO: <新名称> -->
