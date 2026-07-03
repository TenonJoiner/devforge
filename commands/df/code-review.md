# /df:code-review

执行五维度代码评审——Correctness / Readability / Architecture / Security / Performance。

## 何时使用

- **独立使用**：日常开发中任何需要外部视角检查代码质量的时刻
  - `/df:code-review` — 只评审不修复
  - `/df:code-review autofix` — 评审并自动修复
- **批量变更后**：一批 task 完成后做全量收尾评审

## 执行流程

1. 激活 `code-reviewer` Agent
2. **范围确认**：
   - 日常轻量评审：获取当前工作区 `git diff HEAD` + `git diff --cached` 的变更
   - 批量收尾：检测 trunk 分支后计算 `git diff $(git merge-base HEAD <trunk>)..HEAD`
3. **评审**：基于变更规模选择评审深度
   - **轻量评审（< 300 行且模块 ≤ 2）**：`code-reviewer` 单 agent，覆盖 D1 Correctness + D2 Readability，单轮
   - **深度评审（≥ 300 行，或 3+ 模块）**：5 个 subagent 并行（D1-D5 各一个），汇总去重
4. 输出结构化评审报告，按 CRITICAL → HIGH → MEDIUM 分级

**`autofix` 未设置（默认）**：输出评审报告后结束，不执行修复。

**`autofix` 已设置**：继续以下步骤——
5. **修复**：`developer` 按报告逐项修复（CRITICAL → HIGH → MEDIUM）
6. **验证轮**（仅深度评审）：修复完成后再执行一轮评审。若有新增 CRITICAL/HIGH，继续修复并再次评审，直到无新增 CRITICAL/HIGH 时收敛

## 结束条件

**`autofix` 未设置（默认）**：输出评审报告和最终结论后结束。

**`autofix` 已设置**——
- 轻量评审：单轮评审 + 修复后结束
- 深度评审：新一轮评审无新增 CRITICAL/HIGH 时结束
- MEDIUM 由 developer 判断是否修复，未修复的标注为"已接受风险"
- LOW 发现不阻塞，记录后结束

## 参数

```
/df:code-review [autofix] [--full] [--diff-range <value>] [file-pattern]
```

- `autofix`（可选）：评审后自动修复代码。不带此参数时只评审不修复
- `--full`（可选）：分支全量评审，范围为完整 proposal 变更，自动检测 trunk 分支。不传时默认评审工作区未提交变更（`git diff HEAD` + `git diff --cached`）
- `--diff-range`（可选）：显式指定 git diff 范围，如 `"git diff origin/main...HEAD"`。优先级高于 `--full`，由外部调用方（如 pr-review）传入
- `file-pattern`（可选）：只评审匹配的文件，如 `src/storage/*.c`

## 使用示例

**全量评审（QA 收尾）**：

```
/df:code-review autofix --full
> 评审范围：完整 proposal 变更，12 个文件，+450 -120
> 启动深度评审（5 维度并行）...
```

**只评审不修复（默认）**：

```
/df:code-review
> 评审 3 个文件，+120 -45
>
> [Round 1] CRITICAL: 0 | HIGH: 1 | MEDIUM: 2 | LOW: 1
>
> HIGH #1: handler.c:89 — write_record() 返回值未检查
>   Category: Correctness
>   Impact: 写入失败时调用者无法感知
>   Recommendation: if (write_record(r, buf, len) < 0) { return ERR_IO; }
>
> MEDIUM #2: engine.c:2100 — 函数 980 行，职责分散
>   Category: Readability
>   Recommendation: 拆分为 log_init() + index_init()
>
> LOW #3: handler.c:156 — Finding #1 变体，read_record() 返回值未检查
>
> 最终结论: NEEDS_FIX — 1 个 HIGH 未处理
```

**评审并自动修复**：

```
/df:code-review autofix
> 评审 3 个文件，+120 -45
>
> [Round 1] CRITICAL: 0 | HIGH: 1 | MEDIUM: 2 | LOW: 1
>
> HIGH #1: handler.c:89 — write_record() 返回值未检查
>   ...
>
> 修复 #1 (HIGH): 已添加返回值检查
> 修复 #2 (MEDIUM): 已拆分
> #3 (LOW): 记录，不阻塞
>
> [Round 2] 无新增 CRITICAL/HIGH，结束
```

## 关联

- Skill: `devforge-code-review`
- Agent: `code-reviewer`
- Rules: `coding-style`, `testing`
- Hooks: `post-edit-format`（风格问题在编辑时自动处理，不进入评审管线）
