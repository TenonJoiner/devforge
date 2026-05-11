# /df:code-review

执行五维度代码评审——Correctness / Readability / Architecture / Security / Performance。

## 何时使用

- **被 `/opsx:apply` 调用**：
  - 一个 task group 完成后（N.M.6 REVIEW，task group 级轻量评审）
  - 全部实现 task 完成后、`/opsx:verify` 之前（Q.4 全量收尾评审）
- **独立使用**：日常开发中任何需要外部视角检查代码质量的时刻

## 执行流程

1. 激活 `code-reviewer` Agent
2. **范围确认**：
   - 日常轻量评审：获取当前工作区 `git diff HEAD` + `git diff --cached` 的变更
   - task group 完成后：获取当前 task group 对应的 `git diff`（自上次 N.M.6 或分支起点以来的变更）
   - Q.4 全量收尾：获取 `git diff $(git merge-base HEAD main)..HEAD` 的完整 proposal 变更
3. **评审**：基于触发场景和变更规模选择评审深度
   - **N.M.6 task group 完成后**：固定轻量评审
   - **Q.4 全量收尾**：固定深度评审
   - **日常独立使用**：按规模自动选择
     - 轻量评审（< 300 行且模块 ≤ 2）：`code-reviewer` 单 agent，覆盖 D1 Correctness + D2 Readability，单轮
     - 深度评审（≥ 300 行，或 3+ 模块）：5 个 subagent 并行（D1-D5 各一个），汇总去重
4. 输出结构化评审报告，按 CRITICAL → HIGH → MEDIUM 分级
5. **修复**：`developer` 按报告逐项修复（CRITICAL → HIGH → MEDIUM）
6. **验证轮**（仅深度评审）：修复完成后再执行一轮评审。若有新增 CRITICAL/HIGH，继续修复并再次评审，直到无新增 CRITICAL/HIGH 时收敛

## 结束条件

- 轻量评审：单轮评审 + 修复后结束
- 深度评审：新一轮评审无新增 CRITICAL/HIGH 时结束
- MEDIUM 由 developer 判断是否修复，未修复的标注为"已接受风险"
- INFO 发现不阻塞，记录后结束

## 与 `/opsx:apply` 的衔接

- **N.M.6 REVIEW**：一个 task group 完成后执行 `/df:code-review`
- **Q.4 代码评审收尾**：所有实现 task 完成后，由 `code-reviewer` 执行全量 diff 评审

## 参数

```
/df:code-review [file-pattern]
```

- `file-pattern`（可选）：只评审匹配的文件，如 `src/storage/*.c`

## 使用示例

```
/df:code-review
> 评审 3 个文件，+120 -45
>
> [Round 1] CRITICAL: 0 | HIGH: 1 | MEDIUM: 2 | INFO: 1
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
> INFO #3: handler.c:156 — Finding #1 变体，read_record() 返回值未检查
>
> 修复 #1 (HIGH): 已添加返回值检查
> 修复 #2 (MEDIUM): 已拆分
> #3 (INFO): 记录，不阻塞
>
> [Round 2] 无新增 CRITICAL/HIGH，结束
```

## 关联

- Skill: `devforge-code-review`
- Agent: `code-reviewer`
- Rules: `coding-style`, `testing`
- Hooks: `post-edit-format`（风格问题在编辑时自动处理，不进入评审管线）
