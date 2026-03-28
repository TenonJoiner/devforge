## ADDED Requirements

### Requirement: extent 分配

**追溯**：不适用：测试变更，无对应产品级需求文档

元数据服务 SHALL 支持向指定 DNode 的指定 namespace 分配固定大小（64MB）的 extent。分配 MUST 采用两阶段提交：预留 → 确认。

#### Scenario: 正常分配 extent

- **WHEN** 元数据服务向 DNode 发送 extent 分配请求，目标 namespace 有足够可用空间
- **THEN** DNode 预留 64MB 空间并返回 `extent_handle`（含 offset、generation），元数据服务确认后 extent 状态变为已分配

#### Scenario: namespace 空间不足

- **WHEN** 元数据服务向 DNode 发送 extent 分配请求，目标 namespace 可用空间不足 64MB
- **THEN** DNode 返回错误码 `ENOSPC`，不预留任何空间

#### Scenario: 预留后未确认超时

- **WHEN** 元数据服务向 DNode 发送 extent 预留请求成功，但在 30 秒内未发送确认
- **THEN** DNode 自动释放预留的空间，该 extent 恢复为可用状态

### Requirement: extent 回收

**追溯**：不适用：测试变更，无对应产品级需求文档

元数据服务 SHALL 支持回收已分配的 extent。回收前 MUST 确认该 extent 上无活跃 I/O。

#### Scenario: 正常回收无活跃 I/O 的 extent

- **WHEN** 元数据服务向 DNode 发送 extent 回收请求，且该 extent 上无活跃 I/O
- **THEN** DNode 释放该 extent 占用的空间，返回成功，`extent_handle` 失效

#### Scenario: 回收仍有活跃 I/O 的 extent

- **WHEN** 元数据服务向 DNode 发送 extent 回收请求，但该 extent 上仍有活跃 I/O
- **THEN** DNode 返回错误码 `EBUSY`，extent 保持已分配状态

### Requirement: 全局容量视图查询

**追溯**：不适用：测试变更，无对应产品级需求文档

元数据服务 SHALL 维护所有 DNode 的容量汇总视图，MUST 通过 DNode 心跳上报实时更新。

#### Scenario: 正常心跳上报

- **WHEN** DNode 按心跳间隔（默认 10 秒）向元数据服务上报状态，包含总容量、可用容量和活跃连接数
- **THEN** 元数据服务更新该 DNode 的容量记录，全局容量视图反映最新数据

#### Scenario: DNode 心跳超时

- **WHEN** 元数据服务连续 3 个心跳周期（30 秒）未收到某 DNode 的心跳
- **THEN** 元数据服务将该 DNode 标记为 `degraded` 状态，停止向该 DNode 分配新 extent，已分配 extent 保持不变

## MODIFIED Requirements

## REMOVED Requirements

## RENAMED Requirements
