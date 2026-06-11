---
name: zentao-cli
description: 通过 zentao 命令行工具查询和操作禅道（ZenTao）中的产品、项目、执行和 Bug 数据，支持列表、详情、创建、更新、删除，以及 Bug 的确认、激活、关闭、解决、指派和评论。当用户提到禅道、zentao、查询产品/项目/执行、获取或处理 Bug 等项目管理操作时使用本技能。
license: MIT
metadata:
  author: Sun Hao <sunhao@chandao.com>
  repository: https://github.com/easysoft/zentao-cli.git
  keywords: [zentao, 禅道, cli, project-management]
  version: 0.1.6
---

# 禅道 CLI

通过 `zentao` 命令行工具查询和操作禅道数据。CLI 自动处理认证、分页，支持工作区上下文和数据过滤/排序。

## API 版本边界

当前只能使用已经迁移到 ZenTao RESTful API v1 的模块。仍停留在 v2 的模块不要使用；如果用户需要这些模块，先说明当前技能不能可靠调用，等待模块迁移到 v1 后再执行。

| 模块名 | 中文 | API 状态 | 使用建议 |
|--------|------|----------|----------|
| product | 产品 | v1 可用 | 可列表、详情、创建、更新、删除 |
| project | 项目 | v1 可用 | 可列表、详情、创建、更新、删除 |
| execution | 执行/迭代 | v1 可用 | 可按项目列表、详情、创建、更新、删除 |
| bug | Bug | v1 可用 | 可按产品列表、详情、创建、更新、删除、确认、关闭、激活、解决、指派、评论 |
| program | 项目集 | 仍为 v2 | 不要使用 |
| story / epic / requirement | 需求类 | 仍为 v2 | 不要使用 |
| task | 任务 | 仍为 v2 | 不要使用 |
| testcase / testtask | 测试类 | 仍为 v2 | 不要使用 |
| productplan / build / release | 计划、版本、发布 | 仍为 v2 | 不要使用 |
| feedback / ticket / system / user / file | 反馈、工单、应用、用户、附件 | 仍为 v2 | 不要使用 |

## 前置准备

### 安装

```bash
npm install -g @singee/zentao-cli
# 或 bun install -g @singee/zentao-cli
# 或 pnpm install -g @singee/zentao-cli
# 或免安装运行：npx @singee/zentao-cli
```

如果用户没有安装，引导用户进行全局安装使用，如果系统存在 bun 或 pnpm 则优先使用 bun 或 pnpm 进行全局安装。

### 认证

首次执行任意 `zentao` 命令会自动提示登录。也可显式登录：

```bash
zentao login -s https://zentao.example.com -u admin -p 123456
```

环境变量（优先级低于命令行参数）：

| 变量 | 说明 |
|------|------|
| `ZENTAO_URL` | 禅道服务地址 |
| `ZENTAO_ACCOUNT` | 用户账号 |
| `ZENTAO_PASSWORD` | 密码 |
| `ZENTAO_TOKEN` | 直接指定 Token（有此变量可省略密码） |

登录成功后凭证缓存在 `~/.config/zentao/zentao.json`，后续无需重复登录。

### 凭证安全

- 用户尚未登录时，不要在对话里收集账号密码。让用户直接在终端执行 `zentao login`，或执行任意 `zentao` 命令触发首次自动登录提示，由用户自行输入凭证。
- 严禁读取本地凭证：`ZENTAO_PASSWORD` / `ZENTAO_TOKEN` 环境变量、`~/.config/zentao/zentao.json` 配置文件。所有禅道数据均通过 `zentao` 命令获取，凭证由 CLI 内部处理。

## 命令格式

使用简写方式（推荐）：

| 操作 | 命令 |
|------|------|
| 列表 | `zentao <module>` |
| 详情 | `zentao <module> <id>` |
| 创建 | `zentao <module> create --field=value` |
| 更新 | `zentao <module> update <id> --field=value` |
| 删除 | `zentao <module> delete <id>` |
| 动作 | `zentao <module> <action> <id>` |
| 帮助 | `zentao <module> help` |

也支持 `--data='JSON'` 传入 JSON 数据。需要检查即将发送的 HTTP 请求但不实际调用 API 时，加 `--dry-run`。

## 模块与操作速查

| 模块名 | 中文 | 支持的操作 |
|--------|------|-----------|
| product | 产品 | CRUD |
| project | 项目 | CRUD |
| execution | 执行/迭代 | CRUD |
| bug | Bug | CRUD + confirm / activate / close / resolve / assign / comment |

> CRUD = 列表 + 详情 + 创建 + 更新 + 删除；CUD = 无独立列表接口，需指定所属范围

### 列表范围参数

部分模块的列表需要指定所属范围：

```bash
zentao bug --product=1                  # 产品 #1 的 Bug
zentao execution --project=5            # 项目 #5 的执行
```

设置工作区后可省略这些参数（见下方工作区章节）。

## AI 使用策略

### 输出格式

- 展示给用户：不加 `--format` 参数，默认输出 Markdown 表格（列表）或列表（单个对象）
- 需要程序化处理：加 `--format=json`，返回结构化 JSON

### 交互确认

AI 场景下执行删除操作时加 `--yes` 跳过确认提示：

```bash
zentao bug delete 1 --yes
```

写操作前需要检查请求体时加 `--dry-run`：

```bash
zentao bug resolve 42 --resolution=fixed --comment=已解决 --dry-run
```

### 不知道 ID 时

先查列表获取 ID，再操作具体对象：

```bash
zentao product --pick=id,name           # 查看产品列表
zentao bug --product=1 --pick=id,title  # 查看 Bug 列表
zentao bug 42                           # 查看具体 Bug
```

### 写操作前确认

执行创建、更新、删除等写操作前，先向用户确认操作内容。用户明确要求不确认时可跳过。

## 数据处理

### 摘取字段

```bash
zentao product --pick=id,name,status
```

### 过滤

```bash
zentao bug --product=1 --filter='status:active'
zentao bug --product=1 --filter='assignedTo.account:xuan.wang'
zentao bug --product=1 --filter='severity<=2,pri<=2'    # AND
zentao bug --product=1 --filter='status:active' --filter='status:resolved'  # OR
```

支持的运算符：`:` 等于、`!=` 不等于、`>` `<` `>=` `<=`、`~` 包含、`!~` 不包含。

Bug 指派人筛选要使用嵌套字段路径，不要写 `assignedTo:<account-id>`：

```bash
zentao bug --product <productID> --filter='assignedTo.account:<account-id>'
```

`--filter` 是本地过滤，只过滤当前接口返回的数据；需要更完整结果时提高分页大小，例如加 `--recPerPage=100`。

### 模糊搜索

```bash
zentao bug --product=1 --search=登录 --search-fields=title,steps
```

### 排序

```bash
zentao bug --product=1 --sort=pri_asc,severity_asc
```

### 分页

```bash
zentao bug --product=1 --page=1 --recPerPage=50
zentao bug --product=1 --all            # 获取全部
zentao bug --product=1 --limit=10       # 只取前 10 条
```

## 常用操作示例

### 查看进行中的项目和执行

```bash
zentao project --filter='status:doing' --pick=id,name,status
zentao execution --project=5 --pick=id,name,status
```

### 创建需求并关联计划

```bash
当前需求模块仍为 v2，不要使用。
```

### 创建并解决 Bug

```bash
zentao bug create --product=1 --title="Bug标题" --severity=2 --pri=2 --type=codeerror --openedBuild=trunk
zentao bug resolve 42
```

### 指派 Bug

```bash
zentao bug assign 42 --assignedTo=xiaodong.chen
zentao bug assign 42 --assignedTo=xuan.wang --comment="已完成验证，指派回原处理人"
```

### 添加 Bug 评论

```bash
zentao bug comment 42 --comment="补充说明"
zentao bug comment 42 --comment=$'原因：复现路径已确认\n修复：已调整边界处理\n修复信息：随下一次发布交付'
```

`--comment` 会由 CLI 统一进行 HTML escape；不要提前把 `<`、`>`、`&` 等字符手工转义。

### 创建、启动并完成任务

```bash
当前任务模块仍为 v2，不要使用。
```

### 查看帮助

```bash
zentao bug help          # 查看 Bug 模块的参数和操作
zentao project help      # 查看项目模块的参数和操作
zentao help              # 查看所有命令
```

## 意图识别

| 用户意图 | CLI 命令 |
|---------|---------|
| 所有产品/项目 | `zentao product` / `zentao project` |
| 进行中的项目 | `zentao project --filter='status:doing'` |
| 某产品的 Bug | `zentao bug --product=<id>` |
| 创建/新增 Bug | `zentao bug create ...` |
| 解决 Bug | `zentao bug resolve <id>` |
| 指派 Bug | `zentao bug assign <id> --assignedTo=<account>` |
| 添加 Bug 评论 | `zentao bug comment <id> --comment="..."` |
| 关闭 Bug | `zentao bug close <id>` |
| 激活 Bug | `zentao bug activate <id>` |
| 查询执行 | `zentao execution --project=<projectID>` |
| 需求/任务/测试/计划/版本等 | 仍为 v2，当前不要使用 |
| 当前用户信息 | `zentao profile` |

## 错误处理

| 错误码 | 含义 | 处理方式 |
|--------|------|---------|
| E1001 | 未登录/凭证缺失 | 执行 `zentao login` |
| E1004 | Token 失效 | 执行 `zentao login` 重新登录 |
| E2001 | 模块不存在 | 执行 `zentao help` 查看可用模块 |
| E2002 | 对象不存在 | 检查 ID 是否正确 |
| E2003 | 缺少必要参数 | 执行 `zentao <module> help` 或 `zentao <module> <action> help` 查看操作参数 |
| E2006 | 无权限 | 提示用户检查权限 |
| E5001 | 请求超时 | 检查网络或禅道服务状态 |

## 注意事项

- 不确定模块参数时，先执行 `zentao <module> help` 查看帮助，不确定操作参数时，先执行 `zentao <module> <action> help` 查看帮助
- `browseType` 常用值：`all`（全部）、`doing`（进行中）、`closed`（已关闭）
- 多账号切换：`zentao profile` 查看和切换账号
