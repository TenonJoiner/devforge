## 0.1.7 - 2026.09.24

1. 新增 contract-distill 模块级契约蒸馏 skill，生成代码如不符合预期，经过多轮调整后，在同会话中执行本 skill，把代码调整中暴露的「预期 vs 生成之差」反推为模块级契约，沉淀到 `docs/contracts/`
   使用：/df:contract-distill               # 提取当前分支代码调整涉及的模块契约
         /df:contract-distill --base <ref>  # 指定本次调整范围的 git 基点

2. 新增 unit-coverage skill，执行单测并统计覆盖率，未达标时定位遗漏分支自动补测；需在项目上下文中声明覆盖率命令与数据路径
   使用：/df:unit-coverage            # 统计分支 diff 覆盖率，只检测不补测
         /df:unit-coverage --autofix   # 未达标自动补测并回归
         /df:unit-coverage --full      # 统计全仓覆盖率

3. log-audit 新增日志覆盖维度：能查出错误被静默吞掉、失败路径上没留任何日志这类「事后查不到原因」的问题，定位信息更完整

4. code-review 会先读本次变更的 specs 和 design 再评审，减少「设计上本就如此、却被当成缺陷」的误报

5. proposal / specs / design 三份文档更易读：术语一律白话直述，禁止生造复合词，圈内黑话要么译成白话要么不用，评审时也会检查这一点

6. design 文档更贴合变更规模：简单变更不必硬凑章节，复杂变更必须把关键决策写明确——说清选哪个、为什么否决其他方案、量化约束是什么；原 `Interface Changes` 扩展为 `Contracts`，并新增「实现约束」章节，进一步明确实现层面的方案，避免生成代码时自由发挥；评审时会核对声明的档位与实际复杂度是否匹配

7. tasks 任务清单质量提升：任务按依赖关系自动排序，不会做到中途才发现缺前置模块；开工前多一道独立校验，核对清单是否覆盖 specs 全部场景与 NFR、执行顺序是否成立，有问题先修清单再开工

8. plugin 精简：6 个暂未维护的 skill（product-define、product-design、feature-define、feature-design、plan、test-design）及其 `/df:*` 命令移出 plugin，这些命令不再可用

9. arch-extract 系列（子系统 / 系统 / 技术主题的逆向提取）产出更可靠：结论会回溯源码核验而非凭推测、术语按项目词汇表统一、图能正常渲染、篇幅受控不注水

10. 模型分配调整：写代码的 agent 与做评审的 agent 使用不同模型交叉验证，减少「自己写自己审」导致的漏审；执行类任务改用能力更强的模型

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
