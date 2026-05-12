---
template-for: 评审报告（任意被评审对象，统一格式）
mandatory-sections:
  - 评审元数据
  - 问题清单
  - 缺陷密度
  - 评审结论
optional-sections: []
checklist-at-end: true
---

# 评审报告：<被评审文件名>

> **本模板只定义评审输出的格式骨架**。评审视角不在此处定义——视角来源为：
> 1. **对象特异视角**（评审项）：被评审 template 的 `mandatory-sections` + `checklist-at-end`
> 2. **场景特异视角**（评审深度）：skill 派遣 prompt 中动态注入的特异性子维度
> 3. **评审思维风格**：reviewer agent 的角色定位（业务视角 / 技术视角 / 进度视角）
>
> 禁止在 reviewer 人设或本格式模板中硬编码任何具体评审项。

---

## 评审元数据

| 字段 | 值 |
|------|-----|
| 评审日期 | YYYY-MM-DD HH:MM |
| 评审人 | <reviewer agent 角色> |
| 评审对象 | <被评审文件路径> |
| 评审依据 template | <被评审 template 路径>（视角来源 1） |
| 特异性子维度 | <skill 派遣 prompt 注入的子维度概要>（视角来源 2） |
| 评审思维风格 | <reviewer 角色定位概要>（视角来源 3） |
| 评审结论数字摘要 | CRITICAL N / HIGH N / MEDIUM N / LOW N |

---

## 问题清单

> 每条问题按以下统一格式编写。"所属维度"取值必须来自被评审 template 的 mandatory-section 名或 checklist-at-end 项，或派遣 prompt 注入的特异性子维度名。

### CRITICAL

**C1. <简短问题标题>**

- **所属维度**：<取自被评审 template 或派遣 prompt 注入的维度名>
- **问题描述**：<具体问题，含被评审文件中的位置引用>
- **理由**：<为什么这是问题，影响是什么>
- **修复建议**：<可操作的修正方向>

### HIGH

（同 CRITICAL 格式）

### MEDIUM

（同 CRITICAL 格式）

### LOW

（同 CRITICAL 格式）

---

## 缺陷密度

| 项 | 值 |
|-----|-----|
| 评估对象数 | N（如标杆数 / 里程碑点数 / Feature 数） |
| 总加权分 | X（按 CRITICAL=10 / HIGH=3 / MEDIUM=1 / LOW=0.1 加权） |
| 密度 | X / N = Y 分/对象 |
| 密度门槛 | ≤ 2.0 分/对象（由 skill 阶段文件声明，此处仅引用） |

---

## 评审结论

- [ ] 评审结论：**PASS** / **NEEDS-FIX** / **FAIL**
- [ ] 缺陷密度 ≤ 阈值（具体阈值见 skill 阶段文件）
- [ ] 无 CRITICAL 问题（或 CRITICAL 问题已全部记录修复建议）
- [ ] HIGH 问题已逐条评估：接受修正 / 接受延期 / 拒绝

> 若 PASS，在被评审文件末尾按 SKILL.md「评审状态标记契约」格式追加 `**评审状态**: ✅ PASS` 标记。

---

## 自检清单

> 本清单只检查**评审报告的格式完整性**，不检查具体评审维度（具体维度由被评审 template 和派遣 prompt 决定）。

- [ ] 评审元数据 6 个字段全部填写
- [ ] 问题清单中每条问题包含：标题 / 所属维度 / 问题描述 / 理由 / 修复建议（缺一不可）
- [ ] 每条问题的"所属维度"字段值可溯源到被评审 template 或派遣 prompt
- [ ] 缺陷密度已按公式计算并填入
- [ ] 评审结论已明确标注 PASS / NEEDS-FIX / FAIL
- [ ] CRITICAL 和 HIGH 级别问题已全部列出（数量与评审结论数字摘要一致）
