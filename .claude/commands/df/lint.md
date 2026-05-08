# /df:lint

编译检查与静态分析。按项目配置自动探测语言工具链。

## 何时使用

- 修改代码后快速验证（fast 模式）
- 提交前最终检查（fast 模式）
- `/df:tdd` 后的补充验证（fast 模式）
- 特性级 archive 前或 QA 阶段质量收尾

## 执行流程

1. 激活 `developer` Agent
2. 进入 `code/lint-check` Skill：
   - L1：编译检查（探测构建脚本，验证 zero warning，生成 compile_commands.json）
   - L2：静态分析（按项目配置自动探测工具：clang-tidy + cppcheck / clippy / golangci-lint / ruff / eslint 等）
3. 汇总检查结果
4. 如发现问题，提供修复建议

## 参数

```
/df:lint [target]
```

- `target`（可选）：指定要检查的目标文件或目录

## 使用示例

```
/df:lint
> L1 编译检查
>   ✓ make: 0 error, 0 warning
>
> L2 静态分析
>   ✓ clang-tidy: 0 error, 0 warning
>   ✓ cppcheck: 0 error, 0 warning
>
> 总计: 0 error, 0 warning
```

## 关联

- Skill: `code/lint-check`
- Agent: `developer`
- Rules: `coding-style`
- Hooks: `pre-commit-lint`
