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
