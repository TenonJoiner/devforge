## ADDED Requirements

### Requirement: AWS Signature V4 签名验证

**追溯**：`不适用：首次引入 S3 兼容层，无前置需求文档`

S3 Gateway MUST 对每个请求执行 AWS Signature V4 签名验证，确保请求来自持有合法凭证的客户端且请求内容未被篡改。

#### Scenario: 签名验证通过
- **WHEN** 客户端使用正确的 AccessKey 和 SecretKey 对请求进行 V4 签名，Authorization 头包含合法的 Credential、SignedHeaders、Signature 字段
- **THEN** S3 Gateway MUST 使用相同的密钥和算法重新计算签名，与请求中的 Signature 比对一致后，允许请求继续处理

#### Scenario: AccessKey 不存在
- **WHEN** 客户端请求的 Authorization 头中 Credential 包含的 AccessKey 在系统中不存在
- **THEN** S3 Gateway MUST 返回 S3 错误响应，HTTP 状态码 403，错误码 `InvalidAccessKeyId`

#### Scenario: 签名不匹配
- **WHEN** 客户端请求的 Authorization 头中 Signature 与服务端计算结果不一致（SecretKey 错误或请求被篡改）
- **THEN** S3 Gateway MUST 返回 S3 错误响应，HTTP 状态码 403，错误码 `SignatureDoesNotMatch`

#### Scenario: 缺少 Authorization 头
- **WHEN** 客户端请求未携带 Authorization 头
- **THEN** S3 Gateway MUST 返回 S3 错误响应，HTTP 状态码 403，错误码 `AccessDenied`

### Requirement: Authorization 头格式校验

**追溯**：`不适用：首次引入 S3 兼容层，无前置需求文档`

S3 Gateway MUST 校验 Authorization 头的格式是否符合 AWS Signature V4 规范，格式为：`AWS4-HMAC-SHA256 Credential=<access-key>/<date>/<region>/s3/aws4_request, SignedHeaders=<headers>, Signature=<signature>`。

#### Scenario: Authorization 头格式正确
- **WHEN** 客户端发送的 Authorization 头符合 `AWS4-HMAC-SHA256 Credential=...` 格式，包含完整的 Credential、SignedHeaders、Signature 三个字段
- **THEN** S3 Gateway MUST 成功解析出 AccessKey、日期、区域、签名头列表和签名值，进入签名验证流程

#### Scenario: Authorization 头格式非法
- **WHEN** 客户端发送的 Authorization 头不以 `AWS4-HMAC-SHA256` 开头，或缺少 Credential/SignedHeaders/Signature 任一字段
- **THEN** S3 Gateway MUST 返回 S3 错误响应，HTTP 状态码 400，错误码 `AuthorizationHeaderMalformed`

### Requirement: 请求时间窗口校验

**追溯**：`不适用：首次引入 S3 兼容层，无前置需求文档`

S3 Gateway MUST 校验请求的时间戳，拒绝超出合理时间窗口的请求以防止重放攻击。

#### Scenario: 请求时间在有效窗口内
- **WHEN** 客户端请求携带的 `x-amz-date` 头与服务端当前时间的差值不超过 15 分钟
- **THEN** S3 Gateway MUST 接受该请求的时间戳，继续签名验证

#### Scenario: 请求时间超出有效窗口
- **WHEN** 客户端请求携带的 `x-amz-date` 头与服务端当前时间的差值超过 15 分钟
- **THEN** S3 Gateway MUST 返回 S3 错误响应，HTTP 状态码 403，错误码 `RequestTimeTooSkewed`

#### Scenario: 缺少时间戳头
- **WHEN** 客户端请求未携带 `x-amz-date` 头，也未携带 `Date` 头
- **THEN** S3 Gateway MUST 返回 S3 错误响应，HTTP 状态码 403，错误码 `AccessDenied`，Message 指明缺少日期信息

### Requirement: 凭证配置管理

**追溯**：`不适用：首次引入 S3 兼容层，无前置需求文档`

S3 Gateway MUST 从配置文件中加载 AccessKey/SecretKey 凭证对，用于签名验证。

#### Scenario: 配置文件加载成功
- **WHEN** S3 Gateway 启动时，配置文件中包含合法的 AccessKey（长度 16-128 字符）和 SecretKey（长度 1-128 字符）
- **THEN** S3 Gateway MUST 成功加载凭证并就绪处理请求

#### Scenario: 配置文件缺少凭证
- **WHEN** S3 Gateway 启动时，配置文件中未配置 AccessKey 或 SecretKey
- **THEN** S3 Gateway MUST 拒绝启动，输出明确的错误信息指明缺少哪个配置项

## MODIFIED Requirements

## REMOVED Requirements

## RENAMED Requirements
