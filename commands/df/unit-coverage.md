# /df:unit-coverage

单元测试覆盖率达标——执行单测、统计覆盖率、未达标补测遗漏分支。

## 用法

```
/df:unit-coverage [--autofix] [--full] [--diff-range <range>] [--report-output-path <path>]
```

| 参数 | 说明 |
|------|------|
| （无） | 统计当前分支 vs 基线分支的 diff 覆盖率（`git diff <base>...HEAD`，base 自动探测），只检测不补测 |
| `--autofix` | 覆盖率未达标时自动补测遗漏分支并回归（最多 5 轮） |
| `--full` | 全仓覆盖率 |
| `--diff-range <range>` | 显式指定 git diff 范围，优先级最高（由 pr-review 等调用方注入） |
| `--report-output-path <path>` | 指定验收报告写入路径，未提供时使用默认时间戳路径 |

范围确定优先级：`--diff-range` > `--full` > 默认（当前分支 vs 基线分支 diff）。

## 场景

- spec-driven 工作流 QA 阶段 `UNIT-COVERAGE` 任务的执行
- 验证当前分支新增代码的单元测试覆盖率（行/分支/函数）是否达标

## 产出物

覆盖率验收报告（写入文件，路径见参数）。

- **不带 `--autofix`**：输出覆盖率汇总与未覆盖项清单，不执行补测
- **带 `--autofix`**：未达标时定位遗漏分支补测并回归，最多 5 轮

阈值来源：项目上下文（rules/CLAUDE.md）显式定义 > 内置默认（行覆盖 90% / 函数覆盖 80% / 分支覆盖 70%）。diff 模式下阈值作用于新增代码，`--full` 模式下作用于全仓。

**项目上下文需声明两项**：
- **覆盖率命令**（脚本 / make target / npm script 等形式不限）：接受可选 diff 范围参数——不传时输出全仓覆盖率（行/分支/函数），传入时只输出该范围内新增代码的覆盖率
- **覆盖率数据路径**：命令产出结构化覆盖率数据的位置，skill 从此处读取

## 示例

**默认（分支 diff）**：

```
/df:unit-coverage --autofix
> 范围: git diff origin/main...HEAD（新增 12 个文件 / 修改 5 个文件）
> 阈值: 行 90% / 函数 80% / 分支 70%（内置默认，新增代码）
> 执行单测 + 收集覆盖率...
> 行 86% / 分支 72% / 函数 91% —— 行未达标
> 定位遗漏分支（错误处理 3 处、防御性分支 2 处）→ 补测
> 回归: 行 92% / 分支 75% / 函数 92% —— 全部达标 ✅
```

**全仓覆盖率**：

```
/df:unit-coverage --full
> 范围: 全仓
> 阈值: 行 90% / 函数 80% / 分支 70%（内置默认）
> 执行单测 + 收集覆盖率...
> 行 78% / 分支 65% / 函数 85% —— 行与分支未达标
```

执行细节进入 `devforge-unit-coverage` Skill。

## 关联

- **Skill**: `devforge-unit-coverage`
- **Agent**: `tester`（解析覆盖率数据）、`developer`（补测）
- **上游**: `devforge-tdd-workflow`（开发期行为驱动测试）
