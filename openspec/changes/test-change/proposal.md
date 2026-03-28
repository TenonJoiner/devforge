## Why

当前存储系统的数据节点通过用户态存储栈访问本地 NVMe 盘，所有 I/O 请求需经过完整的软件栈处理（协议解析 → 对象映射 → 块分配 → 本地文件系统/块设备写入）。这导致单次 I/O 的软件栈延迟占比超过 60%（实测 4K 随机读平均延迟 ~120μs，其中 NVMe 硬件延迟仅 ~15μs），严重制约了 NVMe 介质的性能发挥。

参考 VAST Data 的 DNode 架构，将 NVMe 本地盘通过 NVMe-oF（NVMe over Fabrics）协议直接暴露给计算节点，可绕过数据节点的用户态存储栈，由计算节点直接发起 NVMe 命令访问远端盘。预期 4K 随机读延迟降至 ~25-30μs（接近网络 RTT + NVMe 硬件延迟），吞吐提升 3-5x。

## What Changes

- 新增 DNode 服务进程：管理本地 NVMe 盘的 NVMe-oF Target 暴露，处理命名空间（namespace）的动态创建/销毁/映射
- 新增 NVMe-oF 连接管理：计算节点侧的 NVMe-oF Initiator 连接生命周期管理（discovery、connect、disconnect、reconnect）
- 新增容量分配协议：元数据服务与 DNode 之间的容量分配/回收交互，按 extent 粒度管理 NVMe namespace 上的空间

## Capabilities

### New Capabilities

- `nvmeof-target-expose`：DNode 将本地 NVMe 盘通过 NVMe-oF Target 暴露为远程可访问的命名空间，支持动态创建和销毁
- `nvmeof-initiator-connect`：计算节点通过 NVMe-oF Initiator 发现并连接远端 NVMe 命名空间，支持故障自动重连
- `extent-allocation`：元数据服务按 extent 粒度向 DNode 分配/回收 NVMe 空间，维护全局容量视图

### Modified Capabilities

（无已有能力变更）

## 产品级追溯

- 所属迭代计划：不适用：本次为 Phase 1 schema 验证用的测试变更，不关联实际迭代计划
- 关联需求文档：不适用：测试变更，无对应产品级需求文档

## Impact

- **新增代码**：DNode 服务进程（C 语言）、NVMe-oF Target 管理模块、Initiator 连接管理库、extent 分配协议
- **依赖**：Linux 内核 NVMe-oF 子系统（nvmet/nvme-fabrics）、RDMA 或 TCP 传输层、libnvme 用户态库
- **受影响系统**：元数据服务（新增 extent 分配 RPC）、计算节点 I/O 路径（从本地块设备切换为 NVMe-oF 远端盘）、运维工具（DNode 监控、NVMe-oF 连接状态查看）
