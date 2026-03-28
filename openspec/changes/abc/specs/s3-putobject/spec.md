## ADDED Requirements

### Requirement: S3 PutObject 请求接收

**追溯**：`不适用：Phase 1 schema 验证用测试变更，无对应产品级需求文档`

系统 MUST 提供兼容 AWS S3 PutObject 协议的 HTTP 接口，接收 `PUT /{bucket}/{key}` 格式的请求，将对象数据和元数据持久化到存储引擎。

#### Scenario: 标准 PutObject 上传成功

- **WHEN** 客户端发送带有有效 AWS Signature V4 签名的 `PUT /{bucket}/{key}` 请求，请求体包含对象数据，且目标 bucket 已存在
- **THEN** 系统返回 HTTP 200，响应头包含 `ETag`（值为对象数据的 MD5 十六进制字符串），对象数据和元数据已持久化到存储引擎

#### Scenario: 目标 bucket 不存在

- **WHEN** 客户端发送 PutObject 请求，指定的 bucket 在系统中不存在
- **THEN** 系统返回 HTTP 404，响应体为 S3 标准 XML 错误格式，错误码为 `NoSuchBucket`

#### Scenario: 认证失败

- **WHEN** 客户端发送 PutObject 请求，但签名验证未通过（签名不匹配、凭证无效或已过期）
- **THEN** 系统返回 HTTP 403，响应体为 S3 标准 XML 错误格式，错误码为 `AccessDenied`

---

### Requirement: S3 PutObject 标准 Header 处理

**追溯**：`不适用：Phase 1 schema 验证用测试变更，无对应产品级需求文档`

系统 MUST 解析并处理 PutObject 请求中的以下标准 HTTP Header：`Content-Type`、`Content-Length`、`Content-MD5`、`x-amz-content-sha256`、`x-amz-date`。

#### Scenario: Content-Type 元数据持久化

- **WHEN** 客户端发送 PutObject 请求，请求头包含 `Content-Type: application/pdf`
- **THEN** 系统将 `application/pdf` 作为对象的 content-type 元数据持久化，后续获取对象时可返回此值

#### Scenario: Content-MD5 校验不匹配

- **WHEN** 客户端发送 PutObject 请求，请求头包含 `Content-MD5` 值，但该值与请求体的实际 MD5 不匹配
- **THEN** 系统返回 HTTP 400，响应体为 S3 标准 XML 错误格式，错误码为 `BadDigest`

#### Scenario: Content-Length 缺失

- **WHEN** 客户端发送 PutObject 请求，未携带 `Content-Length` 请求头
- **THEN** 系统返回 HTTP 411，响应体为 S3 标准 XML 错误格式，错误码为 `MissingContentLength`

---

### Requirement: S3 PutObject 用户自定义元数据

**追溯**：`不适用：Phase 1 schema 验证用测试变更，无对应产品级需求文档`

系统 MUST 支持通过 `x-amz-meta-*` 前缀的请求头传递用户自定义元数据，并与对象一起持久化。

#### Scenario: 用户自定义元数据上传

- **WHEN** 客户端发送 PutObject 请求，请求头包含 `x-amz-meta-author: zhangsan` 和 `x-amz-meta-version: 2`
- **THEN** 系统将这两个自定义元数据键值对与对象一起持久化

#### Scenario: 用户自定义元数据超出限制

- **WHEN** 客户端发送 PutObject 请求，用户自定义元数据的总大小超过 2KB
- **THEN** 系统返回 HTTP 400，响应体为 S3 标准 XML 错误格式，错误码为 `MetadataTooLarge`

---

### Requirement: S3 PutObject 对象覆盖

**追溯**：`不适用：Phase 1 schema 验证用测试变更，无对应产品级需求文档`

系统 MUST 支持对已存在的对象执行覆盖写入。对同一 bucket/key 再次执行 PutObject 时，新数据和元数据 SHALL 替换旧数据和元数据。

#### Scenario: 覆盖已有对象

- **WHEN** 客户端对已存在对象的 bucket/key 发送 PutObject 请求，携带新的数据和元数据
- **THEN** 系统返回 HTTP 200，响应头包含新的 `ETag`，对象的数据和元数据已被新内容完全替换

#### Scenario: 覆盖写入期间原对象可读

- **WHEN** 客户端对已存在对象执行覆盖写入，写入操作尚未完成
- **THEN** 对该对象的读取请求 SHALL 返回覆盖前的完整旧数据，不返回部分写入的新数据

---

### Requirement: S3 PutObject 错误响应格式

**追溯**：`不适用：Phase 1 schema 验证用测试变更，无对应产品级需求文档`

系统 MUST 以 S3 标准 XML 格式返回所有错误响应，包含 `Code`、`Message`、`Resource`、`RequestId` 字段。

#### Scenario: 错误响应包含标准字段

- **WHEN** 任意 PutObject 请求触发错误（如认证失败、bucket 不存在等）
- **THEN** 响应体为 XML 格式，根元素为 `<Error>`，包含 `<Code>`（错误码）、`<Message>`（人类可读描述）、`<Resource>`（请求的资源路径）、`<RequestId>`（唯一请求标识）四个子元素

#### Scenario: 未实现的 S3 功能

- **WHEN** 客户端发送 PutObject 请求携带了 Phase 1 未实现的 Header（如 `x-amz-server-side-encryption`、`x-amz-acl`）
- **THEN** 系统返回 HTTP 501，错误码为 `NotImplemented`，Message 中说明该功能尚未支持

---

### Requirement: S3 PutObject 大对象流式写入

**追溯**：`不适用：Phase 1 schema 验证用测试变更，无对应产品级需求文档`

系统 MUST 支持流式接收和写入大对象数据，单次 PutObject 请求 SHALL 支持最大 5GB 的对象大小。

#### Scenario: 大对象上传成功

- **WHEN** 客户端发送 PutObject 请求，对象大小为 1GB
- **THEN** 系统以流式方式接收并写入数据，返回 HTTP 200 和正确的 ETag，不要求将整个对象缓存在内存中

#### Scenario: 对象大小超过上限

- **WHEN** 客户端发送 PutObject 请求，Content-Length 超过 5GB
- **THEN** 系统返回 HTTP 400，错误码为 `EntityTooLarge`

## MODIFIED Requirements

<!-- 无已有能力变更 -->

## REMOVED Requirements

<!-- 无废弃功能 -->

## RENAMED Requirements

<!-- 无改名 -->
