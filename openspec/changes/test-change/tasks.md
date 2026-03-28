## 1. NVMe-oF Target 基础框架

**并行标记**：independent

- [ ] 1.1 实现 nvmet configfs 操作封装 — `src/dnode/nvmet_configfs.c` 中的 `nvmet_subsys_create()`、`nvmet_subsys_destroy()`
  - [ ] 1.1.1 RED：编写失败测试 — `tests/dnode/test_nvmet_configfs.c::test_subsys_create_success` — 验证调用 `nvmet_subsys_create()` 后 configfs 路径存在
    - mock 说明：mock configfs 文件系统操作（外部边界：内核 configfs），因为测试环境无 root 权限和 nvmet 内核模块
  - [ ] 1.1.2 GREEN：最小实现通过测试 — `src/dnode/nvmet_configfs.c`
  - [ ] 1.1.3 REFACTOR：重构简化
- [ ] 1.2 实现 namespace 创建 — `src/dnode/namespace_mgr.c` 中的 `ns_create()`，对应 spec `nvmeof-target-expose::namespace 创建`
  - [ ] 1.2.1 RED：编写失败测试 — `tests/dnode/test_namespace_mgr.c::test_ns_create_success` — 验证正常创建 namespace 返回成功；`test_ns_create_device_not_found` — 验证设备不存在时返回 ENODEV
  - [ ] 1.2.2 GREEN：最小实现通过测试 — `src/dnode/namespace_mgr.c`
  - [ ] 1.2.3 REFACTOR：重构简化
- [ ] 1.3 实现 namespace 销毁 — `src/dnode/namespace_mgr.c` 中的 `ns_destroy()`，对应 spec `nvmeof-target-expose::namespace 销毁`
  - [ ] 1.3.1 RED：编写失败测试 — `tests/dnode/test_namespace_mgr.c::test_ns_destroy_success` — 验证无连接时正常销毁；`test_ns_destroy_busy` — 验证有活跃连接时返回 EBUSY
  - [ ] 1.3.2 GREEN：最小实现通过测试 — `src/dnode/namespace_mgr.c`
  - [ ] 1.3.3 REFACTOR：重构简化

## 2. NVMe-oF Target 传输层配置

**并行标记**：depends-on:1.1（依赖 nvmet configfs 封装）

- [ ] 2.1 实现传输层配置解析与初始化 — `src/dnode/transport_cfg.c` 中的 `transport_init()`，对应 spec `nvmeof-target-expose::传输层配置`
  - [ ] 2.1.1 RED：编写失败测试 — `tests/dnode/test_transport_cfg.c::test_rdma_init_success` — 验证 RDMA 配置正常初始化；`test_tcp_init_success` — 验证 TCP 配置正常初始化；`test_rdma_module_missing` — 验证 RDMA 模块缺失时启动失败并报错
    - mock 说明：mock 内核模块检测接口（外部边界：`/sys/module/` 文件系统），因为测试环境可能无 RDMA 内核模块
  - [ ] 2.1.2 GREEN：最小实现通过测试 — `src/dnode/transport_cfg.c`
  - [ ] 2.1.3 REFACTOR：重构简化

## 3. NVMe-oF Initiator 连接管理

**并行标记**：independent

- [ ] 3.1 实现远端 discovery — `src/initiator/discovery.c` 中的 `nvmeof_discover()`，对应 spec `nvmeof-initiator-connect::远端发现`
  - [ ] 3.1.1 RED：编写失败测试 — `tests/initiator/test_discovery.c::test_discover_success` — 验证正常发现返回 namespace 列表；`test_discover_timeout` — 验证 DNode 不可达时 5 秒超时返回 ETIMEDOUT
    - mock 说明：mock NVMe-oF discovery 网络交互（外部边界：远端 DNode 的 NVMe-oF discovery 服务），因为测试环境无真实 NVMe-oF Target
  - [ ] 3.1.2 GREEN：最小实现通过测试 — `src/initiator/discovery.c`
  - [ ] 3.1.3 REFACTOR：重构简化
- [ ] 3.2 实现连接建立 — `src/initiator/connector.c` 中的 `nvmeof_connect()`，对应 spec `nvmeof-initiator-connect::连接建立`
  - [ ] 3.2.1 RED：编写失败测试 — `tests/initiator/test_connector.c::test_connect_success` — 验证连接成功后本地块设备可用；`test_connect_refused` — 验证独占 namespace 被拒绝返回 ECONNREFUSED
    - mock 说明：mock NVMe-oF connect 系统调用（外部边界：内核 NVMe-oF initiator 子系统），因为测试环境无法创建真实 NVMe 块设备
  - [ ] 3.2.2 GREEN：最小实现通过测试 — `src/initiator/connector.c`
  - [ ] 3.2.3 REFACTOR：重构简化
- [ ] 3.3 实现故障自动重连 — `src/initiator/reconnect.c` 中的 `nvmeof_reconnect_handler()`，对应 spec `nvmeof-initiator-connect::故障自动重连`
  - [ ] 3.3.1 RED：编写失败测试 — `tests/initiator/test_reconnect.c::test_reconnect_short_outage` — 验证 10 秒中断后自动恢复；`test_reconnect_timeout_exceeded` — 验证超过 60 秒后 I/O 返回 EIO
    - mock 说明：mock 网络连接状态和时间推进（外部边界：网络层），通过模拟连接断开/恢复事件驱动重连状态机
  - [ ] 3.3.2 GREEN：最小实现通过测试 — `src/initiator/reconnect.c`
  - [ ] 3.3.3 REFACTOR：重构简化

## 4. Extent 分配协议

**并行标记**：independent

- [ ] 4.1 实现 extent 分配（两阶段提交）— `src/extent/allocator.c` 中的 `extent_alloc_reserve()` 和 `extent_alloc_commit()`，对应 spec `extent-allocation::extent 分配`
  - [ ] 4.1.1 RED：编写失败测试 — `tests/extent/test_allocator.c::test_alloc_success` — 验证预留+确认后返回有效 handle；`test_alloc_no_space` — 验证空间不足返回 ENOSPC；`test_alloc_reserve_timeout` — 验证预留 30 秒未确认自动释放
  - [ ] 4.1.2 GREEN：最小实现通过测试 — `src/extent/allocator.c`
  - [ ] 4.1.3 REFACTOR：重构简化
- [ ] 4.2 实现 extent 回收 — `src/extent/allocator.c` 中的 `extent_free()`，对应 spec `extent-allocation::extent 回收`
  - [ ] 4.2.1 RED：编写失败测试 — `tests/extent/test_allocator.c::test_free_success` — 验证无活跃 I/O 时回收成功；`test_free_busy` — 验证有活跃 I/O 时返回 EBUSY
  - [ ] 4.2.2 GREEN：最小实现通过测试 — `src/extent/allocator.c`
  - [ ] 4.2.3 REFACTOR：重构简化

## 5. DNode 心跳与容量视图

**并行标记**：independent

- [ ] 5.1 实现 DNode 心跳上报 — `src/dnode/heartbeat.c` 中的 `dnode_heartbeat_send()`，对应 spec `extent-allocation::全局容量视图查询`
  - [ ] 5.1.1 RED：编写失败测试 — `tests/dnode/test_heartbeat.c::test_heartbeat_send_success` — 验证心跳包含正确的容量和连接数信息
    - mock 说明：mock 元数据服务 RPC 端点（外部边界：远端元数据服务），心跳接收方为外部服务
  - [ ] 5.1.2 GREEN：最小实现通过测试 — `src/dnode/heartbeat.c`
  - [ ] 5.1.3 REFACTOR：重构简化
- [ ] 5.2 实现心跳超时检测 — `src/metadata/dnode_monitor.c` 中的 `dnode_check_heartbeat()`，对应 spec `extent-allocation::全局容量视图查询` 中心跳超时 Scenario
  - [ ] 5.2.1 RED：编写失败测试 — `tests/metadata/test_dnode_monitor.c::test_heartbeat_normal` — 验证正常心跳更新容量记录；`test_heartbeat_timeout` — 验证连续 3 次超时后标记 degraded
    - mock 说明：mock 时间源（外部边界：系统时钟），通过注入时间推进模拟心跳超时
  - [ ] 5.2.2 GREEN：最小实现通过测试 — `src/metadata/dnode_monitor.c`
  - [ ] 5.2.3 REFACTOR：重构简化

## 6. DNode 服务进程集成

**并行标记**：depends-on:1.2, depends-on:1.3, depends-on:2.1, depends-on:5.1

- [ ] 6.1 实现 DNode 主进程 — `src/dnode/dnode_main.c` 中的 `main()` 和 `dnode_init()`，串联配置加载、nvmet 初始化、心跳启动
  - [ ] 6.1.1 RED：编写失败测试 — `tests/dnode/test_dnode_main.c::test_dnode_init_success` — 验证初始化流程正确串联各模块；`test_dnode_init_config_missing` — 验证配置文件缺失时报错退出
  - [ ] 6.1.2 GREEN：最小实现通过测试 — `src/dnode/dnode_main.c`
  - [ ] 6.1.3 REFACTOR：重构简化
