## ADDED Requirements

### Requirement: HTTP 请求接收

**追溯**：`不适用：首次引入 S3 兼容层，无前置需求文档`

S3 Gateway MUST 在配置指定的端口上监听 TCP 连接，接收并解析 HTTP/1.1 请求。MUST 支持 GET、PUT、DELETE、HEAD 方法（首期仅路由 PUT，其余返回 501 Not Implemented）。

#### Scenario: 正常接收 PUT 请求
- **WHEN** 客户端向 S3 Gateway 监听端口发送一个合法的 HTTP/1.1 PUT 请求，包含 Host、Content-Length、Authorization 头
- **THEN** S3 Gateway MUST 完整解析请求行（方法、URI、版本）和所有请求头，将解析结果传递给 S3 路由层处理

#### Scenario: 接收到格式错误的 HTTP 请求
- **WHEN** 客户端发送的数据不符合 HTTP/1.1 协议格式（如缺少请求行、头部格式错误、非法字符）
- **THEN** S3 Gateway MUST 返回 HTTP 400 Bad Request 响应并关闭连接

#### Scenario: 请求头超过大小限制
- **WHEN** 客户端发送的请求头总大小超过 8KB
- **THEN** S3 Gateway MUST 返回 HTTP 431 Request Header Fields Too Large 响应并关闭连接

### Requirement: 连接生命周期管理

**追溯**：`不适用：首次引入 S3 兼容层，无前置需求文档`

S3 Gateway MUST 管理每个 TCP 连接的完整生命周期，从 accept 到 close，确保无资源泄漏。

#### Scenario: 正常连接处理完成
- **WHEN** 一个请求处理完成并发送响应后
- **THEN** S3 Gateway MUST 关闭该 TCP 连接并释放所有关联资源（文件描述符、缓冲区、请求上下文）

#### Scenario: 客户端中途断开连接
- **WHEN** 客户端在请求处理过程中（请求体传输中或响应发送前）关闭 TCP 连接
- **THEN** S3 Gateway MUST 检测到连接断开，取消正在进行的操作，释放所有关联资源，不得产生资源泄漏

#### Scenario: 连接数达到上限
- **WHEN** 当前活跃连接数已达到配置的最大值（默认 10000），新客户端尝试建立连接
- **THEN** S3 Gateway MUST 拒绝新连接（accept 后立即关闭），已有连接不受影响

### Requirement: S3 Path-Style 路由

**追溯**：`不适用：首次引入 S3 兼容层，无前置需求文档`

S3 Gateway MUST 支持 Path-Style URL 格式解析，从请求 URI 中提取 bucket 名称和 object key。

#### Scenario: 正常 Path-Style URL 解析
- **WHEN** 客户端发送 PUT 请求，URI 为 `/<bucket-name>/<object-key>`（如 `/my-bucket/path/to/file.txt`）
- **THEN** S3 Gateway MUST 正确提取 bucket 名称为 `my-bucket`，object key 为 `path/to/file.txt`，并路由到对应的 S3 操作处理器

#### Scenario: URI 中缺少 object key
- **WHEN** 客户端发送 PUT 请求，URI 仅包含 bucket（如 `/my-bucket` 或 `/my-bucket/`）
- **THEN** S3 Gateway MUST 返回 S3 错误响应，错误码为 `MethodNotAllowed`（PUT 到 bucket 级别不是合法的 PutObject 操作）

#### Scenario: URI 为根路径
- **WHEN** 客户端发送请求，URI 为 `/`
- **THEN** S3 Gateway MUST 将其识别为服务级别操作（如 ListBuckets），首期返回 501 Not Implemented

### Requirement: 请求体大小限制

**追溯**：`不适用：首次引入 S3 兼容层，无前置需求文档`

S3 Gateway MUST 对请求体大小进行限制，防止单个请求消耗过多资源。

#### Scenario: 请求体在限制范围内
- **WHEN** 客户端发送 PutObject 请求，Content-Length 值不超过配置的最大值（默认 5GB）
- **THEN** S3 Gateway MUST 正常接收并处理该请求

#### Scenario: 请求体超过大小限制
- **WHEN** 客户端发送 PutObject 请求，Content-Length 值超过配置的最大值
- **THEN** S3 Gateway MUST 返回 S3 错误响应，HTTP 状态码 400，错误码 `EntityTooLarge`，不读取请求体，直接关闭连接

#### Scenario: 缺少 Content-Length 头
- **WHEN** 客户端发送 PUT 请求但未携带 Content-Length 头
- **THEN** S3 Gateway MUST 返回 S3 错误响应，HTTP 状态码 411，错误码 `MissingContentLength`

## MODIFIED Requirements

## REMOVED Requirements

## RENAMED Requirements
