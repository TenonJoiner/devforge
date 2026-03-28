## Why

当前分布式存储系统仅提供私有 API 接口，用户无法使用 AWS S3 SDK、s3cmd、rclone 等成熟生态工具直接访问存储服务。这导致：用户需针对私有 API 开发专用客户端，迁移成本高；无法对接已有的基于 S3 协议的数据处理管线（如 Spark、Presto、AI 训练框架）。

S3 PutObject 是对象存储最基础的写入接口，是兼容 S3 生态的第一步。没有 PutObject，后续的 GetObject、MultipartUpload 等接口也无从谈起。

## What Changes

- 新增 S3 兼容 HTTP 接入层，解析 S3 PutObject 请求（AWS Signature V4 认证、HTTP headers、请求体）
- 新增对象元数据管理，将 S3 对象的 key/metadata 映射到内部元数据模型
- 新增数据写入通路，将 PutObject 请求体写入底层存储引擎

## Capabilities

### New Capabilities

- `s3-putobject`：接收并处理兼容 S3 协议的 PutObject 请求，支持 AWS Signature V4 认证、标准 HTTP headers（Content-Type、Content-MD5、x-amz-meta-*），将对象数据和元数据持久化到存储引擎
- `s3-auth-v4`：实现 AWS Signature V4 签名验证，支持 Authorization header 和 query string 两种认证方式

### Modified Capabilities

（无已有能力变更）

## Product Traceability

- 所属迭代计划：不适用：本次为 Phase 1 schema 验证用的测试变更
- 关联需求文档：不适用：测试变更，无对应产品级需求文档

## Impact

- **新增代码**：S3 HTTP 接入层（C 语言，基于 libmicrohttpd 或自研 HTTP parser）、AWS Signature V4 签名验证模块、S3-to-internal 元数据映射层
- **依赖**：OpenSSL/libcrypto（HMAC-SHA256 签名计算）、HTTP 解析库
- **受影响系统**：元数据服务（新增 S3 bucket/key 到内部对象 ID 的映射）、存储引擎（接收来自 S3 接入层的写入请求）、运维工具（S3 接入层监控、请求统计）
