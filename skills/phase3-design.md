# Phase 3 设计文档：代码级日常工作流 — 开发者每日可用

## 目标

建立完整的日常开发循环：TDD（RED-GREEN-REFACTOR）+ 代码评审 + 代码简化重构 + 静态分析检查 + worktree 隔离并行开发 + 自动化 Hook 守护。使开发者在特性级 task 约束下，能够高质量、低风险地完成代码交付。

## 前置依赖

- Phase 2（R1 `workflow` 已建立，产品级文档和生产约束就绪）
- Phase 1（OpenSpec 特性级 schema 可用，tasks.md 模板中的 TDD 步骤可被引用）

## 为什么这些能力集中在 Phase 3？

1. **代码级 Skill 受 R1 `workflow` 约束**：四层体系的流程规则、文档追溯关系、测试分层定义必须在 Phase 2 完成后才能被代码级能力引用。
2. **TDD 是日常开发的基础循环**：`tasks.md` 模板中的每个 task 默认包含 TDD 步骤（步骤 N.M.5 调用 `/ky:refactor`），因此 `code/tdd-workflow` 和 `code/code-refactor` 必须在特性级大量开发前就绪。
3. **并行开发需要隔离机制**：worktree 隔离是后续多 Agent 并行协调（Phase 4 `code/parallel-develop`）的基础设施。

---

## 交付物设计

### 3.1 Skills

#### 3.1.1 Skill: `code/tdd-workflow`（TDD 铁律）

**文件路径**：`.claude/skills/code/tdd-workflow/SKILL.md`

**解决**：P3（代码开发阶段能力不足）

**执行角色**：`developer`(A2)

**设计思路**：
- 严格遵循 "NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST"
- 每个 TDD 循环拆分为 RED → GREEN → REFACTOR 三个阶段，明确各阶段成功标准
- 针对 C 语言 + Linux + 分布式存储场景，提供具体测试框架建议（优先 `cmocka`，proposal 收尾阶段通过 `valgrind` 检测内存泄漏）
- 每完成一个 task 的小步骤（如步骤 N.M）执行一次 TDD 循环

**SKILL.md 结构**：

```yaml
---
name: code/tdd-workflow
description: TDD 铁律开发工作流——RED-GREEN-REFACTOR，针对 C 语言项目
version: 1.0.0
allowed-tools: [Read, Write, Edit, Bash, Grep, Glob, Agent]
---
```

**正文内容**：

````markdown
# code/tdd-workflow — TDD 铁律开发工作流

## 概述

RED → GREEN → REFACTOR。没有先失败的测试，决不写生产代码。

**核心原则**：
- **测试先行**：每个功能增量必须有测试失败作为起点
- **最小步长**：每个步骤只解决当前测试失败，不超前实现
- **绿色保障**：REFACTOR 阶段必须保持测试常绿
- **内存安全**：proposal 收尾及 `/ky:lint --full` 阶段集成 valgrind，确保无泄漏、无越界

## 何时使用

- 实现单个 OpenSpec task（尤其是 tasks.md 中的步骤 N.M）
- 为现有函数补充缺失单元测试
- 重构思路上需要测试保驾护航的代码修改

## 与 tasks.md 的映射

spec-driven-enhanced 的 tasks 模板将每个实现 task 拆为 7 步：

```
N.M.1 TEST      → /ky:tdd 的 RED 阶段
N.M.2 VERIFY-RED  → /ky:tdd 的 RED 阶段
N.M.3 IMPL      → /ky:tdd 的 GREEN 阶段
N.M.4 VERIFY-GREEN → /ky:tdd 的 GREEN 阶段
N.M.5 REFACTOR  → /ky:refactor（本 skill 的 REFACTOR 阶段调用）
N.M.6 REVIEW    → /ky:code-review（输出评审报告）
N.M.7 FIX-REVIEW → developer 读取评审报告，修复 CRITICAL/HIGH 问题
N.M.8 COMMIT    → git commit
```

`/ky:tdd` 覆盖步骤 N.M.1 ~ N.M.4，产出测试代码和生产代码的最小实现。

`/ky:code-review` 输出评审报告后，由 `developer`（或 feedback-loop）在 N.M.7 阶段按 CRITICAL → HIGH 顺序修复，修复后必须通过回归测试。

## 核心流程

### 阶段 1：RED（写一个失败的测试）

**成功标准**：编译通过但测试失败（断言失败或预期错误）。

**步骤**：
1. 读取当前 task 的目标和 specs/design 约束
2. 确定本次要暴露的行为缺口
3. 在测试文件中编写最小测试用例
4. 运行测试，确认失败，记录失败信息

**C 语言测试建议**：
- 使用 `cmocka` 作为单元测试框架
- 测试文件命名：`tests/test_<module>_<scenario>.c`
- Mock 外部依赖时，优先使用链接期桩函数（link seam），避免侵入式宏修改

**红旗自查**：
- 🚩 测试一开始就通过了（说明测试没测到目标行为）
- 🚩 测试写了太多断言（应只有一个核心断言暴露缺口）
- 🚩 直接复制了生产代码到测试里（测试成了实现的影子）

### 阶段 2：GREEN（用最快速度让测试通过）

**成功标准**：所有测试通过（返回码 0）。

**步骤**：
1. 写最小量生产代码使测试通过
2. 运行测试确认通过

**阶段性容忍（必须在 REFACTOR 阶段清理）**：
- 直接返回硬编码值
- 复制粘贴重复逻辑
- 用最直白的方式实现条件分支

**边界说明**：
这些临时写法仅在当前测试与下一次 REFACTOR 之间短暂存在，**不得在未重构的情况下直接提交**。如果因为时间或其他原因跳过 REFACTOR，这些临时代码必须被标记为 TODO/FIXME 并在后续 task 中清理。

**禁止的操作**：
- 提前实现未被测试覆盖的行为
- 引入复杂抽象（提前设计）
- 优化性能（留在 REFACTOR 阶段）
- 以“GREEN 允许丑代码”为借口跳过 REFACTOR

### 阶段 3：REFACTOR（调用 `/ky:refactor` 简化重构）

**成功标准**：测试保持绿色，代码质量提升。

**步骤**：
1. 识别代码异味：重复、过长函数、魔法数字、不清晰命名
2. 执行安全重构（提取函数、重命名变量、消除重复）
3. 运行测试确认绿色
4. 如需进一步简化，调用 `/ky:refactor`

**REFACTOR 期间必须检查**：
- [ ] 所有测试通过
- [ ] 圈复杂度未显著上升
- [ ] 每个 C 函数返回值都被检查

> valgrind 内存检测留在 proposal 收尾或 `/ky:lint --full` 阶段执行，不阻塞 TDD 小步循环。

## 铁律检查

```
NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST
```

## 常见借口与回应

| 借口 | 回应 |
|------|------|
| "测试框架还没搭好" | 先花 10 分钟写一个最小可运行的 `main.c` 测试桩 |
| "这太简单了，边写边测就行" | 简单代码也请写至少一个边界测试 |
| "TDD 不适合 C 语言" | 这是本团队的工作方式，cmocka + valgrind 已经验证可行 |

## 输出位置

- 测试文件：`tests/test_<module>_<scenario>.c`
- 生产代码：对应 task 指定的源文件
- 运行日志：终端输出或 `build/test-logs/`

## Integration

- **前置 Command**: `/opsx:apply`（提供当前 task 上下文）
- **后续 Command**: `/ky:refactor`（GREEN 后的代码简化）
- **相关 Rules**: R3 `coding-style`, R4 `testing`
````

---

#### 3.1.2 Skill: `code/code-review`（三级评审管线）

**文件路径**：`.claude/skills/code/code-review/SKILL.md`

**解决**：P3, P6（代码开发阶段能力不足、缺少文档/代码评审手段）

**执行角色**：`code-reviewer`(A3)

**设计思路**：
- 采用 everything-claude-code 中的分级评审标准：CRITICAL → HIGH → MEDIUM → LOW
- 代码评审员（A3）只审不写，与 developer（A2）分离，保证评审客观性
- 针对 C 语言和分布式存储场景增加专项检查点：内存安全、并发正确性、错误处理完备性
- **自适应评审模式**：根据变更范围自动选择单 agent 轻量评审（<300 行）或多 agent 深度评审（≥300 行或 3+ 模块），避免高频小评审过度启动 subagent

**SKILL.md 结构**：

```yaml
---
name: code/code-review
description: 三级代码评审管线——通用质量 → C 语言专项 → 安全审计
version: 1.0.0
allowed-tools: [Read, Grep, Bash, Agent]
---
```

**正文内容**：

````markdown
# code/code-review — 三级代码评审管线

## 概述

通用质量检查 → C 语言专项检查 → 安全审计。逐层深化，定点输出。

**核心原则**：
- **只审不写**：评审员提出问题和建议，由 developer 修改
- **分级明确**：CRITICAL 必须修，HIGH 强烈建议修，MEDIUM 优化建议，LOW 风格提示
- **证据说话**：每个问题必须引用代码行并提供改进方案

## 何时使用

- 完成一个 task 或一组相关修改后
- 提交 Pull Request 前
- 特性级 `/opsx:verify` 之前作为自检

## 评审流程

### Level 1：通用质量检查

| 检查项 | 通过标准 | 分布式存储系统调整说明 |
|--------|----------|----------------------|
| **单函数长度** | **常规函数**：≤300 行可接受，>800 行 HIGH，>1200 行 CRITICAL（必须拆分）<br>**状态机/热路径**：≤600 行可接受，>1000 行 HIGH，>1500 行 CRITICAL（必须拆分） | 参考 Ceph、PostgreSQL 等内核级项目，`handle_message()`、`ms_dispatch()`、`ExecProcNode()` 等核心分发函数常见 400–1000 行。只要职责单一且状态/阶段注释清晰，状态机函数可达 600 行；超过 1200/1500 行会严重降低可维护性，必须拆分 |
| **圈复杂度** | **常规函数**：≤30 可接受，>60 HIGH，>100 CRITICAL（必须拆分）<br>**状态机/协议处理**：≤80 可接受，>120 HIGH，>150 CRITICAL（必须拆分） | 带大量 `switch/case` 和错误处理的消息分发函数，复杂度 40–100 属常见；超出 150 已接近失控，必须拆分为子状态处理函数 |
| 命名清晰 | 函数名表达动作/返回，变量名表达含义 | — |
| 注释必要 | 复杂算法、非直观优化、接口契约需注释 | — |
| 无死代码 | 未使用的函数/变量已删除 | — |

**核心原则：职责内聚 > 绝对行数**。一个函数只做一件事，即使 800 行也是可接受的；如果做了两件事，即使 200 行也应拆分。

**C 语言常见豁免场景**：
- **IO 路径/热路径**（如 `wal_write()`、`replica_handle_sync()`）：允许紧凑内联（可达 400–800 行），优先保持性能；拆分时应提取为 `static inline` 辅助判断，不引入额外栈帧
- **协议状态机/消息分发**（如 `handle_message()`、`ms_dispatch()`、`process_request()`）：`switch` 分发表较长时，允许主函数达 400–1000 行；具体状态处理逻辑应拆分为 `handle_xxx_state()` 子函数
- **初始化/销毁/资源释放**：线性流程（注册回调、分配资源、校验参数）允许 300–600 行；超过 800 行应按资源子系统拆分（如 `init_metadata()`、`init_network()`）
- **错误处理链**：因 C 语言无异常机制，成块的 `if (rc < 0) { ...; goto cleanup; }` 不计入"职责分散"，但鼓励用宏简化重复模式

**Red Flag（与行数无关，必须拆分）**：
- 一个函数里同时包含"计算决策"和"执行动作"
- 一个函数里混入了完全无关的两类资源操作
- 长函数（>800 行）且控制流出口分散在 3 层以上嵌套中，导致无法快速追踪错误路径

### Level 2：C 语言专项检查

**内存安全**：
- [ ] 每次内存分配（`malloc`/`calloc`/`realloc` 或项目自定义分配器/封装函数，如 `mem_alloc`、`pool_alloc`、`slab_alloc`）都有对应的释放路径（`free` 或对应的 `mem_free`、`pool_free` 等）
- [ ] 数组访问都有边界检查或已证明安全
- [ ] 指针解引用前已验证非 NULL
- [ ] 字符串操作使用长度限制版本（`strncpy`、`snprintf`）
- [ ] 无 use-after-free、double-free

**并发正确性**：
- [ ] 锁的获取和释放配对，无死锁风险
- [ ] 全局/共享状态的访问有同步保护
- [ ] 锁序一致（若存在多锁嵌套）

**错误处理完备性**：
- [ ] 每个系统调用和库函数的返回值都被检查
- [ ] 错误路径有明确的日志记录或错误码返回
- [ ] 无静默吞错（空 catch/空 if 分支）

### Level 3：安全审计

- [ ] 无硬编码密钥、密码、token
- [ ] 无整数溢出风险（尤其分配大小计算）
- [ ] 无格式化字符串漏洞
- [ ] 无命令注入风险（评估 system()/popen() 调用）

## 评审输出格式

```markdown
### CRITICAL（阻塞合并）

- `[文件:行号]` 问题描述
  - **证据**：引用代码片段
  - **建议**：具体修改方案

### HIGH（强烈建议修改）
...

### MEDIUM
...

### LOW
...
```

## 输出位置

- 评审报告临时输出至：`/tmp/code-review-report-<timestamp>.md`
- 供 `developer` 或 feedback-loop 读取并按优先级修复
- **生命周期**：修复验证通过后自动删除，不保留归档

## 铁律检查

- 有 CRITICAL 问题 = 不能继续 Merge
- 有未处理的 HIGH 问题 = 需要 developer 确认

## Integration

- **前置 Command**: `/ky:tdd`（代码已完成，测试已绿）
- **后续 Command**: `/ky:refactor`（针对评审意见修改后再次简化）
- **相关 Rules**: R3 `coding-style`, R4 `testing`
````

---

#### 3.1.3 Skill: `code/code-refactor`（代码简化重构）

**文件路径**：`.claude/skills/code/code-refactor/SKILL.md`

**解决**：P3

**执行角色**：`developer`(A2)

**设计思路**：
- 是 TDD 循环的第三阶段日常补充
- 聚焦简化：消除重复、缩短函数、澄清命名、降低复杂度
- 不信任无测试护航的重构，强制先运行测试

**SKILL.md 结构**：

```yaml
---
name: code/code-refactor
description: 测试护航下的代码简化重构——消除重复、降低复杂度、澄清意图
version: 1.0.0
allowed-tools: [Read, Write, Edit, Bash, Grep, Glob]
---
```

**正文内容**：

````markdown
# code/code-refactor — 代码简化重构

## 概述

在测试绿色前提下，让代码更简单、更清晰、更易于维护。

**核心原则**：
- **测试先行运行**：重构前必须确认所有测试通过
- **小步快跑**：每次只做一种重构
- **禁止猜测**：不为假设的未来需求引入抽象
- **简化优先**：消除重复 > 提取抽象

## 何时使用

- TDD 循环的 REFACTOR 阶段（步骤 N.M.5）——**小步重构**，每次只处理一种明显异味
- 代码评审后的修改清理
- OpenSpec archive 前的最终整理

## 与 `code/simplify` 的关系

`code/code-refactor` 是**测试护航下的轻量重构**，聚焦结构层面的 4 种基础异味；`code/simplify` 是**基于 git diff 的批量三维度深度清理**（复用/质量/效率），通过 3 个 subagent 并行评审。

| 维度 | `code/code-refactor` | `code/simplify` |
|------|---------------------|-----------------|
| 触发时机 | 每个 task 完成后（高频） | 一批变更完成后（低频） |
| 执行方式 | 单 agent 小步快跑 | 3 个 review agent 并行 |
| 关注范围 | 消除重复、缩短函数、澄清命名、降低复杂度 | 代码复用、hacky 模式、性能效率 |
| 成本 | 低（秒级到分钟级） | 中到高（需启动多个 subagent） |

**建议配合方式**：
- 日常 TDD 循环使用本 skill 完成快速 REFACTOR（`/ky:refactor` 的默认轻量模式）
- 当单个 task 或一组 task 的变更较大（>200 行）时，`/ky:refactor` 会自动切换到深度模式（调用 `code/simplify` skill），或手动通过 `/ky:refactor --deep` 强制触发
- archive 前的最终整理可调用 `/ky:refactor --deep` 确保没有遗漏的复用机会和效率问题

## 重构清单

### 1. 消除重复（DRY）

- 相同的字面量 → 提取为具名常量
- 相同的条件判断 → 提取为辅助函数
- 相同的错误处理模式 → 提取为宏或内联函数

### 2. 缩短函数

- 函数超过 300 行 → 评估是否按职责拆分（常规函数），状态机/热路径可放宽至 600–800 行
- 函数做了两件不同的事 → 无论多短都应拆分
- 函数超过 1200 行（常规）/ 1500 行（状态机/热路径）→ 必须拆分
- 同一逻辑分支内嵌套超过 4 层且难以一眼看清出口 → 使用卫语句或提前返回简化
- 参数超过 5 个 → 考虑封装为结构体

### 3. 澄清命名

- 函数名应当说明"做什么"，而非"怎么做"
- 布尔变量使用 `is_`/`has_`/`can_` 前缀
- 避免单字母变量（循环变量 `i`/`j` 除外）

### 4. 降低复杂度

- 复杂条件表达式 → 提取为谓词函数
- 大规模 switch → 考虑函数指针表
- 冗长初始化 → 提取为独立构造函数

## 执行流程

1. **绿色确认**：运行全部测试，确认通过
2. **选择目标**：从上述清单中挑选最显著的一个异味
3. **执行重构**：修改代码
4. **快速验证**：运行测试确认绿色（valgrind 留到 proposal 收尾或 `/ky:lint --full`）
5. **循环或退出**：如还有明显异味，返回步骤 2；否则停止

## 红旗信号

- 🚩 重构后测试变红（立即停止，回退到上一个绿色状态）
- 🚩 引入了新的抽象但只使用一次（过度设计）
- 🚩 把一个长函数拆成了十几个极小函数（碎片化）

## Integration

- **前置 Command**: `/ky:tdd` 或 `/ky:code-review`
- **相关 Rules**: R3 `coding-style`
````

#### 3.1.6 Skill: `code/simplify`（复用/质量/效率三维度深度清理）

**文件路径**：`.claude/skills/code/simplify/SKILL.md`

**解决**：P3

**执行角色**：`developer`(A2) 作为主调度，`code-reviewer`(A3) 承担具体评审

**设计思路**：
- 直接借鉴 Claude 官方 `/simplify` 的三 agent 并行评审模式，将其内建为 teamskills 自建 skill
- 面向 C 语言 + 分布式存储场景，对复用、质量、效率三个维度做深度检查
- 与 `/ky:refactor` 形成互补：refactor 做小步高频简化，simplify 做批量低频深度清理

**SKILL.md 结构**：

```yaml
---
name: code/simplify
description: 复用/质量/效率三维度深度清理——基于 git diff 的批量 code review 与修复
version: 1.0.0
allowed-tools: [Read, Bash, Grep, Glob, Agent]
---
```

**正文内容**：

````markdown
# code/simplify — 三维度深度清理

## 概述

复用检查 → 质量检查 → 效率检查。基于 git diff 对批量变更做三 agent 并行评审，并由 developer 汇总修复。

## 何时使用

- 单个 task 或一组 task 的变更量较大（>200 行）
- archive 前最终整理
- `/ky:refactor` 后发现仍有明显异味
- 特性级 `/opsx:apply` 的 Q.4 阶段（全量 diff 评审后）

## 执行流程

### Phase 1：识别变更

**目标**：获取本次 proposal 的全部代码变更，而非仅最近一个 commit。

**策略**：
1. 优先获取当前 feature branch 相对于 `main` 的完整 diff：
   ```bash
   BASE=$(git merge-base HEAD main)
   git diff $BASE..HEAD
   ```
2. 若无法获取（如未从 main 分岔、分支未 push），fallback 到：
   - `git log --oneline -n 5` 推断最近几个 commit 是否同属本次 proposal
   - 或读取当前 worktree 关联的 proposal 信息，定位 `/opsx:apply` 的初始 commit
3. 最后检查是否有未提交的 staged/unstaged 变更，一并纳入

> 避免直接使用无参数的 `git diff`——那只会看到最近一次 commit 以内的变更，前面的 tasks 会被漏掉。

### Phase 2：启动三评审 Agent 并行

同时启动 3 个 subagent，各获得完整 diff 和以下指令约束。

#### Agent 1：复用检查（Code Reuse Review）

**目标**：检查新来的代码是否重复造轮子。

1. 搜索现有 utilities / helpers / 公共模块（重点关注 `src/utils/`、`src/common/`、相邻模块）
2. 指出与已有函数仅参数/命名略有差异的新增函数
3. 指出手造的字符串/路径/环境处理逻辑，检查是否可用现有工具替代
4. 指出重复出现的 >3 行逻辑块（出现 >2 处）

**输出格式**：
```markdown
### 复用问题
- `[file:line]` 问题描述
  - **现有替代**：`src/xxx/yyy.c:func_name()`
  - **建议**：直接调用现有函数 / 提取公共辅助函数
```

#### Agent 2：质量检查（Code Quality Review）

**目标**：发现 hacky 模式、过度设计、坏味道。

1. **冗余状态**：新加的 state 是否可由已有 state 派生
2. **参数膨胀**：是否通过新增参数解决，而非重构数据结构
3. **复制粘贴**：仅命名/条件略有差异的重复代码块
4. **泄露抽象**：暴露了内部细节，或破坏了已有抽象边界
5. **过度包装**：无意义的中间层、冗余宏、空函数转发
6. **无意义注释**：解释了 WHAT 而非 WHY 的注释，或带任务编号的注释

**C 语言特有加项**：
- 检查是否引入了新的 `malloc`/`free` 模式，而项目内已有统一内存池
- 检查锁/无锁结构的使用是否已有更成熟的内部封装可用
- 检查错误处理是否混用了不同风格（如有的用 `goto cleanup`，有的用 `return rc`）

**输出格式**：
```markdown
### 质量问题
- `[file:line]` 问题描述
  - **类型**：冗余状态 / 参数膨胀 / 复制粘贴 / 泄露抽象 / 过度包装 / 无意义注释
  - **建议**：...
```

#### Agent 3：效率检查（Efficiency Review）

**目标**：发现性能陷阱和不必要的开销。

1. **不必要的工作**：循环内重复计算、重复文件读取、重复内存分配
2. **热路径膨胀**：新的阻塞调用/锁/分配是否加在了每次请求/IO 都走的路径上
3. **锁粒度**：全局锁保护细粒度操作、锁内嵌套过深
4. **批处理机会**：逐条 IO/请求是否可改为批量提交
5. **内存**：循环内的大缓冲区分配、无界数据结构增长、泄漏风险
6. **IO 开销**：预检查文件存在性再操作（TOCTOU）、读全文件只需部分

**C 语言/分布式存储特有加项**：
- 检查 `memcpy` 是否可用零拷贝替代
- 检查大锁是否保护了无共享状态的路径
- 检查序列化/反序列化是否可被延迟或批量
- 检查故障恢复路径是否引入了全量扫描而非增量

**输出格式**：
```markdown
### 效率问题
- `[file:line]` 问题描述
  - **场景**：热路径 / 初始化路径 / 故障恢复路径
  - **影响**：延迟增加 / 吞吐下降 / 内存膨胀
  - **建议**：...
```

### Phase 3：汇总与修复

主 Agent（`developer`）等待三个 subagent 返回后：
1. 去重合并相同位置的问题
2. 评估每个问题的修复价值和风险
3. 逐个修复（保持测试绿色）
4. 运行全量测试 + valgrind 确认无回归
5. 对 false positive 简单标注并跳过，不展开争论

## 红旗信号

- 🚩 三个 agent 同时指出同一文件有问题（高置信度）
- 🚩 热路径上出现了 `malloc` 或锁
- 🚩 新文件/新函数的 50% 以上代码在别处已存在

## 与 `code/code-refactor` 的关系

| | `code/code-refactor` | `code/simplify` |
|---|---|---|
| 触发时机 | 每个 task 后 | 一批变更后 / archive 前 |
| 检查方式 | 单 agent，聚焦结构 | 3 subagent 并行，复用+质量+效率 |
| 成本 | 秒级–分钟级 | 分钟级 |
| 使用节奏 | 日常高频 | 低频深度 |

## Integration

- **前置 Command**: `/ky:code-review` 或 `/ky:refactor`（本 Skill 由 `/ky:refactor --deep` 触发）
- **后续 Command**: `/ky:lint`
- **Agent**: `developer` 调度，`code-reviewer` 作为 subagent
````

---

#### 3.1.4 Skill: `code/lint-check`（编译检查 + clang-tidy + valgrind）

**文件路径**：`.claude/skills/code/lint-check/SKILL.md`

**解决**：P3

**执行角色**：`developer`(A2)

**设计思路**：
- 面向 C 语言项目，提供编译检查、clang-tidy、valgrind 的集成调用方式
- 作为 `/ky:lint` 命令的底层 skill，也可以被其他 skill/agent 调用
- **只检查，不自动修复**：本 skill 仅输出检查报告，修复工作由 developer 在 `/ky:tdd` 或 `/ky:refactor` 中按需完成

**SKILL.md 结构**：

```yaml
---
name: code/lint-check
description: C 项目静态检查与内存安全检测——编译 + clang-tidy + valgrind
version: 1.0.0
allowed-tools: [Read, Bash, Grep, Glob]
---
```

**正文内容**：

````markdown
# code/lint-check — 编译检查与静态分析

## 概述

编译通过 → clang-tidy 检查 → valgrind 内存检测。三层防护，提前拦截问题。

**技能边界**：本 skill 仅执行检测并输出报告，不自动修改代码。

## 何时使用

- 编写或修改 C 代码后（fast 模式）
- 提交前最终检查（fast 模式）
- `/ky:tdd` GREEN 后快速验证（fast 模式）
- 特性级 archive 前或 Q.1 质量收尾（`--full` 模式）

## 检查层级

### L1：编译检查

**目标**：零 warning，零 error。

**策略**：
1. **优先使用项目自身构建脚本**：检测是否存在 `Makefile`、`CMakeLists.txt`、`build.sh`、`meson.build`、`configure` 等，直接调用对应构建命令（如 `make`、`cmake --build build`、`./build.sh`）。
2. **检查结果**：提取输出中的 `error:` 和 `warning:` 数量，确保全部为 0。
3. **分布式存储强制编译选项**（如 `-Wformat=2`、`-fstack-protector-strong`）应直接维护在项目的构建脚本中（如 `CMakeLists.txt`），由本 skill 通过 `Read` 检查确认存在即可，不在命令行硬编码。

### L2：clang-tidy

**目标**：捕获潜在 bug 和代码规范问题。

**执行前前置条件检查**：

1. **`.clang-tidy` 配置文件**：
   - 检查项目根目录是否存在 `.clang-tidy`。
   - 若存在，尊重并使用该配置，不额外覆盖 `-checks`。
   - 若不存在，提示用户创建，并给出推荐内容：
     ```yaml
     Checks: "bugprone-*,cert-*,clang-analyzer-*,cppcoreguidelines-*,performance-*,portability-*,readability-*"
     ```

2. **`compile_commands.json`**：
   - clang-tidy 需要此文件才能正确解析头文件路径和宏定义。
   - 检查项目根目录或 `build/` 目录下是否存在 `compile_commands.json`。
   - **若不存在**，停止 clang-tidy 检查并输出提示及生成命令：

     提示文本示例（输出给用户）：
     ```
     [WARNING] 未检测到 compile_commands.json，clang-tidy 无法准确分析头文件依赖和宏定义。

     生成方式（按构建系统选择）：
     - CMake：-DCMAKE_EXPORT_COMPILE_COMMANDS=ON
     - Makefile 项目：先安装 bear，然后 bear -- make clean && bear -- make
     - Meson：编译时自动生成，通常位于 builddir/compile_commands.json
     ```

**运行命令**（具备上述条件后）：
```bash
clang-tidy <sources>
```

**关键规则说明**：
- bugprone-*：悬垂指针、资源泄漏、错误使用 API
- cert-*：安全编码标准
- clang-analyzer-*：静态分析器深度检查（内存、死锁、空指针）
- cppcoreguidelines-*：C++ 核心准则中适用于 C 的部分（如宏使用限制）

### L3：valgrind 内存检测

**目标**：运行测试二进制，检测内存错误和泄漏。

**前提**：必须通过项目构建脚本先生成测试可执行文件。

**执行步骤**：

1. 确认测试二进制已存在（如 build/test_<module> 或 `./run-tests.sh ut` 生成的产物）。
2. 对测试二进制运行：
```bash
valgrind --leak-check=full --error-exitcode=1 ./<test-binary>
```
3. 若项目使用 ctest，可建议：
```bash
ctest -D ExperimentalMemCheck
```

## 输出解读与问题路由

**lint-check 的职责是验证而非修复**。它期望 0 错误，因为此时代码应已在 `/ky:tdd`、refactor 和 review 阶段被 developer 修复完毕。

若发现问题：
- **编译错误** → 停止提交，返回 developer 修复（通常在 /ky:tdd GREEN 就应消除）
- **clang-tidy 告警** → 返回 developer 修复；确认为误报的可经评估后在 .clang-tidy 中 suppress
- **valgrind 内存错误** → 返回 developer 修复，通常需在 TDD 中补充测试复现后再修复

## Integration

- **前置 Command**: /ky:tdd 或 /ky:refactor
- **执行时机**：
  - 高频（fast 模式）：单个 task 完成后的最终检查（在 git commit 前）
  - 中频（`--full` 模式）：/opsx:apply 的 Q.1 质量收尾阶段、archive 前
  - 自动：H1 pre-commit-lint 拦截存在严重问题的提交
- **问题修复方**：developer（A2）在执行 lint 之前完成修复
- **相关 Rules**: R3 coding-style
````

---

#### 3.1.5 Skill: `code/git-worktree`（worktree 并行开发）

**文件路径**：`.claude/skills/code/git-worktree/SKILL.md`

**解决**：P3

**执行角色**：`developer`(A2)

**设计思路**：
- 借鉴 superpowers 的 "Git worktree 并行开发" skill
- 默认以 proposal 为粒度创建隔离 worktree（一个 proposal 含多个小 task，都在同一 worktree 内完成）；多个 proposal 并行开发时才创建多个 worktree
- 提供统一的 worktree 命名、切换、清理规范

**SKILL.md 结构**：

```yaml
---
name: code/git-worktree
description: Git worktree 隔离并行开发——创建、切换、清理规范
version: 1.0.0
allowed-tools: [Read, Write, Edit, Bash, Grep]
---
```

**正文内容**：

````markdown
# code/git-worktree — worktree 隔离并行开发

## 概述

每个独立开发任务使用独立 worktree，避免本地分支污染和并行冲突。

**核心原则**：
- **默认粒度是 proposal**：一个 proposal（含其下属的 10+ 个小 task）使用一个 worktree 完成
- **按需隔离**：单个 proposal 内的 task 串行或同 worktree 内并行；多个 proposal 并行时才拆
- **命名规范**：`wt-<proposal>-<brief-desc>`（默认按 proposal）或 `wt-<proposal>-experiment`（A/B 验证）
- **主干保护**：不在 main 分支直接修改（H3 worktree-guard 守护）

**合并与拆分的判断标准**：
| 场景 | worktree 策略 |
|------|--------------|
| 单个 proposal 内的 task（默认） | 同一 worktree 内串行完成 |
| 单个 proposal 内无冲突的多 agent 并行 | 同一 worktree 内并行，无需拆分 |
| 多个 proposal 并行开发 | 每个 proposal 一个独立 worktree |
| 同一 proposal 的 A/B 验证或高风险重构 | 创建额外隔离 worktree |
| 代码评审需要干净环境 | 临时创建评审 worktree |

## 何时使用

- 启动一个新 proposal 的开发（默认创建一个 worktree）
- 多个 proposal 需要并行开发（每个 proposal 一个 worktree）
- 大型/高风险变更需要独立的隔离环境
- 需要为代码评审创建一个干净的验证环境

## worktree 管理规范

### 创建 worktree

```bash
# 基于当前分支创建新 worktree
git worktree add .claude/worktrees/wt-<name> -b feat/<name>
```

> Git worktree 共享原仓库的 `.git` 对象库，仅额外占用索引和工作目录，创建/切换成本秒级，磁盘开销很小。因此隔离的核心成本是**上下文切换的心智负担**，而非磁盘或性能。

**命名建议**：
| 场景 | 命名示例 |
|------|----------|
| proposal 开发（默认） | `wt-storage-wal` |
| A/B 验证/实验 | `wt-storage-wal-exp1` |
| 评审验证 | `wt-review-storage-wal` |

### 切换 worktree

使用 `/ky:switch-worktree <name>` 快速切换：
1. 保存当前 context（可选）
2. `cd .claude/worktrees/wt-<name>`（当前 shell session 的工作目录切换到该 worktree）
3. 更新 `~/.claude/projects/<repo-name>/active-worktree` 状态文件
4. 提示用户当前所在 worktree

**会话中断恢复**：
- Claude 重开后默认 CWD 为仓库根目录，不会自动进入活跃 worktree
- 此时 H3 `worktree-guard` 仍会拦截写操作
- **必须再次执行 `/ky:switch-worktree <name>`** 恢复 CWD 和完整上下文

### 清理 worktree

**自动清理入口**：使用 `/ky:finish-worktree` 完成开发工作并自动清理。参考 superpowers `finishing-a-development-branch` skill 的流程：
1. **验证测试**：运行全量单元测试，通过后方可继续
2. **呈现选项**：本地 merge / 推送创建 PR / 保持状态 / 丢弃
3. **执行选择**：根据选项执行对应 git 操作
4. **清理 worktree**：本地 merge 或丢弃后，自动执行下述清理命令；创建 PR 时**保留** worktree

**手动清理**（当选择本地 merge 或丢弃时，由 `/ky:finish-worktree` 自动执行）：

```bash
git worktree remove .claude/worktrees/wt-<name>
git branch -D feat/<name>          # 如已合并则删除
rm ~/.claude/projects/<repo-name>/active-worktree  # 同步清除状态文件
```

> 若 `active-worktree` 未及时清除，H3 `worktree-guard` 会指向一个不存在的目录，导致后续写操作被错误拦截。

## 并行开发规约

1. **默认粒度是 proposal**：一个 proposal 内的所有 task 在同一个 worktree 中完成
2. **proposal 内并行**：经冲突评估后，不同 agent 可在同一 worktree 内并行修改不同文件；同文件修改则串行
3. **多 proposal 并行**：每个 proposal 必须使用独立 worktree
4. **冲突检测**：worktree 间通过 git fetch + diff 检测潜在冲突
5. **最终合并**：每个 worktree 的修改通过独立 PR/MR 合并到 main
6. **定期清理**：废弃的 worktree 和已合并分支应在当天或当周清理，避免堆积

## 红旗信号

- 🚩 在 main 分支直接修改（H3 会拦截）
- 🚩 worktree 长期不清理，积累大量废弃分支
- 🚩 同 proposal 内无冲突却拆成多个 worktree，造成不必要的上下文切换

## Integration

- **前置 Command**: `/opsx:apply`（获取 task 信息）
- **创建/切换 Command**: `/ky:switch-worktree`
- **完成/清理 Command**: `/ky:finish-worktree`
- **后续 Command**: `/opsx:archive`（必须在 `/ky:finish-worktree` 合并代码后执行）
- **Hook**: H3 `worktree-guard`

### 与 OpenSpec workflow 的顺序

一个 proposal 的完整收尾推荐顺序：
1. `/ky:finish-worktree` — 代码合并到 `main`，清理本地 worktree
2. （可选）`/opsx:verify` — 验证实现符合规范
3. `/opsx:archive` — 归档 delta specs 到主规范

> 由于三者均为手工执行命令，此处的顺序约束为**引导性**而非强制性。实际项目中可通过 `/opsx:archive` 的前置检查点（如验证对应 feature branch 已不存在或已合并）来增加流程刚性。
````

---

### 3.2 Agents

#### 3.2.1 Agent: `developer`（C 语言开发工程师）

**文件路径**：`.claude/agents/developer.md`

**解决**：P3

**定位**：专注于 C 语言代码实现，只写不审，严格执行 TDD 铁律

**Agent 格式**：

````yaml
---
name: developer
description: C 语言开发工程师，专注代码实现，严格执行 TDD 铁律，只写不审
model: sonnet
tools: ["Read", "Write", "Edit", "Bash", "Grep", "Glob"]
---

# developer — C 语言开发工程师

## 身份

你是一名资深的 C 语言开发工程师，精通 Linux 系统编程和分布式存储系统开发。你的职责是高质量地实现代码，严格遵守 TDD 铁律：没有先失败的测试，决不写生产代码。

**核心能力**：
- C11 标准及 GCC/Clang 工具链
- Linux 系统调用、POSIX API、epoll/io_uring
- 数据结构（链表、跳表、B树、哈希表）的 C 语言实现
- 内存管理（内存池、 slab 分配器、arena）
- 并发编程（pthread、锁、条件变量、无锁结构）
- 分布式系统基础（Raft、Quorum、一致性哈希）

**行为准则**：
- 只写代码，不做评审（评审是 code-reviewer 的职责）
- 先写测试，再写实现
- 每个小步完成后运行测试
- 遇到测试失败先分析根因，不猜测
- 不确定时明确标注，要求澄清

## 工作模式

### 模式 1：TDD 实现

1. 读取当前 task 的目标和约束
2. 编写最小测试用例（RED）
3. 写最小实现使测试通过（GREEN）
4. 执行简化重构（REFACTOR）
5. proposal 收尾时运行 valgrind 确认内存安全（或在 `/ky:lint --full` 阶段覆盖）

### 模式 2：Task 收尾

单个或一组紧密相关的 task 完成后，执行代码清理和提交前检查。proposal 内的小 task 通常可合并收尾。

1. 确认所有相关测试通过
2. 执行 `clang-format` 格式化
3. 执行 `clang-tidy` 检查并修复问题
4. （可选）当本次变更量较大（>200 行）或涉及多个模块时，调用 `/ky:refactor --deep` 进行复用/质量/效率三维度深度清理
5. 清理本 proposal 的临时评审报告（如 `/tmp/devforge-code-review-*.md`）
6. 汇总变更，准备提交

### 模式 3：反馈闭环（生成器角色）

在反馈闭环（feedback-loop）中被 project-manager(A10) 调度为**生成器**：
- **闭环 A（L1）**：直接修正编译错误
- **闭环 A（L2）**：TDD 修复缺陷（NO FIX WITHOUT A FAILING TEST FIRST）
- **闭环 A（L2-Review）**：读取 `code-reviewer` 输出的评审报告，按 CRITICAL → HIGH 顺序修复问题，修复后回归测试
- **闭环 B（L3）**：重构 / 重设计

**行为约束**：只修复不发现、置信度守门、回归验证、原子 commit。详见 `feedback-loop.md`。

### 模式 4：质量收尾（Q.1–Q.4）

在 `/opsx:apply` 的所有实现 task 完成后，执行 proposal 级质量收尾：
- **Q.1**：全量 diff 代码评审收尾。若变更量较大（>200 行），调用 `/ky:refactor --deep` 进行复用/质量/效率三维度深度清理
- **Q.2**：全量编译 + clang-tidy 静态分析
- **Q.3**：全量单元测试（确保无回归）
- **Q.4**：覆盖率检查（通用模块单元测试行覆盖率 ≥85%，核心模块 ≥90%，新增代码 ≥95%；100% 作为努力方向，显著低于 95% 需在 Q.4 补充说明并增加测试）

### 模式 5：Proposal 完整收尾

代码实现及质量检查全部完成后：
1. 执行 `/ky:finish-worktree` 将代码合并到 `main`
2. 执行 `/opsx:verify`（如需要）
3. 执行 `/opsx:archive` 归档 delta specs

> developer 在引导用户时应确保 `/ky:finish-worktree` 完成后，再推进到 `/opsx:archive`。

## 关键规则

1. **NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST**
2. 每个函数返回值必须被检查或显式忽略（`(void)func()`）
3. 每次内存分配（含自定义分配器/封装函数）必须有对应的释放路径
4. 锁的获取必须有对应的释放
5. 不引入没有测试覆盖的新抽象
6. 不使用已被标记为 deprecated 的函数
7. 修复问题时不扩大范围，每次修复后必须通过回归测试

## 沟通风格

- 直接、具体、可操作
- 不确定时明确说"我不确定..."
- 测试失败时给出失败信息、分析假设、下一步行动

## 成功指标

- 测试先红后绿
- valgrind 报告 0 错误（proposal/PR 收尾阶段通过 `/ky:lint --full` 覆盖）
- clang-tidy 无严重警告
- 代码变更与 task 目标精确对齐（无镀金）
- 在 feedback-loop 中：修复回归测试通过，不引入新问题
````

---

#### 3.2.2 Agent: `code-reviewer`（代码评审工程师）

**文件路径**：`.claude/agents/code-reviewer.md`

**解决**：P3, P6

**定位**：只审不写，输出分级评审意见（CRITICAL/HIGH/MEDIUM/LOW）

**Agent 格式**：

````yaml
---
name: code-reviewer
description: 代码评审工程师，只审不写，输出结构化分级评审意见
model: sonnet
tools: ["Read", "Grep", "Bash", "Agent"]
---

# code-reviewer — 代码评审工程师

## 身份

你是一名严苛但公正的代码评审工程师，专精于 C 语言和分布式存储系统的代码质量。你的职责是发现代码中的问题、风险和不规范之处，**只审不写**。

**核心能力**：
- C 语言内存安全与并发正确性审计
- 代码复杂度与可维护性评估
- 分布式系统常见陷阱识别（竞态条件、错误处理遗漏、资源泄漏）
- 安全漏洞扫描（缓冲区溢出、格式化字符串、整数溢出）

## 评审模式

根据变更范围自动选择单 agent 轻量评审或多 agent 深度评审。

### 轻量评审（默认）

**触发条件**：变更 < 300 行，且涉及模块 ≤ 2 个。

由 `code-reviewer` 单 agent 依次完成 L1 + L2 + L3，输出结构化评审报告。

### 深度评审

**触发条件**：变更 ≥ 300 行，或涉及 3+ 模块，或 Q.4 全量 diff 收尾。

启动 3 个 `code-reviewer` subagent 并行，各负责一个层级：
- **Agent 1（通用质量）**：L1 通用检查
- **Agent 2（C 语言专项）**：L2 内存安全、并发正确性、错误处理完备性
- **Agent 3（安全审计）**：L3 硬编码密钥、注入风险、整数溢出

主 agent 等待全部返回后：
1. 合并三个子报告，按 CRITICAL / HIGH / MEDIUM / LOW 统一分级
2. 去重同一位置的问题
3. 输出汇总评审报告

## 评审流程

1. **范围确认**：获取本次评审的目标代码范围
   - 轻量评审（单个或少量 task）：取当前工作区的 staged/unstaged 变更，即 `git diff HEAD` + `git diff --cached`
   - 深度评审 / Q.4 收尾：取整个 proposal 相对于 `main` 的完整变更，即 `git diff $(git merge-base HEAD main)..HEAD`
2. **模式选择**：根据范围（行数、模块数）选择轻量评审或深度评审
3. **执行评审**：按 L1 → L2 → L3 深度检查
4. **分级输出**：CRITICAL / HIGH / MEDIUM / LOW
5. **总结建议**：给出修复优先级和总体通过/不通过结论

## 输出格式

```markdown
## 代码评审报告

### 变更概要
- 评审文件数：N
- 新增代码行：+X
- 删除代码行：-Y

### CRITICAL
- `[path:line]` 问题描述
  - 证据：...
  - 建议：...

### HIGH
...

### MEDIUM
...

### LOW
...

### 结论
- [ ] 通过（无 CRITICAL，HIGH 已处理或接受）
- [ ] 不通过（存在未处理的 CRITICAL 或 HIGH）
```

## 输出位置

- 评审报告临时输出至：`/tmp/code-review-report-<timestamp>.md`
- 供 `developer` 或 feedback-loop 读取并按优先级修复
- **生命周期**：修复验证通过后自动删除，不保留归档

## 沟通风格

- 不说"有趣"，说"这里有风险"
- 每个问题都附带改进方案
- 不确定时标注为假设，要求作者确认

## 成功指标

- 所有 CRITICAL 问题都被定位
- 每个意见都有明确的代码位置引用
````

---

### 3.3 Commands

#### 3.3.1 Command: `/ky:tdd`

**文件路径**：`.claude/commands/ky/tdd.md`

**映射 Skill**: `code/tdd-workflow`

**Command 格式**：

````markdown
# /ky:tdd

执行 TDD 开发循环（RED-GREEN-REFACTOR）。

## 何时使用

- 实现单个 OpenSpec task 的步骤
- 为现有代码补充测试
- 需要测试保驾护航的重构

## 执行流程

1. 激活 `developer` Agent
2. 读取当前 task 上下文（如由 `/opsx:apply` 触发）
3. 进入 `code/tdd-workflow` Skill：
   - RED：编写失败测试（对应 tasks.md N.M.1 ~ N.M.2）
   - GREEN：写最小实现使测试通过（对应 tasks.md N.M.3 ~ N.M.4）
   - REFACTOR：调用 `/ky:refactor` 简化代码（对应 tasks.md N.M.5）
5. 运行测试确认绿色（valgrind 留到 proposal 收尾或 `/ky:lint --full` 阶段）

## 参数

```
/ky:tdd [step-description]
```

- `step-description`（可选）：本次要实现的步骤简述

## 使用示例

```
/ky:tdd 实现 WAL 写入接口的追加逻辑
> RED：编写 test_wal_append.c，断言写入后 offset 增加
> 测试失败：assertion failed: offset == 0
>
> GREEN：实现 wal_append，返回更新的 offset
> 测试通过 ✅
>
> REFACTOR：提取边界检查到 wal_validate_record
> 测试保持绿色 ✅
```

## 关联

- Skill: `code/tdd-workflow`
- Agent: `developer`
- Rules: `coding-style`, `testing`
````

---

#### 3.3.2 Command: `/ky:code-review`

**文件路径**：`.claude/commands/ky/code-review.md`

**映射 Skill**: `code/code-review`

**Command 格式**：

````markdown
# /ky:code-review

执行三级代码评审管线。

## 何时使用

- task 完成后提交前
- 特性级 `/opsx:verify` 之前
- 任何需要外部视角检查代码质量的时刻

## 执行流程

1. 激活 `code-reviewer` Agent
2. **范围确认**：
   - 日常轻量评审：获取当前工作区 `git diff HEAD` + `git diff --cached` 的变更
   - Q.4 全量收尾：获取 `git diff $(git merge-base HEAD main)..HEAD` 的完整 proposal 变更
3. **模式选择**：基于范围行数和模块数自动选择
   - 轻量评审（< 300 行且模块 ≤ 2）：`code-reviewer` 单 agent 完成 L1+L2+L3
   - 深度评审（≥ 300 行，或 3+ 模块，或 Q.4 收尾）：启动 3 个 `code-reviewer` subagent 并行（通用质量 / C 专项 / 安全审计），主 agent 汇总去重
4. 输出结构化评审报告，写入 `/tmp/code-review-report-<timestamp>.md`
5. `developer` 或 feedback-loop 读取报告并按 CRITICAL → HIGH 顺序修复
6. 修复验证通过后，自动删除该临时报告

## 与 `/opsx:apply` 的衔接

- **N.M.6 REVIEW**：单个 task 完成后执行 `/ky:code-review`
- **Q.4 代码评审收尾**：所有实现 task 完成后，由 `code-reviewer`(A3) 执行全量 diff 评审

## 参数

```
/ky:code-review [file-pattern]
```

- `file-pattern`（可选）：只评审匹配的文件，如 `src/storage/*.c`

## 使用示例

```
/ky:code-review
> 评审 3 个文件，+120 -45
> 发现 1 个 HIGH：wal.c:89 缺少错误返回值检查
> 发现 2 个 MEDIUM：`storage_engine.c:2100` 函数长度 980 行且包含两类资源操作，建议拆分为 `wal_init()` 和 `index_init()`
> 结论：不通过（存在未处理 HIGH）
```

## 关联

- Skill: `code/code-review`
- Agent: `code-reviewer`
- Rules: `coding-style`, `testing`
````

---

#### 3.3.3 Command: `/ky:refactor`

**文件路径**：`.claude/commands/ky/refactor.md`

**映射 Skill**: `code/code-refactor`

**Command 格式**：

````markdown
# /ky:refactor

执行测试护航下的代码简化重构。支持轻量重构（默认）和深度清理（`--deep`）两种模式。

## 何时使用

- TDD 循环的 REFACTOR 阶段
- 代码评审后的修改清理
- 特性级 archive 前的最终整理

## 执行流程

1. 激活 `developer` Agent
2. **模式选择**：
   - **轻量模式**（默认）：变更量 ≤200 行，或未指定 `--deep`
   - **深度模式**：变更量 >200 行，或用户指定 `--deep`，或处于 Q.1 全量收尾阶段。此时自动进入 `code/simplify` Skill，启动三 agent 并行评审（复用 / 质量 / 效率），由 `developer` 汇总去重并修复问题
3. 运行全部测试并确认绿色
4. 进入对应 Skill 执行重构/清理：
   - 轻量模式：`code/code-refactor`，每次处理一种最明显异味，循环 until 无明显异味
   - 深度模式：`code/simplify`，Phase 1 识别变更 → Phase 2 三 agent 并行评审 → Phase 3 `developer` 汇总修复
5. 再次运行测试确认绿色（深度模式完成后可接 `/ky:lint --full` 跑 valgrind）
6. 输出重构摘要

## 参数

```
/ky:refactor [--deep] [focus]
```

- `--deep`：强制进入深度模式，调用 `code/simplify` Skill 进行复用/质量/效率三维度清理
- `focus`（可选，轻量模式适用）：`dup`（消除重复）/`length`（缩短函数）/`name`（澄清命名）/`complexity`（降低复杂度）

## 使用示例

```
/ky:refactor
> 轻量模式
> 测试绿色 ✅
> 发现 wal.c 有两处重复的错误处理逻辑
> 提取为 wal_handle_io_error()
> 测试保持绿色 ✅
```

```
/ky:refactor --deep
> 深度模式（变更量 +380 -120，涉及 5 个文件）
> 启动三 agent 并行评审...
> 复用 agent：发现 1 处可复用现有 `utils/buffer.c:buf_append()`
> 质量 agent：发现 2 处参数膨胀和 1 处无意义注释
> 效率 agent：发现热路径上新增 `malloc`，建议改为 slab 分配
> 已修复 4/5 个问题，1 个问题标记为后续 TODO
> 全量测试通过，valgrind 0 错误 ✅
```

## 关联

- Skill: `code/code-refactor`（轻量模式）, `code/simplify`（深度模式）
- Agent: `developer`（调度）+ `code-reviewer`（深度模式 subagent）
- Rules: `coding-style`
````

---

#### 3.3.4 Command: `/ky:lint`

**文件路径**：`.claude/commands/ky/lint.md`

**映射 Skill**: `code/lint-check`

**Command 格式**：

````markdown
# /ky:lint

执行编译检查和静态分析。默认 fast 模式只跑编译 + clang-tidy；`--full` 模式额外跑 valgrind 全量内存检测。

## 何时使用

- 修改 C 代码后快速验证（fast 模式）
- 提交前最终检查（fast 模式）
- `/ky:tdd` 后的补充验证（fast 模式）
- 特性级 archive 前或 Q.1 质量收尾（`--full` 模式）

## 执行流程

1. 激活 `developer` Agent
2. 进入 `code/lint-check` Skill：
   - L1：编译（优先使用项目构建脚本 `make`/`cmake --build build` 等）
   - L2：clang-tidy
   - L3：valgrind（仅在 `--full` 模式下执行，需测试二进制已存在）
3. 汇总检查结果
4. 如发现问题，提供修复建议

## 参数

```
/ky:lint [--full] [target]
```

- `--full`：同时执行 valgrind 内存检测
- `target`（可选）：指定要检查的目标文件或构建产物

## 使用示例

```
/ky:lint
> 编译 ✅ 0 error, 0 warning
> clang-tidy ⚠️ 2 个 readability Warning
```

```
/ky:lint --full
> 编译 ✅ 0 error, 0 warning
> clang-tidy ⚠️ 2 个 readability Warning
> valgrind ✅ 0 errors
```

## 关联

- Skill: `code/lint-check`
- Agent: `developer`
- Rules: `coding-style`
- Hooks: `pre-commit-lint`
````

---

#### 3.3.5 Command: `/ky:switch-worktree`

**文件路径**：`.claude/commands/ky/switch-worktree.md`

**映射 Skill**: `code/git-worktree`

**Command 格式**：

````markdown
# /ky:switch-worktree

切换或创建 Git worktree，实现隔离并行开发。

## 何时使用

- 启动新 proposal 的开发
- 在不同 proposal 的 worktree 之间切换
- 创建干净的评审环境

## 执行流程

1. 激活 `developer` Agent
2. 检测现有 worktree 列表：`git worktree list`
3. 如果用户指定了存在的 worktree → 直接切换
4. 如果不存在 → 询问是否创建，并自动按 proposal 命名
5. 进入 `code/git-worktree` Skill 完成切换

## 参数

```
/ky:switch-worktree [proposal-name]
```

- `proposal-name`（可选）：目标 proposal 名称，对应 worktree 为 `wt-<proposal-name>`

## 使用示例

```
/ky:switch-worktree storage-wal
> 已切换到 .claude/worktrees/wt-storage-wal
> 当前分支：feat/storage-wal
```

## 关联

- Skill: `code/git-worktree`
- Agent: `developer`
- Hooks: `worktree-guard`
````

---

#### 3.3.6 Command: `/ky:finish-worktree`

**文件路径**：`.claude/commands/ky/finish-worktree.md`

**映射 Skill**: `code/git-worktree`

**Command 格式**：

````markdown
# /ky:finish-worktree

完成当前 worktree 的开发工作：验证测试 → 呈现合并选项 → 执行选择 → 清理。

## 何时使用

- proposal 开发完成，需要合并回 main
- 需要创建 PR 并清理关联 worktree
- 需要丢弃废弃的 worktree

## 执行流程

1. 激活 `developer` Agent
2. **前置状态检测**：检查当前分支是否已合并到 base branch（如 `main`）
   - **若已合并**：直接提示"分支已合并，是否清理关联 worktree？"
     - 确认后自动执行 `git worktree remove` + 删除分支 + 清除 `~/.claude/projects/<repo-name>/active-worktree`
     - 跳过后续选项展示
   - **若未合并**：继续下一步
3. **验证测试**：运行 `./run-tests.sh ut`（或项目定义的测试命令），确认通过；失败则停止
4. **确定 base branch**：通常为 `main`
5. **呈现选项**：
   - **选项 1**：本地合并回 `main`，成功后清理 worktree
   - **选项 2**：推送分支并创建 Pull Request，**保留** worktree（PR 未合并前可能需要修改）
   - **选项 3**：保持当前状态，以后再处理
   - **选项 4**：丢弃当前分支和 worktree（需 typed 确认）
6. **执行选择**：执行对应 git 操作
7. **清理 worktree**（选项 1、4）：执行 `git worktree remove` 并删除 `~/.claude/projects/<repo-name>/active-worktree`
   - **选项 2 的后续**：PR 合并后再次执行 `/ky:finish-worktree`，将通过前置状态检测自动进入快速清理流程
8. **后序引导**：清理完成后提示用户继续执行 `/opsx:verify`（如需）→ `/opsx:archive`

## 参数

```
/ky:finish-worktree    # 处理当前所在 worktree
```

## 使用示例

```
/ky:finish-worktree
> 测试通过 ✅
> 选择：2. 推送并创建 PR
> PR 已创建：#42
> worktree 保留在 .claude/worktrees/wt-storage-wal
```

## 关联

- Skill: `code/git-worktree`
- Agent: `developer`
- Hooks: `worktree-guard`
````

---

### 3.4 Rules

#### 3.4.1 Rule: R2 `git-workflow`（Git 工作流规范）

**文件路径**：`.claude/rules/git-workflow.md`

**解决**：P3

**Rule 内容要点**：

````markdown
# R2 git-workflow — Git 工作流规范

## 适用范围

所有代码提交。

## Conventional Commits

提交信息格式：

```
<type>(<scope>): <subject>

<body>

Refs: <proposal-name>/<task-id>
```

**type**：
- `feat`: 新功能
- `fix`: Bug 修复
- `docs`: 文档变更
- `style`: 不影响代码含义的格式修改
- `refactor`: 既不修复 bug 也不添加功能的代码变更
- `test`: 测试相关
- `chore`: 构建过程或辅助工具的变动

**scope**：子系统名，如 `storage`、`metadata`、`network`

**Refs**：关联的 OpenSpec proposal 或 task（如 `Refs: storage-wal-impl/step-2`）

## 分支策略

- **main**：只接受合并，不接受直接推送
- **feat/<proposal>**：特性开发分支
- **fix/<issue>**：热修复分支
- **wt-<proposal>**：worktree 专用分支

## worktree 规范

- **默认粒度是 proposal**：一个 proposal 使用一个 worktree
- worktree 目录统一放在 `.claude/worktrees/`
- 单个 proposal 内无冲突的多 agent 并行可在同一 worktree 内完成
- 多个 proposal 并行开发时，每个 proposal 一个独立 worktree
- 废弃 worktree 及时清理
````

---

#### 3.4.2 Rule: R3 `coding-style`（C 语言编码规范）

**文件路径**：`.claude/rules/coding-style.md`

**适用范围**：`**/*.c`, `**/*.h`

**解决**：P3

**Rule 内容要点**：

完整规则见 `.claude/rules/coding-style.md`，核心板块包括：

- **格式**：`clang-format`（LLVM 风格，4 空格缩进，100 字符行宽，K&R 花括号）
- **命名**：函数/结构体/变量/macros 的命名规范、全局/静态变量前缀约定
- **头文件组织**：`.h`/`.c` 职责边界、include guard、包含顺序、内部头文件约定
- **宏的使用纪律**：`static inline` 优于宏、宏参数保护、`do { } while(0)`、禁止宏指针 typedef
- **类型系统**：固定宽度整数、`const` 正确性、布尔值、`typedef` 使用边界
- **内存管理**：分配/释放配对、`free` 后置 NULL、分配失败处理、禁止 `alloca`/VLA
- **错误处理**：返回值检查铁律、`goto cleanup` 规范、错误传播与日志
- **并发**：锁的配对原则、全局锁序、RAII 封装、无锁结构的使用边界
- **安全**：边界字符串操作、格式化字符串安全、整数溢出检查
- **热路径与性能**：热路径禁止 `malloc`/锁/日志、`likely`/`unlikely`、缓存行对齐
- **断言与不变量**：`assert` 只用于内部不变量，不处理外部错误
- **注释**：接口契约、复杂算法 WHY 注释、禁止过期/无意义注释
- **可移植性**：编译器属性封装宏、显式字节序转换
- **提交前检查清单**：内存、锁、`goto`、热路径等自查项

> **与 `clang-format` 的关系**：`clang-format` 只处理纯语法格式（由 H2 hook 自动执行），`coding-style.md` 约束 `clang-format` 无法检查的语义与设计规则。

---

#### 3.4.3 Rule: R4 `testing`（测试分层规范）

**文件路径**：`.claude/rules/testing.md`

**适用范围**：`**/*.c`, `**/*.h`

**解决**：P3, P4

**Rule 内容要点**：

````markdown
# R4 testing — 测试分层与 TDD 规范

## 测试分层

| 层级 | 范围 | Runner | 归属 |
|------|------|--------|------|
| 单元测试 | 单函数/模块（进程内、无外部依赖） | `./run-tests.sh ut` | 特性 proposal |
| 集成测试 | 多节点/组件交互、接口契约、故障注入 | `./run-tests.sh it` | 独立 proposal |
| 性能测试 | 基准/压力/回归 | `./run-tests.sh perf` | 独立 proposal |

## TDD 铁律

1. **RED**：先写一个失败的测试
2. **GREEN**：写最小实现使测试通过
3. **REFACTOR**：在绿色下简化代码

## 单元测试要求

- 每个公开的 API 函数至少有一个直接测试
- 每个错误路径至少有一个测试
- proposal/PR 级别通过 `/ky:lint --full` 或项目 CI 集成 valgrind
- 新增代码必须被测试覆盖

## 测试文件组织

```
tests/
├── unit/
│   └── test_<module>_<scenario>.c
├── integration/
│   └── test_<subsystem>_<scenario>.c
└── perf/
    └── bench_<module>.c
```

## 断言风格

使用 `cmocka` 时：

```c
assert_int_equal(expected, actual);
assert_ptr_not_null(ptr);
assert_string_equal("ok", result);
```

## 覆盖率

- **单元测试行覆盖率**：
  - 通用模块 ≥ **85%**
  - 核心模块（metadata / storage / network / 一致性协议）≥ **90%**
- **新增代码**：行覆盖率 ≥ **95%**，100% 作为努力方向（显著低于 95% 需在 Q.4 说明并补充测试）
- **集成测试**：覆盖所有关键路径、子系统交互接口、端到端场景、故障恢复场景
- **性能测试**：建立基准线，回归检测 ≤5% 波动

## Mock 纪律（与 spec-driven-enhanced tasks 模板一致）

### 单元测试
- 可以 mock **子系统外部边界**（外部 RPC、外部服务依赖、外部存储介质模拟）
- **禁止 mock 子系统内部模块**（同子系统内的 `.c`/`.h` 模块），测试必须走真实的内部调用链
- 每个 mock 必须注释说明：mock 了什么、为什么必须 mock、mock 行为与真实行为的差异
- 🚩 如果发现需要 mock 内部模块才能写测试，说明模块耦合过紧，应先重构解耦

### 集成测试
- **原则上禁止 mock**，必须走真实调用链
- 仅在极少数无法真实集成的外部边界（如第三方付费 API、特定硬件）才可例外 mock，且需经 code-reviewer 确认
- mock 必须注释说明其与真实行为的差异及不可真实集成的原因

## 集成测试编写规则

### 环境搭建/拆除要求

- 每个集成测试套件必须有独立的 `setup()`/`teardown()`，确保测试间无状态泄漏
- 文件系统测试使用临时目录（`mkdtemp`），teardown 时清理
- 网络测试使用随机端口绑定，避免端口冲突
- 多进程测试使用 `waitpid` 确保子进程正确回收，避免僵尸进程
- 数据库/存储引擎测试使用独立数据目录，teardown 时完整清除

### 故障注入验证标准

- **磁盘故障**：使用 `fallocate` + 只读挂载 / `LD_PRELOAD` 注入 IO 错误，验证错误处理路径
- **网络故障**：使用 `iptables`/`tc` 模拟丢包/延迟/分区，验证超时和重试逻辑
- **进程故障**：使用 `kill -9` 模拟崩溃，验证重启后数据完整性和状态恢复
- **并发故障**：使用 `helgrind`/`TSan` 检测竞态，使用延迟注入放大时间窗口

### 多节点测试编排规则

- 使用进程模拟多节点（单机多进程），Docker 按需用于需要网络隔离的场景
- 节点启动顺序和时机必须可控（支持延迟启动、乱序启动）
- 每个多节点测试必须验证至少一种故障场景（节点宕机/网络分区/脑裂）
- 一致性验证：写入后读取验证、多副本数据比对、故障恢复后数据完整性校验

### 集成测试反模式（Red Flags）

- 🚩 mock 了子系统内部模块（应走真实调用链）
- 🚩 测试通过但未验证数据正确性（只检查返回码不检查数据内容）
- 🚩 无故障场景（只测试 happy path）
- 🚩 测试间有隐式状态依赖（执行顺序影响结果）
- 🚩 硬编码端口/路径（导致并行运行冲突）
````

---

### 3.5 Hooks

所有 Hooks 统一配置于 **`.claude/hooks.json`**。

#### 3.5.1 Hook: H1 `pre-commit-lint`

**触发时机**：`PreToolUse(Bash)` — 检测到 `git commit` 命令时

**行为**：
1. 获取 staged 的 `.c` 和 `.h` 文件列表
2. 对这些文件执行 `clang-tidy`（增量检查）
3. 若发现 `bugprone-*`、`cert-*`、`clang-analyzer-*` 等级的错误，拦截提交并输出问题列表
4. 无严重问题时放行

**Hook 配置片段**：

```json
{
  "pre-commit-lint": {
    "type": "PreToolUse",
    "matcher": {
      "tool": "Bash",
      "pattern": "git commit"
    },
    "command": "bash .claude/hooks/pre-commit-lint.sh"
  }
}
```

**脚本逻辑**（`.claude/hooks/pre-commit-lint.sh` 中）：

```bash
STAGED=$(git diff --cached --name-only --diff-filter=ACM | grep -E '\.(c|h)$')
[ -z "$STAGED" ] && exit 0

clang-tidy $STAGED -- -I./include \
  -checks="bugprone-*,cert-*,clang-analyzer-*" 2>&1 | tee /tmp/clang-tidy.log

if grep -q "error:" /tmp/clang-tidy.log; then
    echo "❌ clang-tidy 发现错误，提交被拦截"
    exit 1
fi
```

---

#### 3.5.2 Hook: H2 `post-edit-format`

**触发时机**：`PostToolUse(Edit)` — 使用 Edit 修改 `.c` 或 `.h` 文件后

**行为**：
1. 对被编辑的文件自动执行 `clang-format -i`
2. 如格式化产生了修改， silently apply（不打扰用户）

**Hook 配置片段**：

```json
{
  "post-edit-format": {
    "type": "PostToolUse",
    "matcher": {
      "tool": "Edit",
      "filePattern": "**/*.{c,h}"
    },
    "command": "bash .claude/hooks/post-edit-format.sh"
  }
}
```

**脚本逻辑**：

```bash
FILE="$CLAUDE_EDITED_FILE"
[ -f "$FILE" ] && clang-format -i "$FILE"
```

---

#### 3.5.3 Hook: H3 `worktree-guard`

**触发时机**：`PreToolUse(Edit|Write)` — 对仓库内文件执行写操作前

**行为**：
1. 读取 `~/.claude/projects/<repo-name>/active-worktree` 状态文件（如存在）
2. 若存在活跃 worktree，仅放行**活跃 worktree 目录内**和**项目外**的写操作
3. 若写操作目标不在活跃 worktree 内，拦截并根据当前位置给出差异化提示：
   - 当前在仓库根目录（非任何 worktree）：提示"⚠️ 当前不在活跃 worktree 内，建议执行 `/ky:switch-worktree <name>` 恢复上下文"
   - 当前在另一个 worktree：提示"🚫 当前在另一个 worktree，建议执行 `/ky:switch-worktree <name>` 切换"
4. 无活跃 worktree 时（如在 main 分支且未创建 worktree），直接放行

> `/ky:switch-worktree` 执行时自动更新 `~/.claude/projects/<repo-name>/active-worktree`，guard 随之切换守护范围。防止会话中断或上下文丢失后误写主干或其他非活跃 worktree。

**Hook 配置片段**：

```json
{
  "worktree-guard": {
    "type": "PreToolUse",
    "matcher": {
      "tool": "Edit|Write",
      "filePattern": "**/*"
    },
    "command": "bash .claude/hooks/worktree-guard.sh"
  }
}
```

**脚本逻辑**：

```bash
ACTIVE_WORKTREE_FILE="$HOME/.claude/projects/$(basename "$PWD")/active-worktree"
[ ! -f "$ACTIVE_WORKTREE_FILE" ] && exit 0

ACTIVE_WORKTREE=$(cat "$ACTIVE_WORKTREE_FILE" | tr -d '[:space:]')
[ -z "$ACTIVE_WORKTREE" ] && exit 0

# 获取当前工作目录
CWD=$(pwd)
# 计算活跃 worktree 的绝对路径
ACTIVE_PATH=$(cd "$ACTIVE_WORKTREE" 2>/dev/null && pwd || echo "")

# 检查当前是否在活跃 worktree 目录内
if [ -n "$ACTIVE_PATH" ] && [[ "$CWD" == "$ACTIVE_PATH"* ]]; then
    exit 0
fi

# 检查是否身处另一个 worktree
CURRENT_WORKTREE=$(git rev-parse --show-toplevel 2>/dev/null || echo "")

if [ -z "$CURRENT_WORKTREE" ] || [ "$CURRENT_WORKTREE" = "$(git -C "$ACTIVE_WORKTREE" rev-parse --show-toplevel 2>/dev/null)" ]; then
    # 在仓库根目录或其他非 worktree 路径
    echo "⚠️  worktree 守护：当前不在活跃 worktree 内"
    echo "   当前目录：$CWD"
    echo "   活跃 worktree：$ACTIVE_WORKTREE"
    echo "   建议执行 /ky:switch-worktree $(basename "$ACTIVE_WORKTREE" | sed 's/^wt-//') 恢复上下文"
else
    # 在另一个 worktree 中
    echo "🚫 worktree 守护：当前在另一个 worktree（$CURRENT_WORKTREE），但活跃 worktree 是 $ACTIVE_WORKTREE"
    echo "   建议："
    echo "     1. 执行 /ky:switch-worktree $(basename "$ACTIVE_WORKTREE" | sed 's/^wt-//') 切换"
    echo "     2. 若已废弃该 worktree，执行 /ky:finish-worktree 完成清理"
fi
exit 1
```

---

### 3.6 `.claude/hooks.json` 完整配置

```json
{
  "hooks": [
    {
      "name": "pre-commit-lint",
      "type": "PreToolUse",
      "matcher": {
        "tool": "Bash",
        "pattern": "git commit"
      },
      "command": "bash .claude/hooks/pre-commit-lint.sh"
    },
    {
      "name": "post-edit-format",
      "type": "PostToolUse",
      "matcher": {
        "tool": "Edit",
        "fileGlob": "**/*.{c,h}"
      },
      "command": "bash .claude/hooks/post-edit-format.sh"
    },
    {
      "name": "worktree-guard",
      "type": "PreToolUse",
      "matcher": {
        "tool": "Edit|Write",
        "fileGlob": "**/*"
      },
      "command": "bash .claude/hooks/worktree-guard.sh"
    }
  ]
}
```

> 注：Claude Code 的 Hook 配置格式以实际版本为准，上述为基于 everything-claude-code 参考的风格化配置。如当前版本已支持 `settings.json` hook 配置，请优先使用官方格式。

---

## 验证计划

1. **TDD 验证**：
   - 在示例 C 项目中执行 `/ky:tdd`
   - 验证 RED → GREEN → REFACTOR 三阶段完整运行
   - 验证 "NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST" 被强制执行
   - 验证 TDD 循环内不阻塞跑 valgrind，proposal 收尾时通过 `/ky:lint --full` 覆盖 valgrind

2. **代码评审验证**：
   - 执行 `/ky:code-review` 对一组已知有问题的代码
   - 验证三级评审管线能发现内存泄漏、错误处理遗漏、安全漏洞
   - 验证输出格式为 CRITICAL/HIGH/MEDIUM/LOW 分级

3. **重构验证**：
   - 执行 `/ky:refactor`
   - 验证重构前后测试保持绿色
   - 验证代码质量指标改善（重复减少、函数缩短）

4. **Simplify 验证**：
   - 在一组 >200 行的变更后执行 `/ky:refactor --deep`
   - 验证 3 个 subagent（复用/质量/效率）并行启动并返回结构化问题
   - 验证 `developer` 汇总修复后测试保持绿色

5. **Lint 验证**：
   - 执行 `/ky:lint`（fast 模式）：验证编译通过、clang-tidy 无严重警告
   - 执行 `/ky:lint --full`：额外验证 valgrind 无内存错误

6. **Worktree 验证**：
   - 执行 `/ky:switch-worktree test-proposal`
   - 验证 worktree 创建和分支切换正确
   - 执行 `/ky:finish-worktree`，验证四种选项（本地 merge / 创建 PR / 保持 / 丢弃）能正确执行并清理 worktree

7. **Hook 验证**：
   - 使用 `/ky:switch-worktree test-proposal` 创建 worktree，验证 `~/.claude/projects/<repo-name>/active-worktree` 被更新
   - 退出 worktree 后尝试 Edit `.c` 文件，验证 H3 `worktree-guard` 基于 `active-worktree` 拦截
   - 使用 Edit 修改 `.c` 文件后，验证 H2 `post-edit-format` 自动格式化
   - 在 feature 分支 `git commit`，验证 H1 `pre-commit-lint` 增量扫描 staged 文件

8. **任务步骤映射验证**：
   - 验证 `/ky:tdd` 的执行输出与 tasks.md 的 N.M.1 ~ N.M.4 对应
   - 验证 `/ky:refactor` 的输出与 tasks.md 的 N.M.5 对应
   - 验证 `/ky:code-review` 的输出与 tasks.md 的 N.M.6 / Q.4 对应

---

## 与 Phase 2 的关系

Phase 3 的所有代码级能力在 R1 `workflow` 的约束下运行：
- `/ky:tdd` 实现的是特性级 tasks.md 中定义的 task 步骤
- `/ky:code-review` 在代码实现完成后执行，是进入测试验证级前的质量门
- worktree 隔离是四层工作流中"代码级 → 测试验证级"的并行基础

## 与 Phase 4 的关系

Phase 4 将建立：
- `code/spec-review`：对 OpenSpec 交付件（proposal/spec/design）的评审
- `code/parallel-develop`：多 Agent 并行协调（需要 Phase 3 的 worktree 隔离作为基础设施）
- `code/systematic-debug`：系统化调试

因此 Phase 3 是 Phase 4 的基础设施，必须先完成并验证通过。
