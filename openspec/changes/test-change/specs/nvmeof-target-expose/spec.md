## ADDED Requirements

### Requirement: NVMe namespace 创建

**追溯**：不适用：测试变更，无对应产品级需求文档

DNode SHALL 支持通过管理接口在指定 NVMe 盘上创建 NVMe-oF namespace，创建成功后该 namespace MUST 对远端 Initiator 可发现、可连接。

#### Scenario: 正常创建 namespace

- **WHEN** 元数据服务向 DNode 发送 namespace 创建请求，指定 NVMe 设备路径（如 `/dev/nvme0n1`）和 namespace ID
- **THEN** DNode 在内核 nvmet 子系统中创建对应的 namespace 并返回成功，远端 Initiator 执行 discovery 后 MUST 能发现该 namespace

#### Scenario: 指定的 NVMe 设备不存在

- **WHEN** 元数据服务向 DNode 发送 namespace 创建请求，指定的 NVMe 设备路径不存在
- **THEN** DNode 返回错误码 `ENODEV`，不创建任何 namespace

#### Scenario: namespace ID 冲突

- **WHEN** 元数据服务向 DNode 发送 namespace 创建请求，指定的 namespace ID 已被占用
- **THEN** DNode 返回错误码 `EEXIST`，已有 namespace 不受影响

### Requirement: NVMe namespace 销毁

**追溯**：不适用：测试变更，无对应产品级需求文档

DNode SHALL 支持销毁已创建的 NVMe-oF namespace。销毁前 MUST 确保该 namespace 上无活跃 I/O 连接。

#### Scenario: 正常销毁无连接的 namespace

- **WHEN** 元数据服务向 DNode 发送 namespace 销毁请求，且该 namespace 上无活跃的 Initiator 连接
- **THEN** DNode 从 nvmet 子系统中移除该 namespace 并返回成功，远端 Initiator 执行 discovery 后 MUST 不再发现该 namespace

#### Scenario: 销毁仍有活跃连接的 namespace

- **WHEN** 元数据服务向 DNode 发送 namespace 销毁请求，但该 namespace 上仍有 1 个或多个活跃的 Initiator 连接
- **THEN** DNode 返回错误码 `EBUSY`，namespace 保持不变

### Requirement: NVMe-oF Target 传输层配置

**追溯**：不适用：测试变更，无对应产品级需求文档

DNode SHALL 支持通过配置文件指定 NVMe-oF Target 的传输层类型。MUST 支持 RDMA 和 TCP 两种传输协议。

#### Scenario: 配置 RDMA 传输

- **WHEN** DNode 启动时配置文件指定传输层为 RDMA，且系统已加载 RDMA 内核模块
- **THEN** DNode 创建的 NVMe-oF Target 监听在 RDMA 端口上，Initiator 可通过 RDMA 传输连接

#### Scenario: 配置 TCP 传输

- **WHEN** DNode 启动时配置文件指定传输层为 TCP
- **THEN** DNode 创建的 NVMe-oF Target 监听在指定 TCP 端口（默认 4420）上，Initiator 可通过 TCP 传输连接

#### Scenario: 配置 RDMA 但内核模块未加载

- **WHEN** DNode 启动时配置文件指定传输层为 RDMA，但系统未加载 RDMA 内核模块
- **THEN** DNode 启动失败，日志输出错误信息明确指出 RDMA 模块缺失，进程以非零退出码退出

## MODIFIED Requirements

## REMOVED Requirements

## RENAMED Requirements
