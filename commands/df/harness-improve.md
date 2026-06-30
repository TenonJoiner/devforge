# /df:harness-improve

从开发者 trace 数据中诊断 harness 缺陷，输出结构化 issues 列表。

## 何时使用

- 收到开发者反馈某个 skill 质量下降
- 定期扫描 trace 数据，发现 harness 退化信号
- 新增 skill 后观察实际使用表现

## 参数

```
/df:harness-improve --trace_dir <path> --project_dir <path>
```

- `--trace_dir`（必选）：单个项目的原始 trace 包目录路径（存储层已按项目分目录）
- `--project_dir`（必选）：开发者项目源码目录路径，用于读取项目级上下文文件诊断缺陷

## 使用示例

```
/df:harness-improve --trace_dir /tmp/traces/devforge --project_dir /path/to/project
> 读取 /tmp/traces/devforge (8 sessions, 3 devs)
> [蒸馏] 8/8 完成
> [聚合] 跨开发者概览已生成
> [分析] 发现 3 个共性模式 issue, 1 个个人模式 issue
> issues 已写入 $WORK_DIR/issues.md
```

## 产出物

- `$WORK_DIR/aggregate.md` — 跨开发者聚合报告
- `$WORK_DIR/issues.md` — 结构化 issues 列表（含 DevForge 层和项目级）

## 关联

- Skill: `devforge-harness-improve`
- Agent: `harness-engineer`
- Hook: `trace-collector`, `trace-upload`
