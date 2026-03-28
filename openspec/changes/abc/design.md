## Context

当前分布式存储系统仅提供私有 API 接口，无法兼容 S3 生态工具（s3cmd、rclone、AWS SDK 等）。本设计为系统新增 S3 兼容接入层，首先实现 PutObject 接口及 AWS Signature V4 认证，作为 S3 兼容的第一步。

**现状**：系统已有完整的内部元数据服务和存储引擎，支持对象的写入和管理，但仅通过私有协议访问。

**约束**：
- 语言限制为 C，运行环境为 Linux
- 需与现有元数据服务和存储引擎集成，不能侵入式修改现有核心模块
- 签名计算依赖 OpenSSL/libcrypto
- Phase 1 仅实现 PutObject，但架构需考虑后续 GetObject、DeleteObject、MultipartUpload 等接口的扩展

**利益相关方**：存储引擎团队、元数据服务团队、运维团队、外部用户（使用 S3 SDK 访问）

## Goals / Non-Goals

**Goals:**
- 新增独立的 S3 HTTP 接入层，接收标准 S3 PutObject 请求
- 实现 AWS Signature V4 签名验证（Authorization header 方式 + query string 方式）
- 将 S3 对象的 bucket/key 映射到内部元数据模型并持久化
- 将请求体数据写入底层存储引擎
- 架构上为后续 S3 接口（GetObject、DeleteObject 等）预留扩展点

**Non-Goals:**
- 不实现 PutObject 以外的 S3 接口（Phase 1 范围外）
- 不实现 S3 ACL / IAM 权限体系（使用现有鉴权映射）
- 不实现 MultipartUpload（后续 Phase）
- 不处理 HTTPS/TLS 终结（由前置 nginx/LB 负责）
- 不实现 S3 事件通知（SNS/SQS 通知机制）

## Decisions

### Decision 1: HTTP 服务框架选型

S3 接入层需要一个 HTTP 服务器处理 REST 请求。

**备选方案**：

| 维度 | 方案 A: libmicrohttpd | 方案 B: libevent (evhttp) | 方案 C: 自研 HTTP parser |
|------|----------------------|--------------------------|------------------------|
| 复杂度 | 低，API 简洁，嵌入式使用 | 中，需要理解 event loop 模型 | 高，需实现 HTTP/1.1 协议解析 |
| 性能影响 | 中等，线程池模型，适合中等并发 | 较高，事件驱动，高并发友好 | 可深度优化，但开发投入大 |
| 可维护性 | 高，成熟库，文档完善 | 高，社区活跃，广泛使用 | 低，自研代码需长期维护 |
| 与现有代码一致性 | 需引入新依赖 | 若系统已使用 libevent 则一致性好 | 完全自主可控 |
| 大对象流式处理 | 支持，通过回调分块接收 | 支持，但需手动管理 buffer | 可定制流式处理策略 |

**结论**：选择方案 A（libmicrohttpd），因为：
1. API 简洁，嵌入式使用方便，开发周期短
2. 原生支持分块数据接收回调，适合大对象上传场景
3. 线程池模型对 Phase 1 的并发需求足够
4. 成熟稳定，减少自研 HTTP 解析的 bug 风险
5. 如后续性能不足，可替换为 libevent 或自研方案，接入层内部解耦设计使替换成本可控

### Decision 2: S3 请求路由与分发架构

需要将 S3 REST 请求（基于 HTTP method + URL path + query params）路由到对应的处理函数。

**备选方案**：

| 维度 | 方案 A: 集中式 router（method + path 匹配表） | 方案 B: 分层 handler chain（类似 middleware） |
|------|---------------------------------------------|---------------------------------------------|
| 复杂度 | 低，简单的查找表 + 匹配逻辑 | 中，需设计 handler 接口和 chain 管理 |
| 性能影响 | O(n) 路由匹配，接口少时无影响 | 每层 handler 有额外函数调用开销 |
| 可维护性 | 新接口只需加一行注册 | 新接口需编写 handler 并注册到 chain |
| 可扩展性 | 接口多时匹配表变长，但仍清晰 | 天然支持认证/日志/限流等横切关注点 |

**结论**：选择方案 B（分层 handler chain），因为：
1. S3 协议中认证、日志、限流等横切关注点天然适合 middleware 模式
2. 认证（Signature V4 验证）作为独立 handler，可在请求到达业务逻辑前统一拦截
3. 后续新增 GetObject/DeleteObject 只需添加业务 handler，不影响认证/日志链路
4. 虽然 Phase 1 接口少，但 handler chain 架构为后续扩展奠定基础

### Decision 3: AWS Signature V4 认证模块设计

S3 请求需验证 AWS Signature V4 签名，涉及 HMAC-SHA256 计算和 canonical request 构造。

**备选方案**：

| 维度 | 方案 A: 内嵌认证逻辑（与请求处理耦合） | 方案 B: 独立认证模块（清晰接口） |
|------|--------------------------------------|-------------------------------|
| 复杂度 | 低，直接在处理函数中计算签名 | 中，需定义认证接口和凭证管理 |
| 性能影响 | 无差异，计算逻辑相同 | 无差异 |
| 可维护性 | 低，认证逻辑分散在各处理函数 | 高，认证逻辑集中管理 |
| 可测试性 | 低，难以独立测试认证逻辑 | 高，认证模块可独立单元测试 |

**结论**：选择方案 B（独立认证模块），因为：
1. Signature V4 计算逻辑复杂（canonical request 构造、signing key 派生、签名比对），需独立维护和测试
2. 作为 handler chain 中的认证 handler，天然解耦
3. 凭证管理（access key / secret key 的存储和查找）需要独立的存储后端，不应与业务逻辑混合
4. 后续可扩展支持 STS 临时凭证、presigned URL 等认证方式

### Decision 4: S3 bucket/key 到内部元数据的映射策略

S3 使用 bucket + key 定位对象，需映射到内部元数据模型的对象 ID。

**备选方案**：

| 维度 | 方案 A: bucket 映射为命名空间前缀 | 方案 B: bucket 映射为独立命名空间实体 |
|------|-------------------------------|-------------------------------------|
| 复杂度 | 低，key 拼接为 "bucket/key" 作为内部路径 | 中，需在元数据服务新增 bucket 概念 |
| 性能影响 | 查找时需前缀匹配，列举操作效率低 | bucket 粒度索引，列举操作高效 |
| 可维护性 | 简单但扩展性差 | 与 S3 语义对齐，后续 ListObjects 等接口实现直观 |
| 与现有代码一致性 | 兼容现有路径模型 | 需扩展元数据模型 |

**结论**：选择方案 B（独立命名空间实体），因为：
1. S3 的 bucket 有独立的语义（区域、权限、配额等），简单前缀拼接会丢失这些信息
2. 后续 ListObjects 需要按 bucket 粒度高效列举，独立实体天然支持
3. 元数据服务的扩展（新增 bucket 表/索引）是一次性工作，长期收益大于短期成本
4. 对现有元数据模型的侵入有限：新增映射表，不修改已有数据结构

### Decision 5: 数据写入通路集成

PutObject 请求体需写入底层存储引擎。

**备选方案**：

| 维度 | 方案 A: 同步写入（请求处理线程直接写） | 方案 B: 异步写入（提交到写入队列） |
|------|-------------------------------------|-------------------------------|
| 复杂度 | 低，直接调用存储引擎写接口 | 中，需管理写入队列和异步回调 |
| 性能影响 | 请求延迟 = 写入延迟，大对象时响应慢 | 可优化吞吐，但需处理异步完成通知 |
| 可维护性 | 高，逻辑直观 | 中，异步错误处理复杂 |
| 数据一致性 | 高，写完即响应，语义清晰 | 需额外机制保证写入成功再响应 |

**结论**：选择方案 A（同步写入），因为：
1. S3 PutObject 语义要求返回 200 时数据已持久化，同步写入天然满足
2. Phase 1 不追求极致吞吐，正确性优先
3. 异步模式在 PutObject 场景下需等待写入完成才能响应，实质上仍是同步等待，引入异步队列反而增加复杂度
4. 可通过流式写入（边接收边写）优化大对象延迟，无需异步队列

**覆盖写入原子性保证**：对象覆盖采用 write-aside-then-swap 策略：
1. 新数据写入到新的存储位置（不覆盖旧数据）
2. 写入完成后，原子更新元数据指向新数据
3. 旧数据延迟回收（标记删除后异步清理）
该策略确保覆盖写入期间，读取请求始终返回完整的旧数据，不会读到部分写入的新数据

## Risks / Trade-offs

1. **[libmicrohttpd 线程池并发上限]** → 通过配置合理的线程池大小（初始 64，可配置），监控线程利用率，必要时切换框架 → 残余风险：极端高并发下可能成为瓶颈，需在 Phase 2 评估

2. **[Signature V4 实现合规性]** → 严格参照 AWS 官方文档实现，编写覆盖所有边界情况的测试用例（URL 编码、多值 header、空 payload 等）。签名比对 MUST 使用常量时间比较函数（OpenSSL `CRYPTO_memcmp`）防止时序攻击 → 残余风险：AWS SDK 版本迭代可能引入新的签名行为

3. **[元数据服务 bucket 扩展侵入性]** → 新增独立的 bucket 映射表，不修改现有表结构；通过接口层隔离访问 → 残余风险：元数据服务升级时需同步维护映射表 schema

4. **[大对象内存压力]** → 采用流式处理，libmicrohttpd 回调分块接收数据并直接写入存储引擎，避免在内存中缓存完整对象 → 残余风险：极慢的客户端可能长时间占用连接和存储引擎写入会话

5. **[S3 协议兼容性覆盖度]** → Phase 1 聚焦 PutObject 核心路径，已知不兼容项（如 ACL、加密、版本控制 header）返回明确错误码 → 残余风险：部分 S3 客户端可能依赖未实现的 header 或行为

6. **[大对象 SHA256/MD5 增量计算性能]** → 对 5GB 大对象计算 SHA256（payload hash 验证）和 MD5（ETag 生成）开销显著。采用流式增量计算：在 libmicrohttpd 回调中边接收数据边更新 hash context → 残余风险：CPU 密集型计算可能影响并发处理能力，需关注 hash 计算对请求延迟的影响

## Migration Plan

1. **部署步骤**：
   - S3 接入层作为独立进程部署，监听独立端口（默认 8080）
   - 配置前置 LB/nginx 将 S3 请求（通过 Host header 或 URL path 前缀识别）转发到 S3 接入层
   - 元数据服务部署 bucket 映射表的 schema 升级（新增表，不影响已有数据）
   - 凭证管理：初期通过配置文件管理 access key / secret key 对

2. **回滚策略**：
   - S3 接入层独立部署，停止该进程即可回滚，不影响已有私有 API
   - 元数据服务的 bucket 映射表为新增表，回滚时保留即可（无数据依赖）

3. **灰度方案**：
   - 初期仅开放测试 bucket 给内部用户验证
   - 通过 LB 权重控制流量比例

## Open Questions

1. **凭证存储后端**：Phase 1 使用配置文件存储 access key / secret key 对，后续是否需要对接已有的鉴权系统？
2. **S3 接入层与元数据服务通信协议**：复用已有 RPC 框架还是使用新的通信方式？
3. **请求日志与监控**：S3 请求日志格式是否对齐 S3 server access log 格式？
4. **Bucket 创建方式**：Phase 1 不实现 CreateBucket API，但 PutObject 要求 bucket 已存在。需确定 Phase 1 的 bucket 创建途径（如管理员命令行工具、内部 API 手动创建）

## Architecture Traceability

- 关联架构文档：不适用：当前项目 docs/architecture/ 目录不存在。本变更为 S3 兼容接入层的新增模块，属于新领域首次引入，无对应的产品级架构文档

## Interface Changes

### 接口: S3 接入层 → 元数据服务（新增）

- 变更类型：新增
- 函数签名：
  ```c
  /* 创建或获取 bucket 映射 */
  int s3_meta_bucket_create(const char *bucket_name, uint64_t *bucket_id);
  int s3_meta_bucket_lookup(const char *bucket_name, uint64_t *bucket_id);

  /* 创建对象元数据映射 */
  int s3_meta_object_put(uint64_t bucket_id, const char *key,
                         const s3_object_meta_t *meta, uint64_t *object_id);
  ```
- 数据结构：
  ```c
  typedef struct {
      char     content_type[256];
      char     content_md5[33];     /* hex string */
      uint64_t content_length;
      /* x-amz-meta-* 用户自定义元数据 */
      s3_kv_pair_t user_meta[S3_MAX_USER_META];
      int          user_meta_count;
  } s3_object_meta_t;
  ```
- 兼容性：新增接口，不影响现有系统，向前兼容

### 接口: S3 接入层 → 存储引擎（新增）

- 变更类型：新增
- 函数签名：
  ```c
  /* 流式写入对象数据 */
  int s3_storage_write_begin(uint64_t object_id, s3_write_ctx_t **ctx);
  int s3_storage_write_chunk(s3_write_ctx_t *ctx, const void *data, size_t len);
  int s3_storage_write_commit(s3_write_ctx_t *ctx, char *etag_out, size_t etag_len);
  int s3_storage_write_abort(s3_write_ctx_t *ctx);
  ```
- 兼容性：新增接口，不影响现有系统，向前兼容

### 接口: S3 HTTP 外部接口（新增）

- 变更类型：新增
- 协议格式：HTTP/1.1 REST，兼容 AWS S3 PutObject API
  - `PUT /{bucket}/{key}` — 上传对象
  - 支持的请求 Header：`Authorization`、`Content-Type`、`Content-Length`、`Content-MD5`、`x-amz-content-sha256`、`x-amz-date`、`x-amz-meta-*`
  - 响应：`200 OK` + `ETag` header（对象数据的 MD5）
  - 错误响应：标准 S3 XML 错误格式（`AccessDenied`、`NoSuchBucket`、`InternalError` 等）
- 兼容性：新增外部接口，不影响已有私有 API
