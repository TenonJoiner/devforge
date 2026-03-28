## ADDED Requirements

### Requirement: 对象写入

**追溯**：`不适用：首次引入 S3 兼容层，无前置需求文档`

S3 Gateway MUST 支持通过 HTTP PUT 方法将对象写入指定 bucket，兼容 AWS S3 PutObject 语义。

#### Scenario: 成功写入新对象
- **WHEN** 客户端发送合法的 PUT 请求到 `/<bucket>/<key>`，签名验证通过，请求体包含对象数据，bucket 已存在
- **THEN** S3 Gateway MUST 将对象数据和元数据写入存储引擎，返回 HTTP 200，响应头包含 `ETag`（对象数据的 MD5 十六进制摘要，用双引号包裹，如 `"d41d8cd98f00b204e9800998ecf8427e"`）

#### Scenario: 覆盖已有对象
- **WHEN** 客户端发送 PUT 请求写入一个已存在的 object key
- **THEN** S3 Gateway MUST 用新数据完整覆盖旧对象，返回新对象的 ETag。覆盖操作 MUST 是原子的——要么完全覆盖成功，要么保持旧对象不变

#### Scenario: 目标 bucket 不存在
- **WHEN** 客户端发送 PUT 请求到 `/<bucket>/<key>`，但指定的 bucket 在存储引擎中不存在
- **THEN** S3 Gateway MUST 返回 S3 错误响应，HTTP 状态码 404，错误码 `NoSuchBucket`

#### Scenario: 两个客户端同时写入同一 key
- **WHEN** 两个客户端并发发送 PUT 请求写入同一 `<bucket>/<key>`
- **THEN** S3 Gateway MUST 保证最终存储的对象是两个请求中某一个的完整数据（不得出现数据混合），返回各自的 ETag。最终结果取决于存储引擎的写入完成顺序

#### Scenario: 写入过程中存储引擎故障
- **WHEN** 对象数据已接收完毕，但调用存储引擎写入时返回错误（如磁盘故障、空间不足）
- **THEN** S3 Gateway MUST 返回 S3 错误响应，HTTP 状态码 500，错误码 `InternalError`。MUST 确保失败的写入不会留下部分数据（无残留）

### Requirement: 自定义元数据

**追溯**：`不适用：首次引入 S3 兼容层，无前置需求文档`

S3 Gateway MUST 支持通过请求头传递自定义元数据，以 `x-amz-meta-` 前缀标识，元数据 MUST 与对象一同持久化存储。

#### Scenario: 携带自定义元数据写入
- **WHEN** 客户端发送 PutObject 请求，包含一个或多个 `x-amz-meta-*` 请求头（如 `x-amz-meta-author: zhang`、`x-amz-meta-version: 1.0`）
- **THEN** S3 Gateway MUST 提取所有 `x-amz-meta-` 前缀的头部，将键值对作为元数据与对象一同写入存储引擎

#### Scenario: 元数据总大小超过限制
- **WHEN** 客户端发送 PutObject 请求，所有 `x-amz-meta-*` 头的键值对总大小（键+值的 UTF-8 字节数之和）超过 2KB
- **THEN** S3 Gateway MUST 返回 S3 错误响应，HTTP 状态码 400，错误码 `MetadataTooLarge`

### Requirement: Content-Type 处理

**追溯**：`不适用：首次引入 S3 兼容层，无前置需求文档`

S3 Gateway MUST 将客户端指定的 Content-Type 作为对象的内容类型进行持久化存储。

#### Scenario: 客户端指定 Content-Type
- **WHEN** 客户端发送 PutObject 请求，包含 `Content-Type: application/json` 头
- **THEN** S3 Gateway MUST 将 `application/json` 作为对象的内容类型存储到存储引擎

#### Scenario: 客户端未指定 Content-Type
- **WHEN** 客户端发送 PutObject 请求，未携带 Content-Type 头
- **THEN** S3 Gateway MUST 使用默认值 `application/octet-stream` 作为对象的内容类型

### Requirement: ETag 计算

**追溯**：`不适用：首次引入 S3 兼容层，无前置需求文档`

S3 Gateway MUST 对写入的对象数据计算 MD5 摘要作为 ETag，用于数据完整性标识。

#### Scenario: 正常计算 ETag
- **WHEN** 客户端成功写入一个对象
- **THEN** S3 Gateway MUST 计算对象完整数据的 MD5 摘要（128 位），以 32 字符十六进制小写字符串表示，用双引号包裹后放入响应头 `ETag` 字段（如 `ETag: "098f6bcd4621d373cade4e832627b4f6"`）

#### Scenario: 空对象的 ETag
- **WHEN** 客户端发送 PutObject 请求，Content-Length 为 0（空对象）
- **THEN** S3 Gateway MUST 成功写入空对象，返回空数据的 MD5 值作为 ETag（`"d41d8cd98f00b204e9800998ecf8427e"`）

### Requirement: Content-Length 与实际数据一致性校验

**追溯**：`不适用：首次引入 S3 兼容层，无前置需求文档`

S3 Gateway MUST 校验实际接收的数据长度与 Content-Length 头声明的值一致。

#### Scenario: 数据长度与 Content-Length 一致
- **WHEN** 客户端发送 PutObject 请求，Content-Length 声明为 1024 字节，实际发送 1024 字节数据后关闭发送端
- **THEN** S3 Gateway MUST 正常处理该请求

#### Scenario: 实际数据短于 Content-Length
- **WHEN** 客户端发送 PutObject 请求，Content-Length 声明为 1024 字节，但实际仅发送 512 字节后关闭连接
- **THEN** S3 Gateway MUST 检测到数据不完整，丢弃已接收的数据，不写入存储引擎，返回 S3 错误响应，HTTP 状态码 400，错误码 `IncompleteBody`

#### Scenario: 实际数据超过 Content-Length
- **WHEN** 客户端发送 PutObject 请求，Content-Length 声明为 1024 字节，但在发送 1024 字节后继续发送额外数据
- **THEN** S3 Gateway MUST 仅接收 Content-Length 声明长度的数据，忽略超出部分，正常处理请求

## MODIFIED Requirements

## REMOVED Requirements

## RENAMED Requirements
