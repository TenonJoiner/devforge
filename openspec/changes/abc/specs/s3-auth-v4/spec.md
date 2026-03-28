## ADDED Requirements

### Requirement: AWS Signature V4 Authorization Header 认证

**追溯**：`不适用：Phase 1 schema 验证用测试变更，无对应产品级需求文档`

系统 MUST 支持通过 HTTP `Authorization` Header 进行 AWS Signature V4 签名验证。系统 SHALL 解析 Authorization Header 中的 Credential、SignedHeaders、Signature 三个组件，按照 AWS Signature V4 算法重新计算签名并与请求签名比对。

#### Scenario: Authorization Header 签名验证成功

- **WHEN** 客户端发送请求，Authorization Header 包含有效的 Credential（格式为 `access-key/date/region/s3/aws4_request`）、SignedHeaders 列表和 Signature，且签名与服务端计算结果一致
- **THEN** 认证通过，请求继续进入业务处理流程

#### Scenario: Authorization Header 格式错误

- **WHEN** 客户端发送请求，Authorization Header 不符合 `AWS4-HMAC-SHA256 Credential=...,SignedHeaders=...,Signature=...` 格式（缺少必要组件或格式畸形）
- **THEN** 系统返回 HTTP 400，错误码为 `AuthorizationHeaderMalformed`

#### Scenario: 签名不匹配

- **WHEN** 客户端发送请求，Authorization Header 格式正确但 Signature 值与服务端计算结果不一致（如请求体被篡改、Header 被修改）
- **THEN** 系统返回 HTTP 403，错误码为 `SignatureDoesNotMatch`，Message 中包含服务端用于计算签名的 Canonical Request 和 String-to-Sign 供调试

---

### Requirement: AWS Signature V4 Query String 认证

**追溯**：`不适用：Phase 1 schema 验证用测试变更，无对应产品级需求文档`

系统 MUST 支持通过 URL Query String 参数进行 AWS Signature V4 签名验证（presigned URL 方式），解析 `X-Amz-Algorithm`、`X-Amz-Credential`、`X-Amz-Date`、`X-Amz-Expires`、`X-Amz-SignedHeaders`、`X-Amz-Signature` 参数。

#### Scenario: Query String 签名验证成功

- **WHEN** 客户端使用 presigned URL 发送请求，URL 中包含完整的 V4 签名参数，签名有效且未过期
- **THEN** 认证通过，请求继续进入业务处理流程

#### Scenario: Presigned URL 已过期

- **WHEN** 客户端使用 presigned URL 发送请求，当前时间超过 `X-Amz-Date` + `X-Amz-Expires` 所确定的过期时间
- **THEN** 系统返回 HTTP 403，错误码为 `AccessDenied`，Message 中说明请求已过期

#### Scenario: Query String 缺少必要参数

- **WHEN** 客户端使用 presigned URL 发送请求，但缺少 `X-Amz-Algorithm`、`X-Amz-Credential`、`X-Amz-Signature` 中的任意一个必要参数
- **THEN** 系统返回 HTTP 400，错误码为 `AuthorizationQueryParametersError`

---

### Requirement: Canonical Request 构造

**追溯**：`不适用：Phase 1 schema 验证用测试变更，无对应产品级需求文档`

系统 MUST 按照 AWS Signature V4 规范构造 Canonical Request，包含 HTTP Method、Canonical URI（路径 URI 编码）、Canonical Query String（参数按字母序排列）、Canonical Headers（小写化 + 值去首尾空白）、Signed Headers 列表和 Payload Hash。

#### Scenario: URI 路径包含特殊字符

- **WHEN** 请求路径包含需要 URI 编码的字符（如 `PUT /my-bucket/path%20with%20spaces/file.txt`）
- **THEN** 系统按照 AWS 的 URI 编码规则（RFC 3986）构造 Canonical URI，对路径中每个段分别编码，确保签名计算结果与 AWS SDK 一致

#### Scenario: 多值 Header 的规范化

- **WHEN** 请求包含同名 Header 的多个值（如多个 `x-amz-meta-tag` 值）
- **THEN** 系统按照 AWS 规范将同名 Header 的值用逗号连接，去除值的首尾空白后参与 Canonical Headers 计算

---

### Requirement: Signing Key 派生

**追溯**：`不适用：Phase 1 schema 验证用测试变更，无对应产品级需求文档`

系统 MUST 按照 AWS Signature V4 规范，通过 HMAC-SHA256 四级派生计算 Signing Key：`HMAC(HMAC(HMAC(HMAC("AWS4" + SecretKey, Date), Region), "s3"), "aws4_request")`。

#### Scenario: Signing Key 正确派生

- **WHEN** 系统收到认证请求，Credential 中包含 date=20260328、region=us-east-1
- **THEN** 系统使用对应 access key 的 secret key，按四级 HMAC-SHA256 派生出 Signing Key，计算出的签名与 AWS SDK 使用相同 secret key 计算的签名一致

#### Scenario: Access Key 不存在

- **WHEN** 请求中的 Credential 包含系统中不存在的 access key
- **THEN** 系统返回 HTTP 403，错误码为 `InvalidAccessKeyId`

---

### Requirement: 请求时间戳验证

**追溯**：`不适用：Phase 1 schema 验证用测试变更，无对应产品级需求文档`

系统 MUST 验证请求的时间戳（通过 `x-amz-date` Header 或 `Date` Header 提供），请求时间与服务端时间的偏差 SHALL 不超过 15 分钟。

#### Scenario: 时间戳在有效范围内

- **WHEN** 请求携带 `x-amz-date` Header，其时间值与服务端当前时间的偏差在 15 分钟以内
- **THEN** 时间戳验证通过，继续进行签名验证

#### Scenario: 请求时间戳过期

- **WHEN** 请求携带 `x-amz-date` Header，其时间值与服务端当前时间的偏差超过 15 分钟
- **THEN** 系统返回 HTTP 403，错误码为 `RequestTimeTooSkewed`，Message 中包含服务端时间和请求时间供调试

#### Scenario: 缺少时间戳

- **WHEN** 请求既未携带 `x-amz-date` Header 也未携带 `Date` Header
- **THEN** 系统返回 HTTP 403，错误码为 `AccessDenied`，Message 中说明缺少时间戳信息

---

### Requirement: Payload Hash 验证

**追溯**：`不适用：Phase 1 schema 验证用测试变更，无对应产品级需求文档`

系统 MUST 验证 `x-amz-content-sha256` Header 的值。当该 Header 值为具体的 SHA256 哈希字符串时，系统 SHALL 计算请求体的 SHA256 并与之比对；当值为 `UNSIGNED-PAYLOAD` 时，系统 SHALL 跳过请求体哈希验证。

#### Scenario: Payload Hash 匹配

- **WHEN** 请求携带 `x-amz-content-sha256` Header，值为请求体的 SHA256 十六进制字符串，且与实际计算结果一致
- **THEN** Payload 验证通过，继续处理请求

#### Scenario: Payload Hash 不匹配

- **WHEN** 请求携带 `x-amz-content-sha256` Header，值为具体的 SHA256 字符串，但与请求体的实际 SHA256 计算结果不一致
- **THEN** 系统返回 HTTP 400，错误码为 `XAmzContentSHA256Mismatch`

#### Scenario: UNSIGNED-PAYLOAD 标记

- **WHEN** 请求携带 `x-amz-content-sha256: UNSIGNED-PAYLOAD`
- **THEN** 系统跳过请求体哈希验证，使用字符串 `UNSIGNED-PAYLOAD` 作为 Canonical Request 中的 payload hash 参与签名计算

#### Scenario: x-amz-content-sha256 Header 缺失

- **WHEN** 请求未携带 `x-amz-content-sha256` Header
- **THEN** 系统返回 HTTP 400，错误码为 `InvalidRequest`，Message 中说明缺少必要的 x-amz-content-sha256 Header

## MODIFIED Requirements

<!-- 无已有能力变更 -->

## REMOVED Requirements

<!-- 无废弃功能 -->

## RENAMED Requirements

<!-- 无改名 -->
