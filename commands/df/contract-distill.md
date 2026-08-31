# /df:contract-distill

代码调整告一段落时，回顾生成代码被调整之处，把「预期 vs 生成之差」翻译成模块级契约，沉淀/更新 `docs/contracts/<module>.md`。

## 何时使用

- 用 /opsx:apply 生成代码后，实现经过代码调整才符合预期
- 想在代码调整告一段落时，把代码调整中暴露的隐式契约显性化，避免下次生成再犯同样的错

## 参数

```
/df:contract-distill [--base <git-ref>]
```

- `--base`（可选）：本次代码调整范围的 git 基点。默认自动取当前分支与上游的分叉点（`git merge-base HEAD @{upstream}`）

## 使用示例

```
/df:contract-distill
> [识别] 发现 3 处代码调整，2 处疑似缺契约
> [反推] storage 模块 2 条契约；另 1 处为分流项（rules 缺失）
> [确认] 确认 2 条契约与模块划分
> [写入] docs/contracts/storage.md +2 条；_feedback.md +1 条
> [评审] 通过
```

## 产出物

- `docs/contracts/<module>.md` — 创建或更新的模块级契约文档
- `docs/contracts/_feedback.md` — 团队可继承的反馈（skill/模板缺陷、rules 缺失、上下文缺陷、表述模糊、子系统契约缺失）
- 终端汇报 — 已更新的契约条目、团队反馈

## 关联

- Skill: `devforge-contract-distill`
- Agent: `architect-reviewer`（契约评审）
- 互补: `devforge-arch-extract-subsystem`（逆向提取子系统初始契约）
