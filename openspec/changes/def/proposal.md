## Why

当前分布式存储系统仅提供内部私有 API，无法对接已有的 S3 生态工具链（如 aws-cli、s3cmd、各语言 SDK）。用户接入需要编写定制客户端，开发和运维成本高。增加 S3 兼容接口是对象存储产品化的基础前提——没有 S3 接口，就无法进入任何以 S3 为标准的应用场景。

不解决的后果：产品仅限内部使用，无法对接任何第三方工具和应用生态。

## Product Traceability

- 所属迭代计划：不适用：本变更为对象存储 S3 兼容层的首次引入，尚未纳入迭代计划
- 关联需求文档：不适用：首次构建 S3 接入层，无前置需求文档

## What Changes

- **新增** HTTP 服务器接入层（监听、连接管理、请求解析、响应构建）
- **新增** S3 协议解析模块（S3 请求路由、签名验证 V4、XML 响应序列化）
- **新增** PutObject 接口实现（单次 PUT 写入对象，支持 Content-Type、Content-Length、x-amz-meta-* 自定义元数据）
- **新增** S3 错误响应处理（标准 S3 XML 错误码：AccessDenied、NoSuchBucket、InvalidArgument 等）

## Capabilities

### New Capabilities

- `s3-http-server`: HTTP 服务器接入层，支持接收和响应 S3 REST 请求，管理连接生命周期
- `s3-auth-v4`: S3 V4 签名验证，校验请求的 Authorization 头，拒绝非法请求
- `s3-put-object`: 兼容 S3 PutObject 语义的对象写入能力，支持 Content-Type、Content-Length、x-amz-meta-* 自定义元数据，返回 ETag
- `s3-error-response`: S3 标准 XML 错误响应生成，覆盖常见错误码

### Modified Capabilities

（无，首次引入 S3 兼容层）

## Impact

- **新增模块**：s3-gateway（HTTP 服务器 + S3 协议解析 + 路由分发）
- **依赖**：需要对接底层存储引擎的对象读写接口（put/get API）
- **构建系统**：新增 s3-gateway 编译目标，可能引入 HTTP 解析库（如 http-parser/llhttp）和 XML 生成库
- **部署**：新增独立监听端口（默认 8080），需配置防火墙规则
- **测试**：可使用 aws-cli 作为 S3 兼容性验收工具
