# /df:baseline

OpenSpec 变更文档基线化归档——将已通过 Tech Leader 评审的 change 文档归档到基线仓库。

## 使用场景

- 某个 change 已完成 review 且 Tech Leader 决策为 `PASS` / `PASS WITH CONDITIONS` 后，将其文档归档到基线仓库
- 需要跨版本长期保存已冻结的 spec/design

## 输出物

- 基线化仓库中的 `baseline/<version>/<repo-name>/<change-name>/` 目录，包含该 change 的核心文档

## 调用方式

调用 Skill 工具加载 `devforge-baseline`：

```
/df:baseline --change <name> --version <version> --repo-url <url>
```

- `--change <name>`：change 名称，例如 `add-storage-wal`。默认从当前 `openspec/changes/<name>/` 目录自动识别
- `--version <version>`：产品版本号（必填）
- `--repo-url <url>`：基线化文档仓库的 git URL（必填）

## 示例

```
/df:baseline --change add-storage-wal --version V2R1C01 --repo-url git@github.com:org/specs-baseline.git
```
