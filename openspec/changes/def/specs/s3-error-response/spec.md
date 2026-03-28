## ADDED Requirements

### Requirement: S3 XML 错误响应格式

**追溯**：`不适用：首次引入 S3 兼容层，无前置需求文档`

S3 Gateway MUST 以 AWS S3 标准 XML 格式返回错误响应，确保 S3 客户端能正确解析错误信息。

#### Scenario: 返回标准格式错误响应
- **WHEN** 任何 S3 操作处理过程中发生业务错误（如 bucket 不存在、签名错误、权限不足）
- **THEN** S3 Gateway MUST 返回 Content-Type 为 `application/xml` 的响应体，格式为：
  ```xml
  <?xml version="1.0" encoding="UTF-8"?>
  <Error>
    <Code>错误码</Code>
    <Message>人类可读的错误描述</Message>
    <Resource>请求的资源路径</Resource>
    <RequestId>请求唯一标识</RequestId>
  </Error>
  ```
  HTTP 状态码 MUST 与错误码对应（如 NoSuchBucket→404、AccessDenied→403、InternalError→500）

#### Scenario: 非 S3 操作的 HTTP 错误
- **WHEN** 请求在 HTTP 层就被拒绝（如 HTTP 400 Bad Request、431 Header Too Large），尚未进入 S3 操作路由
- **THEN** S3 Gateway MUST 返回标准 HTTP 错误响应（无 XML Body），仅包含状态码和原因短语

### Requirement: 错误码覆盖

**追溯**：`不适用：首次引入 S3 兼容层，无前置需求文档`

S3 Gateway MUST 支持以下错误码，每个错误码 MUST 对应正确的 HTTP 状态码和描述信息。

| 错误码 | HTTP 状态码 | 触发场景 |
|--------|-----------|---------|
| AccessDenied | 403 | 缺少 Authorization 头 |
| InvalidAccessKeyId | 403 | AccessKey 不存在 |
| SignatureDoesNotMatch | 403 | 签名验证失败 |
| RequestTimeTooSkewed | 403 | 请求时间偏差超过 15 分钟 |
| AuthorizationHeaderMalformed | 400 | Authorization 头格式错误 |
| NoSuchBucket | 404 | 目标 bucket 不存在 |
| MethodNotAllowed | 405 | 请求方法不允许（如 PUT 到 bucket 级别） |
| EntityTooLarge | 400 | 请求体超过大小限制 |
| MissingContentLength | 411 | 缺少 Content-Length 头 |
| MetadataTooLarge | 400 | 自定义元数据总大小超过 2KB |
| IncompleteBody | 400 | 实际数据长度与 Content-Length 不一致 |
| NotImplemented | 501 | 请求的 S3 操作尚未实现 |
| InternalError | 500 | 存储引擎内部错误 |

#### Scenario: 已定义的错误码
- **WHEN** S3 操作触发上述表格中列出的错误条件
- **THEN** S3 Gateway MUST 返回对应的错误码、HTTP 状态码和描述信息

#### Scenario: 未预期的内部错误
- **WHEN** 处理过程中发生未被以上错误码覆盖的异常情况（如内存分配失败、意外的程序状态）
- **THEN** S3 Gateway MUST 返回错误码 `InternalError`，HTTP 状态码 500，Message 为 `We encountered an internal error. Please try again.`。MUST 不得在错误响应中泄露内部实现细节（如堆栈、文件路径、内存地址）

### Requirement: RequestId 生成

**追溯**：`不适用：首次引入 S3 兼容层，无前置需求文档`

S3 Gateway MUST 为每个请求生成唯一的 RequestId，用于错误排查和日志关联。

#### Scenario: 每个请求获得唯一 RequestId
- **WHEN** S3 Gateway 处理任意请求（无论成功或失败）
- **THEN** S3 Gateway MUST 生成一个全局唯一的 RequestId（建议 16 字节十六进制字符串），通过响应头 `x-amz-request-id` 返回（无论成功或失败）；当返回错误 XML 时，同时在 `<RequestId>` 字段中包含该值

#### Scenario: 高并发下 RequestId 唯一性
- **WHEN** 多个请求在极短时间内并发到达
- **THEN** 每个请求的 RequestId MUST 互不相同

## MODIFIED Requirements

## REMOVED Requirements

## RENAMED Requirements
