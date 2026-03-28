## Context

当前分布式存储系统无 HTTP 接入层和 S3 兼容接口。本设计从零构建 S3 Gateway 模块，作为独立进程运行，接收 S3 REST 请求并转换为内部存储引擎调用。首期仅实现 PutObject 单接口，为后续扩展 GetObject、DeleteObject 等接口奠定架构基础。

约束条件：
- 语言：C（与存储引擎一致）
- 平台：Linux（epoll）
- 首期仅需支持基础 PutObject（单次 PUT，无 Multipart）
- 必须通过 aws-cli `s3api put-object` 验收

## Architecture Traceability

- 关联架构文档：不适用：S3 兼容层为首次引入的新领域，尚无对应架构文档

## Goals / Non-Goals

**Goals:**
- 实现可通过 aws-cli 验证的 S3 PutObject 接口
- 构建可扩展的 S3 Gateway 架构，后续接口可增量添加
- 支持 S3 V4 签名验证
- 支持自定义元数据（x-amz-meta-*）和 Content-Type

**Non-Goals:**
- Multipart Upload（后续变更）
- HTTPS/TLS 终止（由前端反向代理负责）
- S3 ACL 权限控制（后续变更）
- 多租户隔离
- 带宽限流和 QoS

## Decisions

### Decision 1: HTTP 解析库选型

**备选方案：**

| 维度 | llhttp (Node.js 出品) | http-parser (旧版) | 手写解析器 |
|------|----------------------|-------------------|-----------|
| 复杂度 | 低，API 简洁 | 低，API 简洁 | 高，需处理各种边界 |
| 性能 | ~2.5GB/s 解析吞吐 | ~1.5GB/s 解析吞吐 | 取决于实现质量 |
| 可维护性 | 活跃维护，Node.js 核心依赖 | 已归档停止维护 | 需自行维护 |
| 与现有代码一致性 | C API，零依赖 | C 库，零依赖 | 无外部依赖 |
| 成熟度 | 生产验证（Node.js 每天数十亿请求） | 广泛使用但已弃用 | 未验证 |

**结论**：选择 **llhttp**，因为它是 http-parser 的继任者，性能更优（~1.7x），仍在活跃维护，且是纯 C 实现零外部依赖，集成成本最低。

### Decision 2: 网络 I/O 模型

**备选方案：**

| 维度 | epoll 单线程事件循环 | epoll + 线程池 | 每连接一线程 |
|------|---------------------|---------------|-------------|
| 复杂度 | 中，需管理状态机 | 高，需线程间同步 | 低，阻塞式编程 |
| 性能（并发连接） | 10K+ 连接，单核 | 10K+ 连接，多核利用 | ~1K 连接，线程开销大 |
| 可维护性 | 中，回调/状态机模式 | 低，并发 bug 难排查 | 高，逻辑直观 |
| CPU 利用 | 单核 | 多核 | 多核但线程切换开销大 |

**结论**：选择 **epoll + 线程池**，因为分布式存储场景需处理高并发连接，且 PutObject 涉及磁盘 I/O 写入会阻塞，单线程事件循环无法充分利用多核。采用主线程 epoll 接收连接和解析请求头，工作线程池处理请求体接收和存储写入。

### Decision 3: S3 请求路由方式

**备选方案：**

| 维度 | Path-Style (`/bucket/key`) | Virtual-Hosted (`bucket.host/key`) |
|------|---------------------------|-----------------------------------|
| 复杂度 | 低，URL 路径解析即可 | 高，需 DNS 通配符 + Host 头解析 |
| 客户端兼容性 | aws-cli 默认支持（`--endpoint-url`） | 需配置 DNS，本地测试不便 |
| 与 S3 标准一致性 | AWS 已弃用新 bucket，但私有部署广泛使用 | AWS 推荐方式 |

### Decision 4: XML 响应生成方式

**备选方案：**

| 维度 | snprintf 手写拼接 | 轻量 XML 库 (mini-xml) |
|------|-------------------|----------------------|
| 复杂度 | 低，S3 XML 结构简单固定 | 中，需引入外部依赖 |
| 性能 | 极高，零分配 | 中，有解析/构建开销 |
| 可维护性 | 低（XML 多时不好管理） | 高（结构化 API） |
| 首期适用性 | 仅 Error 和 PutObject 两种响应，完全足够 | 过度设计 |

**结论**：选择 **snprintf 手写拼接**，因为首期仅需 PutObject 成功响应（无 Body，仅 ETag 在 Header）和错误响应（固定格式 XML），模板数量极少。后续接口增多时再评估引入 XML 库。

### Decision 5: 签名验证实现策略

**备选方案：**

| 维度 | 完整 V4 签名验证 | 仅校验格式 + 可配置跳过 |
|------|-----------------|----------------------|
| 安全性 | 高，完整密钥派生和签名比对 | 低，无实际安全保障 |
| 复杂度 | 高，需实现 HMAC-SHA256 链式派生 | 低 |
| 与 S3 兼容性 | 完全兼容 | 不兼容，aws-cli 仍会发签名 |

**结论**：选择 **完整 V4 签名验证**，因为 aws-cli 始终发送签名头，必须能正确验证。使用 OpenSSL 的 HMAC-SHA256 实现，避免自研加密算法。密钥存储首期使用配置文件明文存储 AccessKey/SecretKey 对。

## Concurrency Model

- **主线程**：运行 epoll 事件循环，负责 accept 新连接、读取请求头、解析 HTTP/S3 协议
- **工作线程池**：固定大小（默认 CPU 核数 × 2），负责请求体接收、签名验证、存储引擎写入、响应发送
- **连接对象**：每个连接分配一个 `s3_conn_t` 结构体，包含解析状态和请求上下文
- **线程间传递**：主线程解析完请求头后，将 `s3_conn_t` 投递到工作队列（互斥锁 + 条件变量保护的 FIFO 队列），工作线程从队列取出处理
- **锁粒度**：仅工作队列一把互斥锁，连接对象在任一时刻只归属一个线程，无共享状态竞争
- **Happens-before**：主线程写入 `s3_conn_t` 所有字段 → enqueue（释放锁）→ 工作线程 dequeue（获取锁）→ 读取字段，锁的 release/acquire 语义保证可见性

## State Machines

### 连接状态机

| 当前状态 | 事件 | 下一状态 | 动作 |
|---------|------|---------|------|
| CONN_INIT | accept 成功 | CONN_READING_HEADERS | 注册 epoll EPOLLIN，分配 recv buffer |
| CONN_READING_HEADERS | 数据到达 | CONN_READING_HEADERS | 调用 llhttp 增量解析 |
| CONN_READING_HEADERS | 头部解析完成 | CONN_DISPATCHED | 从 epoll 移除，投递到工作队列 |
| CONN_READING_HEADERS | 解析错误 | CONN_CLOSING | 发送 400 错误，关闭连接 |
| CONN_DISPATCHED | 工作线程取出 | CONN_PROCESSING | 读取 Body、签名验证、存储写入 |
| CONN_PROCESSING | 处理完成 | CONN_SENDING_RESPONSE | 构建响应，发送到客户端 |
| CONN_PROCESSING | 处理失败 | CONN_SENDING_RESPONSE | 构建错误 XML 响应 |
| CONN_SENDING_RESPONSE | 发送完成 | CONN_CLOSING | 关闭连接（首期不支持 Keep-Alive） |
| CONN_CLOSING | — | (释放) | 释放 `s3_conn_t`，关闭 fd |

## Interface Changes

### 接口: 存储引擎对象写入

- 变更类型：新增（S3 Gateway 调用存储引擎的适配接口）
- 函数签名：
  ```c
  /**
   * 写入对象到存储引擎
   * @param bucket  桶名称（以 '\0' 结尾）
   * @param key     对象键（以 '\0' 结尾）
   * @param data    对象数据指针
   * @param len     数据长度（字节）
   * @param content_type 内容类型（以 '\0' 结尾，如 "application/json"）
   * @param meta    元数据键值对数组（以 NULL 结尾）
   * @return 0 成功，负值为错误码
   */
  int storage_put_object(const char *bucket, const char *key,
                         const void *data, size_t len,
                         const char *content_type,
                         const s3_metadata_t *meta);
  ```
- 兼容性：新增接口，无兼容性问题

### 接口: S3 Gateway 配置

- 变更类型：新增
- 数据结构：
  ```c
  typedef struct {
      uint16_t    port;           /* 监听端口，默认 8080 */
      int         worker_threads; /* 工作线程数，默认 CPU*2 */
      int         max_connections; /* 最大并发连接数，默认 10000 */
      size_t      max_body_size;  /* 最大请求体，默认 5GB */
      const char *access_key;     /* S3 AccessKey */
      const char *secret_key;     /* S3 SecretKey */
  } s3_gateway_config_t;
  ```
- 兼容性：新增配置，无兼容性问题

## Risks / Trade-offs

1. **[风险] llhttp 外部依赖引入** → [缓解] llhttp 为纯 C 代码，可直接将源码编入项目（vendoring），无需动态链接 → [残余风险] 需跟踪上游安全更新

2. **[风险] snprintf 拼接 XML 在接口扩展时不可维护** → [缓解] 首期仅 2 种 XML 模板，控制在可管理范围；当 XML 模板超过 5 种时引入 XML 库 → [残余风险] 重构时需回归测试所有已有响应格式

3. **[风险] 配置文件明文存储 SecretKey** → [缓解] 配置文件权限设置为 0600，仅 owner 可读 → [残余风险] 进程内存中密钥明文存在，core dump 可能泄露

4. **[风险] 首期不支持 Keep-Alive，高频小对象写入性能受限** → [缓解] 批量场景建议客户端并发多连接；后续迭代添加 Keep-Alive → [残余风险] TCP 建连开销在高频场景下显著

5. **[风险] 单主线程 epoll 可能成为瓶颈** → [缓解] 主线程仅做头部解析（~μs 级），实际 I/O 在工作线程；若成为瓶颈可演进为 SO_REUSEPORT 多 accept 线程 → [残余风险] 短连接高并发场景下 accept 可能排队

## Migration Plan

- **部署**：S3 Gateway 作为独立进程部署，不影响现有存储引擎进程
- **配置**：新增 `s3-gateway.conf` 配置文件（端口、线程数、密钥）
- **回滚**：停止 S3 Gateway 进程即可，不影响存储引擎正常运行
- **验收**：使用 `aws s3api put-object --endpoint-url http://<host>:8080` 验证

## Open Questions

1. 存储引擎当前是否已有对象级 put/get 接口，还是需要在存储引擎侧也新增适配层？
2. 是否需要支持同一 AccessKey/SecretKey 多实例部署（无状态网关 vs 有状态）？
3. 最大单对象大小限制是多少？（首期建议 5GB，与 S3 单次 PUT 上限一致）
