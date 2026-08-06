## 0.1.6 - 2026.08.06

1. 新增 log-audit skill，审计日志级别合理性与打印频率，支持 `--autofix` 自动修复，已集成到 pr-review 作为并行门禁
   使用：/df:log-audit                     # 审计工作区未提交变更
         /df:log-audit --autofix           # 审计并自动修复
         /df:log-audit --log-dir /var/log  # 结合运行时日志做频率分析

2. lint-check 强化：告警交叉验证分析，防止越界扩展检查范围；完善 lint 脚本、Makefile 及 linting.md 上下文
   使用：/df:lint              # 增量检查工作区未提交变更
         /df:lint --full       # 全仓 lint 检查
         /df:lint --autofix    # 检查并自动修复

3. pr-review 增加 lint-check 和 log-audit 作为下游检查，MR 门禁从单维扩展为三维（代码评审 + 编译/lint + 日志审计）

4. openspec schema 强化：新增 merge-first 原则防止 Capability 过度拆分，tasks 阶段前加入基线归档门禁

5. 新增 plugin 自动升级 hook，定期检查并自动更新

## 0.1.5 - 2026.07.07

1. 优化 openspec 模板及指令，结合项目上下文优化 proposal 和 spec 文档的写作质量

2. 优化 code-review 和 lint skill，更加适配 openspec workflow 流程，减少摩擦

3. 新增 pr-review skill，集成到 CI 流水线作为门禁

4. 新增 setup skill，一键安装 devforge plugin 运行依赖
   使用：/df:setup

5. 新增 harness-improve loop，用于观察并改进 skill 体系和项目上下文，减少 Coding Agent 使用过程中的摩擦

## 0.1.4 - 2026.06.26

1. workflow 在 design/spec 之后、tasks 之前引入 review 环节作为强制门禁，通过评审后才能进入后续环节

2. 新增 spec-review 文档评审 skill，辅助 review 环节
   使用：/df:spec-review              # 评审 change 目录下的文档
         /df:spec-review --autofix    # 评审并自动修复

3. 新增 baseline 文档基线化 skill，review 通过后将核心文档归档到基线仓库
   使用：/df:baseline

4. 新增 coding-style-generator skill，各仓库负责人执行一次即可生成适用于本仓库的编码规范
   使用：/df:coding-style

5. 新增 git-workflow 规范，统一分支命名、MR 规范和 atomic commit 规范
