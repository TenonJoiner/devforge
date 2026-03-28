# 产品级 Skills + 特性级 Schema

## 三、产品级 Skills + 特性级 Schema

### 3.1 产品级启发式 Skills（6 个，替代原 product-design schema）

解决 P1+P4+P5：缺少产品级规划视角、测试不成体系、变更无法回溯。

**设计决策**：产品级设计是持续 2-3 个月的创意迭代过程——架构↔需求↔接口反复纠缠，重要的是**输出质量**而非**流程控制**。因此完全移除 product-design schema，产品级与 OpenSpec 彻底脱离，用 6 个启发式 skill（按思考模式拆分）替代 5 个 schema artifact。其中 PS5 `product/test-design` 解决测试策略制定问题（P4），PS6 `product/verify` 解决变更回溯问题（P5）。

**保留相同的交付物，改变生产方式——从「引擎驱动流程」变为「skill 辅助思考」。**

#### PS1: `product/explore`（探索性思考）

- **适用交付物**：vision.md、architecture/、子系统分解
- **核心模式**：发散思考 → 多方案对比 → 收敛决策
- **内置启发方法**：
  - 竞品分析框架：技术方案对比矩阵（功能/性能/一致性/可运维性）
  - 多方案探索：每个架构决策至少 3 个候选方案 + trade-off 分析
  - 质量属性评估：从性能、一致性、可靠性、可维护性、扩展性五维审视每个方案
  - ADR 输出：每个重大决策产出 Architecture Decision Record
- **置信度守门**：
  - 问题理解充分度（25%）、方案可行性验证（25%）、业界方案调研（20%）、风险识别（15%）、团队共识（15%）
  - ≥90% 推进 / 70-89% 继续调研 / <70% 停止
- **可反复使用**：愿景可以回来改，架构可以反复迭代，子系统划分可以重新调整。没有"完成"状态，只有"当前最佳版本"

#### PS2: `product/define`（定义性思考）

- **适用交付物**：requirements/、interfaces/
- **核心模式**：场景驱动 → 精确定义 → 场景独立可验收
- **需求组织格式**：Feature-Scenario 两级结构，Scenario 是独立验收单元
  ```
  Feature: <特性名称>
    做什么：该特性提供的能力和行为
    为什么：为什么需要这个特性，解决什么问题或带来什么价值

    Scenario: <场景名称>
      前置条件：系统处于什么状态
      触发动作：用户/系统执行什么操作
      预期行为：系统应产生什么结果
      验证方法：具体的测试手段（可独立编写测试用例验收）
  ```
- **内置启发方法**：
  - Feature 识别：从用户视角识别能力分组，将相关场景归纳到同一特性下
  - Scenario 挖掘：正常路径 + 故障场景（节点宕机/网络分区/磁盘故障/并发冲突），每个 Scenario 是独立可验收的行为单元
  - 接口契约设计：输入/输出/错误码/一致性语义/幂等性/版本兼容
  - 非功能需求量化：吞吐量/延迟/可用性/容量必须有具体数字，表达为可独立验收的 Scenario
- **铁律守门**：
  - 每个 Scenario 必须可独立编写测试用例验收（否则粒度不够）
  - 每个接口必须定义错误处理契约（否则不算完成设计）
  - 分布式场景必须覆盖至少 4 种故障模式
- **可反复使用**：架构变了 Feature 要调，接口变了 Scenario 要改——随时回来迭代

#### PS3: `product/plan`（规划性思考）

- **适用交付物**：iteration-plan.md（迭代计划 + proposal 清单）
- **核心模式**：MVP 优先 → 依赖分析 → 最大化并行
- **内置启发方法**：
  - MVP 识别：最小可用产品的核心能力边界
  - 依赖图分析：proposal 之间的前后依赖关系，识别关键路径
  - 并行分组：无依赖的 proposal 分入同一并行组（Wave）
  - 复杂度估算：S/M/L 三档，辅助团队排期
  - 递归深化：如果某个迭代过于庞大，拆分为子迭代
- **与特性级衔接**：iteration-plan.md 的每个 proposal 名称使用 kebab-case，团队人工通过 `/opsx:propose <name> --schema spec-driven-enhanced` 启动特性级开发

#### PS4: `product/review`（审视性思考）

- **适用交付物**：所有产品级文档
- **核心模式**：多维评审 + 跨文档一致性 + 红旗检测
- **内置启发方法**：
  - 跨文档一致性检查：架构子系统 ↔ 需求子系统 ↔ 接口子系统是否对齐
  - 完备性检查：每个子系统有架构？每个特性域有需求？每对交互子系统有接口？
  - 红旗检测：🚩 未验证的性能假设、🚩 没有故障场景的接口、🚩 没有 ADR 的重大决策、🚩 不可独立验收的 Scenario、🚩 没有具体数字的非功能需求
- **两轮评审**：AI 评审（CRITICAL/HIGH/MEDIUM/LOW 分级）+ 人员交叉评审

#### PS5: `product/test-design`（定义性思考）

- **适用交付物**：test-strategy.md、各级测试方案
- **核心模式**：测试分层定义 → 覆盖率目标分配 → 各级测试方案设计
- **内置启发方法**：
  - 测试分层定义：单元测试 vs 集成测试 vs 系统测试 vs 性能测试的边界和职责划分
  - 覆盖率目标分配：各层级的覆盖率目标（单元 ≥80%、集成覆盖关键路径、系统覆盖端到端场景）
  - 集成测试方案：组件交互验证、接口契约验证、故障注入（磁盘/网络/进程故障）、数据一致性验证
  - 系统测试方案：多节点部署验证、一致性协议验证、故障恢复验证、升级回滚验证
  - 性能测试方案：基准测试（IOPS/吞吐/延迟）、压力测试、性能回归检测
- **可反复使用**：测试策略随架构和需求的迭代同步调整

#### PS6: `product/verify`（审视性思考）

- **适用交付物**：产品级文档 vs 特性级（spec/design/code）
- **核心模式**：全量双向一致性检查 → 方向判断 → 修改建议
- **内置方法**：
  - 对比所有已实现 feature 的 spec/design/code 与产品级文档，识别不一致点
  - 判断同步方向：上行同步（特性级变更合理，建议更新产品级文档）或下行修正（违反产品级设计，建议修正特性级文档/代码）
  - 输出：不一致清单 + 方向判断 + 修改建议，由人确认
- **典型触发时机**：一批特性完成后、产品级文档重大调整后、迭代周期结束时
- **可反复使用**：每次迭代结束都应执行，确保上下层文档同步

**产品级与特性级的衔接**：

```
产品级（启发式 Skills，可反复迭代）
  /ky:explore ←→ /ky:define ←→ /ky:plan
      │               │              │
      ▼               ▼              ▼
  vision.md    requirements/    iteration-plan.md
  architecture/  interfaces/    （含测试代码仓 proposal）
      │
      │ /ky:test-design（测试策略 + 各级测试方案）
      │ /ky:product-review（多维评审 + 红旗检测）
      │
      └── proposal 清单（人工执行）
          ▼
特性级（OpenSpec spec-driven-enhanced schema，DAG 驱动）
  /opsx:propose <name>          │
          ▼ 特性完成后
  /ky:verify（全量双向一致性检查，反馈产品级文档）
```

### 3.2 spec-driven-enhanced schema（特性级，5 个 artifact，fork spec-driven）

解决 P2：特性开发输出质量不足。在 OpenSpec 的 spec-driven schema（proposal → specs → design → tasks）基础上增强。

**与 spec-driven 的三处关键差异**：
1. **新增 review artifact**：在 design 之后、tasks 之前插入设计评审环节，CRITICAL/HIGH 问题阻塞进入 tasks
2. **tasks 模板强制 TDD 粒度**：每个 task 包含 TEST → VERIFY-RED → IMPL → VERIFY-GREEN → REFACTOR → COMMIT 六步
3. **所有 artifact 的 instruction 注入 C 语言 + 分布式存储约束**

```yaml
# openspec/schemas/spec-driven-enhanced/schema.yaml
name: spec-driven-enhanced
version: 1
description: 增强版特性工作流 — 增加设计评审、TDD 任务粒度、C 语言约束

artifacts:
  - id: proposal
    generates: proposal.md
    description: 特性提案（遵循产品级约束）
    template: proposal.md
    instruction: |
      创建特性提案文档，说明为什么需要这个变更。

      前置步骤（必须）：
      - 阅读产品级 iteration-plan.md，定位本 proposal 对应的条目
      - 阅读产品级 requirements/ 中相关特性域的需求规格
      - 阅读产品级 architecture/ 中相关子系统的架构设计
      - 阅读产品级 interfaces/ 中相关子系统的接口规格
      以产品级文档为参考上下文。如发现产品级文档存在缺漏或需要调整，在 proposal 中标注差异点，后续通过 /ky:verify 反馈到产品级。

      格式要求与 spec-driven 相同（Why / What Changes / Capabilities / Impact）。

      额外约束：
      - proposal 必须追溯到产品级 iteration-plan 中的条目
      - Impact 部分必须标注影响的子系统和接口
      - 变更涉及数据路径时，必须说明对数据一致性的影响
      - 变更涉及性能关键路径时，必须说明对延迟/吞吐量的预期影响
    requires: []

  - id: specs
    generates: "specs/**/*.md"
    description: Delta 格式特性规格
    template: spec.md
    instruction: |
      创建特性规格文档，定义系统应该做什么（Delta 格式）。

      前置步骤（必须）：
      - 阅读产品级 requirements/ 中相关特性域的需求规格
      - 尽量追溯到产品级需求；如发现产品级未覆盖的新行为，在 spec 中标注为「新增发现」，后续通过 /ky:verify 反馈到产品级

      格式要求与 spec-driven 相同（ADDED/MODIFIED/REMOVED/RENAMED Requirements + Scenarios）。

      额外约束：
      - 每个 Scenario 必须具体到可直接编写测试用例的粒度
      - 涉及错误处理的 Requirement 必须包含错误场景的 Scenario
      - 涉及并发的 Requirement 必须包含竞态条件的 Scenario
      - 涉及故障恢复的 Requirement 必须包含故障注入的 Scenario

      分布式存储特定 Scenario 模板：
      - 正常路径 + 节点故障 + 网络分区 + 并发冲突 + 磁盘故障
    requires:
      - proposal

  - id: design
    generates: design.md
    description: 技术设计文档
    template: design.md
    instruction: |
      创建技术设计文档，说明如何实现变更。

      前置步骤（必须）：
      - 阅读产品级 architecture/ 中相关子系统的架构设计和专题文档
      - 阅读产品级 adr.md 中相关的架构决策记录
      - 阅读产品级 interfaces/ 中相关子系统的接口规格
      - 参考产品级架构约束和已有 ADR 决策；如需偏离，在 design 中说明理由并标注为「架构偏离」，后续通过 /ky:verify 反馈到产品级

      格式要求与 spec-driven 相同（Context / Goals / Decisions / Risks）。

      额外约束（C 语言 + 分布式存储）：
      - **数据结构设计**：关键数据结构的内存布局、缓存友好性考量
      - **并发设计**：锁粒度、锁序、是否可用无锁结构、线程模型
      - **错误处理链**：从底层到上层的错误码传播路径
      - **内存管理**：分配策略（内存池/slab/malloc）、引用计数/所有权语义
      - **IO 路径**：同步/异步 IO 选择、批处理策略、零拷贝机会

      Decisions 部分：
      - 重大决策应在产品级 adr.md 或子系统 adr.md 中创建正式 ADR
      - 特性级 design.md 引用相关 ADR，补充特性实现层面的决策说明
      - 每个决策必须列出至少一个备选方案及其排除理由
    requires:
      - proposal

  - id: review
    generates: review.md
    description: 设计评审报告（新增 artifact，CRITICAL/HIGH 阻塞进入 tasks）
    template: review.md
    instruction: |
      对 proposal、specs、design 进行多维度设计评审，生成评审报告。
      评审分两个阶段：AI 迭代评审（自动）+ 人员交叉评审（线下）。

      === 第一阶段：AI 迭代评审（最多 5 轮）===

      AI 评审采用「评审 → 修复 → 再评审」循环，直到无 CRITICAL 和 HIGH 问题或达到 5 轮上限。

      每轮评审维度：
      1. **完整性**：需求是否完整覆盖、场景是否充分
      2. **正确性**：设计是否能满足 spec 要求、技术方案是否可行
      3. **一致性**：proposal/specs/design 三者是否一致、与产品级文档是否一致
      4. **安全性**：是否存在安全风险（OWASP/STRIDE 模型）
      5. **性能影响**：对关键路径延迟和吞吐量的影响评估
      6. **可维护性**：设计复杂度是否合理、是否过度工程化

      迭代流程：
      1. AI 评审 proposal/specs/design，输出问题清单（CRITICAL/HIGH/MEDIUM/LOW）
      2. 如存在 CRITICAL 或 HIGH 问题，AI 修复对应的 specs/design 文档
      3. 重新评审修复后的文档，检查 CRITICAL/HIGH 是否消除、是否引入新问题
      4. 重复步骤 2-3，直到无 CRITICAL 和 HIGH 问题
      5. 达到 5 轮上限仍有 CRITICAL 或 HIGH 问题时，停止迭代，在 review.md 中标注未解决问题，提示用户人工介入

      出口标准：无 CRITICAL 和 HIGH 问题，或达到 5 轮上限。

      === 第二阶段：人员交叉评审 ===

      AI 迭代评审达标后，review.md 中人员评审部分留空模板，等待线下完成。

      评审人员：
      - **本子系统技术 leader**（必须）：最终审批人，负责签字
      - **其他子系统开发人员**（至少 1 人）：提供跨子系统视角

      评审重点（聚焦 AI 无法覆盖的部分）：
      - 领域知识和工程经验判断
      - 跨子系统的影响和兼容性
      - 方案的可落地性和运维友好性
      - 历史踩坑经验（AI 不了解的项目历史）

      评审流程：
      1. AI 迭代评审达标后暂停，提示用户安排人员评审
      2. 评审人员直接编辑 review.md，在人员评审区域追加意见
      3. 技术 leader 在签字区域填写结论
      4. 签字完成后，用户手动执行 `/opsx:continue` 生成 tasks

      === 输出格式 ===

      ## AI 迭代评审
      ### 迭代记录
      - 第 1 轮：X 个 CRITICAL / Y 个 HIGH / Z 个 MEDIUM / W 个 LOW
      - 第 2 轮：...（记录每轮修复后的问题数变化）
      - 最终轮次：第 N 轮 | 结果：CRITICAL/HIGH 已清零 / 达到上限仍有未解决问题

      ### 当前遗留问题
      #### CRITICAL — 必须修复（AI 迭代未能消除时才有此节）
      - [C1] 描述 | 位置 | 未能修复原因
      #### HIGH — 应修复（AI 迭代未能消除时才有此节）
      - [H1] 描述 | 位置 | 修复建议
      #### MEDIUM — 建议修复
      - [M1] 描述 | 位置 | 修复建议
      #### LOW — 可选优化
      - [L1] 描述 | 位置 | 修复建议

      ## 人员交叉评审
      ### 评审人：<姓名> | 角色：<技术 leader / 开发人员> | 子系统：<名称> | 日期：<YYYY-MM-DD>
      - [意见] 描述 | 修复建议
      （每位评审人独立一节）

      ## 技术 Leader 签字
      - **签字人**：<姓名>
      - **日期**：<YYYY-MM-DD>
      - **结论**：APPROVED / CONDITIONAL / REJECTED
      - **备注**：<补充说明，如遗留风险、后续关注点>

      === 通过标准 ===

      review 的通过由技术 leader 签字决定：
      - **APPROVED**：AI 评审的 CRITICAL/HIGH 已全部修复，leader 认可方案，进入 tasks
      - **CONDITIONAL**：需修复指定问题后重新评审
      - **REJECTED**：方案需重大调整，回到 design 阶段

      说明：
      - AI 评审的 CRITICAL/HIGH 是硬门禁——未修复则 leader 不应签 APPROVED
      - AI 评审的 MEDIUM/LOW 由 leader 裁定是否需要修复
      - 其他子系统开发人员的意见由 leader 综合考虑后裁定
      - 人员意见与 AI 意见冲突时，以 leader 裁定为准
    requires:
      - specs
      - design

  - id: tasks
    generates: tasks.md
    description: TDD 粒度的实现任务清单
    template: tasks.md
    instruction: |
      创建 TDD 粒度的实现任务清单。

      前置条件（必须验证）：
      - 检查 review.md 中"技术 Leader 签字"部分，结论必须为 APPROVED
      - 如签字缺失或结论非 APPROVED，拒绝生成 tasks 并提示用户完成评审

      === 实现任务（bite-sized，每个 task 2-5 分钟）===

      每个实现任务包含以下子步骤：

      ```
      - [ ] N.M <任务描述>
        - [ ] N.M.1 TEST: 编写失败测试（精确文件路径 + 完整测试代码）
        - [ ] N.M.2 VERIFY-RED: 运行测试确认失败（精确命令 + 预期输出）
        - [ ] N.M.3 IMPL: 编写最小实现（精确文件路径 + 代码）
        - [ ] N.M.4 VERIFY-GREEN: 运行测试确认通过（精确命令 + 预期输出）
        - [ ] N.M.5 REFACTOR: 使用 /ky:refactor 命令进行代码简化重构
        - [ ] N.M.6 REVIEW: 代码检视（通用检视 + C 语言专项）
        - [ ] N.M.7 COMMIT: 提交（conventional commit 格式）
      ```

      Mock 纪律（防止测试在"真空环境"中通过）：
      - 子系统内部模块之间禁止 mock，测试必须走真实的内部调用链
      - 只允许 mock 子系统外部边界（外部 RPC、外部服务依赖）
      - 每个测试必须注释说明 mock 了什么、为什么必须 mock

      C 语言特定任务模板：
      - 测试使用 CMocka 框架，包含 setup/teardown
      - 编译命令包含 `-Wall -Wextra -Werror -fsanitize=address,undefined`
      - 涉及内存分配的 task 额外包含 valgrind memcheck 验证步骤
      - 涉及并发的 task 额外包含 valgrind helgrind 验证步骤

      并行标注：
      - 每个 task 标注 `[并行: 是/否]`，独立 task 可由不同 subagent 并行执行
      - 修改同一文件的 task 标注 `[并行: 否]`

      引用 spec 中的具体 Requirement 和 Scenario，确保每个 spec 条目都有对应 task。

      === 质量收尾任务（所有实现任务完成后执行）===

      在所有实现任务之后，追加以下质量任务：

      ```
      - [ ] Q.1 全量编译 + clang-tidy 静态分析
      - [ ] Q.2 全量单元测试（确保无回归）
      - [ ] Q.3 集成测试冒烟（integration-tester(A6) 执行核心路径验证）
      - [ ] Q.4 代码评审收尾（code-reviewer(A3) 全量 diff 评审）
      ```
    requires:
      - review

apply:
  requires: [tasks]
  tracks: tasks.md
  instruction: |
    按 tasks.md 逐条实现。每个实现 task 严格按 TDD 步骤执行：
    1. 写测试 → 2. 确认红色 → 3. 写实现 → 4. 确认绿色 → 5. /ky:refactor 重构 → 6. 代码检视 → 7. 提交
    全部实现 task 完成后，执行质量收尾任务（Q.1-Q.4）。

    实现前执行置信度检查：
    - 是否理解需求？（检查对应 spec）
    - 是否理解技术方案？（检查 design）
    - 是否存在未解决的依赖？

    C 语言编译检查：
    - 每次实现后运行 `gcc -Wall -Wextra -Werror -fsyntax-only` 快速验证
    - 每次提交前运行 `clang-tidy` 静态分析

    遇到阻塞时暂停并报告，不要猜测。
```

**Artifact 依赖图**（对比 spec-driven 新增了 review）：

```
spec-driven:                     spec-driven-enhanced:

    proposal                         proposal
    │     │                          │     │
    ▼     ▼                          ▼     ▼
  specs  design                    specs  design
    │     │                          │     │
    └──┬──┘                          └──┬──┘
       ▼                                ▼
     tasks                           review（新增：评审门禁）
                                        │
                                        ▼
                                      tasks（增强：TDD 粒度）
```

### 3.2a openspec/config.yaml（C 语言 + 分布式存储上下文注入，仅特性级）

> 注意：config.yaml 仅服务于特性级的 spec-driven-enhanced schema。产品级已脱离 OpenSpec，由启发式 Skills 驱动。

```yaml
# openspec/config.yaml — 各子系统代码仓各自维护一份
schema: spec-driven-enhanced    # 默认使用增强版特性工作流

# 产品级文档基础路径（子仓库需修改为 teamskills 的实际路径）
# schema instruction 中的 docs/ 引用会被替换为此路径
product_docs_base: docs/        # teamskills 本仓默认值；子仓库示例：../teamskills/docs/

context: |
  技术栈：C 语言（C11/C17 标准）、Linux 系统编程
  领域：分布式存储系统
  目标平台：ARM + x86 双架构

  核心质量约束（影响 spec 场景设计和 design 技术决策）：
  - 数据一致性：副本一致、故障后数据完整
  - 并发正确性：无死锁、无竞态
  - 内存安全：无泄漏、无越界
  - 性能：低延迟、高吞吐

rules:
  proposal:
    - 尽量追溯到产品级 iteration-plan 中的条目；如无对应条目，说明原因
    - 涉及数据路径变更时必须说明一致性影响
    - 涉及性能关键路径时必须说明延迟/吞吐量影响
  specs:
    - 每个 Scenario 的粒度必须可直接转化为 CMocka 测试用例
    - 分布式场景必须覆盖：正常路径 + 节点故障 + 网络分区 + 并发冲突
  design:
    - 必须包含数据结构内存布局设计
    - 必须包含并发设计（锁策略/无锁设计/线程模型）
    - 必须包含错误处理链设计
    - 关键决策使用 ADR 格式
  review:
    - CRITICAL 级别必须包含：内存安全、并发正确性、数据一致性问题
    - CRITICAL/HIGH 问题阻塞进入 tasks 阶段
  tasks:
    - 每个实现 task 必须包含 TDD 步骤（TEST/VERIFY-RED/IMPL/VERIFY-GREEN/REFACTOR[/ky:refactor]/REVIEW/COMMIT）
    - 所有实现 task 之后必须追加质量收尾任务（全量 /ky:refactor + 全量代码检视 + 单元测试覆盖率 ≥ 80%）
    - 测试代码使用 CMocka 框架
    - 编译包含 -Wall -Wextra -Werror -fsanitize=address,undefined
```

---

## 四、目录结构

teamskills 本身的目录结构和子仓库使用后的目录结构是两件事，分开定义。

### 4.1 teamskills 仓库目录结构

```
teamskills/
├── CLAUDE.md                              # 项目指导
│
├── docs/                          # ★ 产品级交付物（不在 openspec/ 下）
│   ├── vision.md                          #   产品愿景
│   ├── architecture/                      #   架构设计
│   │   ├── design.md                      #     系统级总纲
│   │   └── <subsystem>/                   #     子系统架构
│   ├── adr.md                             #   架构决策记录（跨架构与需求）
│   ├── requirements/                      #   需求规格
│   │   └── <feature-domain>.md
│   ├── interfaces/                        #   接口规格
│   │   └── <subsystem>.md
│   └── iteration-plan.md                  #   迭代计划 + proposal 清单
│
├── .claude/                               # ★ Claude Code 标准扩展目录
│   │                                      #   子仓库通过目录级 symlink 引用
│   ├── skills/                            #   ★ 自建技能（14 个）
│   │   ├── product/                       #     产品级（6 个）— 解决 P1+P4+P5
│   │   │   ├── explore/SKILL.md           #       探索性思考
│   │   │   ├── define/SKILL.md            #       定义性思考
│   │   │   ├── plan/SKILL.md              #       规划性思考
│   │   │   ├── review/SKILL.md            #       审视性思考
│   │   │   ├── test-design/SKILL.md       #       测试策略设计
│   │   │   └── verify/SKILL.md            #       全量双向一致性检查
│   │   └── code/                          #     代码级（8 个）— 解决 P2+P3+P6
│   │       ├── tdd-workflow/SKILL.md
│   │       ├── code-review/SKILL.md
│   │       ├── spec-review/SKILL.md       #       特性级交付件评审
│   │       ├── code-refactor/SKILL.md
│   │       ├── parallel-develop/SKILL.md
│   │       ├── lint-check/SKILL.md
│   │       ├── git-worktree/SKILL.md
│   │       └── systematic-debug/SKILL.md  #       系统化调试
│   │
│   ├── agents/                            #   ★ Agent 角色（10 个）
│   │   ├── architect.md                   #     A1 架构师
│   │   ├── developer.md                   #     A2 开发工程师
│   │   ├── code-reviewer.md               #     A3 代码评审工程师
│   │   ├── debugger.md                    #     A4 调试工程师
│   │   ├── frontend-developer.md          #     A5 前端开发工程师
│   │   ├── integration-tester.md          #     A6 集成测试工程师
│   │   ├── perf-tester.md                 #     A7 性能测试工程师
│   │   ├── security-engineer.md           #     A8 安全工程师
│   │   ├── doc-writer.md                  #     A9 文档工程师
│   │   └── project-manager.md             #     A10 项目经理（反馈闭环编排）
│   │
│   ├── commands/                          #   ★ 用户触发命令（13 个，/ky: 前缀）
│   │   ├── explore.md                     #     C1 产品级：探索架构方案
│   │   ├── define.md                      #     C2 产品级：定义需求接口
│   │   ├── plan.md                        #     C3 产品级：制定迭代计划
│   │   ├── product-review.md              #     C4 产品级：多维评审
│   │   ├── test-design.md                 #     C5 产品级：测试策略设计
│   │   ├── verify.md                      #     C6 产品级：全量一致性检查
│   │   ├── tdd.md                         #     C7 代码级：TDD 开发
│   │   ├── review.md                      #     C8 代码级：代码评审
│   │   ├── spec-review.md                 #     C9 代码级：特性级交付件评审
│   │   ├── refactor.md                    #     C10 代码级：代码重构
│   │   ├── lint.md                        #     C11 代码级：编译检查+静态分析
│   │   ├── switch-worktree.md             #     C12 代码级：切换 worktree
│   │   └── debug.md                       #     C13 代码级：系统化调试
│   │
│   ├── rules/                             #   ★ 规则文件（4 个）
│   │   ├── workflow.md                    #     R1 四层工作流规范（全局）
│   │   ├── git-workflow.md                #     R2 git 协作规范（全局）
│   │   ├── coding-style.md                #     R3 C 语言编码规范（*.c/*.h）
│   │   └── testing.md                     #     R4 测试分层标准（*.c/*.h）
│   │
│   └── hooks.json                         #   ★ 自动化钩子（3 条）
│
├── openspec/                              # ★ OpenSpec 扩展（仅特性级）
│   ├── schemas/
│   │   └── spec-driven-enhanced/          #   特性级增强 schema（5 个 artifact）
│   │       ├── schema.yaml
│   │       └── templates/
│   │           ├── proposal.md
│   │           ├── spec.md
│   │           ├── design.md
│   │           ├── review.md              #   ← 新增：设计评审模板
│   │           └── tasks.md               #   ← 增强：TDD 粒度模板
│   └── config.yaml.template              #   C 语言 + 分布式存储上下文（模板）
│
├── templates/                             # ★ 产品级文档参考模板
│   └── product/
│       ├── vision.md
│       ├── architecture.md
│       ├── requirements.md
│       ├── interface.md
│       └── iteration-plan.md
│
├── scripts/                               # 辅助脚本
│   ├── install.sh                         #   ★ 子系统代码仓集成脚本
│   └── repos.yaml                         #   夜间 CI 子系统仓库列表
│
└── docs/                                  # teamskills 自身的设计文档
    ├── design-proposal.md                 #   索引文件
    ├── architecture.md                    #   架构与基础
    ├── product-feature-schema.md          #   产品级与特性级设计
    ├── extensions-catalog.md              #   扩展清单
    ├── workflow.md                        #   工作流串联
    ├── team-and-sync.md                   #   团队协作与变更同步
    ├── feedback-loop.md                   #   反馈闭环
    └── decisions-and-plan.md              #   决策与实施计划
```

### 4.2 子仓库集成后的目录结构

子仓库执行 `scripts/install.sh` 后产生的目录结构：

```
<sub-repo>/
├── .claude/
│   ├── skills   → symlink → teamskills/.claude/skills
│   ├── agents   → symlink → teamskills/.claude/agents
│   ├── commands → symlink → teamskills/.claude/commands
│   ├── rules    → symlink → teamskills/.claude/rules
│   └── hooks.json → symlink → teamskills/.claude/hooks.json
│
├── openspec/
│   ├── schemas/
│   │   └── spec-driven-enhanced → symlink → teamskills/openspec/schemas/spec-driven-enhanced
│   └── config.yaml              # 从模板复制，子仓库自行修改 context 部分
│
└── ... (子仓库自身代码)
```

### 4.3 分发机制

统一使用**目录级 symlink**，由 `scripts/install.sh` 自动完成：

| 扩展类型 | 分发方式 | 说明 |
|---------|---------|------|
| skills | 目录级 symlink | Claude Code 自动发现 |
| agents | 目录级 symlink | Claude Code 自动发现 |
| commands | 目录级 symlink | Claude Code 自动发现 |
| rules | 目录级 symlink | Claude Code 自动发现 |
| hooks.json | 文件级 symlink | 单文件，直接 symlink |
| openspec schema | 目录级 symlink | OpenSpec 自有查找机制 |
| openspec config | 复制模板 | 子仓库需自定义 context |

子仓库不自行定义扩展，所有增强统一修改 teamskills。
