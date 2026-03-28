## ADDED Requirements

### Requirement: NVMe-oF 远端发现

**追溯**：不适用：测试变更，无对应产品级需求文档

计算节点 SHALL 支持通过 NVMe-oF discovery 协议发现指定 DNode 上的所有可用 namespace。

#### Scenario: 正常发现远端 namespace

- **WHEN** 计算节点向 DNode 的 discovery 地址发起 NVMe-oF discovery 请求，且 DNode 上已创建 2 个 namespace
- **THEN** 计算节点获取到包含 2 个 namespace 条目的发现列表，每个条目包含 namespace ID、传输地址和端口

#### Scenario: DNode 不可达

- **WHEN** 计算节点向 DNode 的 discovery 地址发起请求，但 DNode 进程未运行或网络不可达
- **THEN** 计算节点在超时时间（默认 5 秒）内返回连接失败错误码 `ETIMEDOUT`

### Requirement: NVMe-oF 连接建立

**追溯**：不适用：测试变更，无对应产品级需求文档

计算节点 SHALL 支持根据 discovery 结果连接指定的远端 NVMe namespace，连接成功后 MUST 在本地创建对应的 NVMe 块设备。

#### Scenario: 正常连接远端 namespace

- **WHEN** 计算节点根据 discovery 结果对指定 namespace 发起 NVMe-oF connect 请求
- **THEN** 内核创建本地 NVMe 块设备（如 `/dev/nvme1n1`），该设备可正常执行读写 I/O

#### Scenario: 连接已被占用的 namespace

- **WHEN** 计算节点对一个已被其他计算节点独占连接的 namespace 发起 connect 请求
- **THEN** 连接请求返回错误码 `ECONNREFUSED`，不创建本地块设备

### Requirement: NVMe-oF 故障自动重连

**追溯**：不适用：测试变更，无对应产品级需求文档

计算节点 MUST 在 NVMe-oF 连接中断后自动尝试重连，重连期间上层 I/O 请求 SHALL 被挂起而非立即失败。

#### Scenario: 网络短暂中断后自动恢复

- **WHEN** 已建立 NVMe-oF 连接的计算节点与 DNode 之间网络中断 10 秒后恢复
- **THEN** 计算节点在网络恢复后 5 秒内自动重连成功，挂起的 I/O 请求继续完成，无 I/O 错误返回给上层

#### Scenario: 长时间中断超过重试上限

- **WHEN** 已建立 NVMe-oF 连接的计算节点与 DNode 之间网络持续中断超过重连超时时间（默认 60 秒）
- **THEN** 计算节点停止重连尝试，所有挂起的 I/O 请求返回错误码 `EIO`，本地 NVMe 块设备标记为 dead

## MODIFIED Requirements

## REMOVED Requirements

## RENAMED Requirements
