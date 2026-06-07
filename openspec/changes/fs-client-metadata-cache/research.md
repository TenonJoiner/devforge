# Research

<!-- 特性级研究文档：客户端元数据缓存子系统标杆分析 + 关键决策维度对比 -->
<!-- 输入 design 阶段，提供素材而非决策 -->

## 1. 背景与目标

**问题与目标**：

分布式文件系统客户端在执行 `open/stat/readdir/getattr` 等 POSIX 操作时，需要频繁向元数据服务器（MDS）请求 inode 属性、目录项、权限信息。典型分布式文件系统中元数据请求占总 RPC 的 60-80%，单次 MDS 往返延迟 1-5ms；在小文件密集型工作负载（编译、日志分析、AI 训练数据集遍历）下，元数据延迟主导端到端性能，编译时间被拉长 2-3 倍，IOPS 无法充分利用。MDS 单点处理能力上限约 10-20 万 OPS，是横向扩展的关键瓶颈。

本特性目标是在客户端引入元数据缓存子系统，覆盖 4 个 Capabilities：`metadata-cache-layer`（缓存 inode 属性、目录项、权限）、`cache-consistency`（缓存一致性协议）、`cache-eviction-policy`（LRU/LFU 混合 + 容量/TTL 双约束）、`prefetch-optimization`（批量查询与预取）。性能目标量化为：缓存命中时元数据延迟降低 50-80%，缓存命中率 70-90%，客户端内存预算 100MB-1GB（取决于配置），MDS 负载降低 60-80%。

设计上需要重点权衡的方面：一致性强度（强一致 POSIX vs close-to-open 弱一致 vs TTL 弱一致）、服务端状态成本（无状态 vs 持有者跟踪 vs 锁状态机）、撤销机制（超时被动 vs 反向通道主动）、批量化粒度（语法合并 vs 语义合并 vs 隐式批量）、预取启发式（自适应 vs 异步线程窗口 vs 服务端推送）。

**核心约束**（生成期确认）：

- **一致性窗口** = close-to-open（弱一致），跨客户端可见性允许会话边界刷新
- **客户端规模** < 百级，单集群活跃客户端数量上限可控
- **网络拓扑** = 内网（RTT < 10ms），反向通道可达性高、低延迟摊销空间小

**标杆选择**：

选择 3 个标杆，覆盖一致性强度光谱的两端与中间，强调互补性而非穷举：

- **NFSv4**：代表 **timeout + 可选 delegation 弱一致主流路线**。POSIX 兼容文件系统在工业界的事实标准之一，CTO 语义匹配本特性已确认的弱一致约束，服务端默认无状态使运维代价最低，是该范式的典型工业实现。
- **CephFS**：代表 **capability bits 强一致 + 反向 revoke 细粒度路线**。同范式中存在 AFS/Coda 等更早实现，但 CephFS 提供活跃维护的现代生产级实现且源码可读性高，cap bits 把整 inode 锁切分到 8 类 14 比特的精细度是该范式的典型样本，便于学习强一致路径的状态成本与协议复杂度。
- **Lustre**：代表 **DLM 多模式分布式锁 + intent RPC 高并发路线**。HPC 场景元数据性能优化的代表，LDLM ibits 锁与 intent 合并 RPC 是该范式的典型工业实现，statahead 异步预取是预取启发式的工业级样本，可与 NFSv4 的"启发式 + 自适应反馈"形成对比。

## 2. 标杆方案分析

### 2.1 NFSv4

**方案全景**：

NFSv4 客户端元数据缓存采用**「timeout 弱一致兜底 + delegation 可选升级 + COMPOUND 摊销」三层叠加**的设计哲学。底层用 attribute timeout（acregmin/acregmax 等四参数）+ close-to-open（CTO）语义提供"够用但不严格"的弱一致基线，让绝大多数 POSIX 应用在无服务端状态前提下仍能享受缓存收益；当工作负载具备低共享特征（read 多 / 单写者）时，服务端可在 OPEN 响应中**主动颁发 delegation**，将访问语义从"超时重验证"升级为"独占代理"，客户端持 delegation 期间可零 RPC 处理 GETATTR/LOOKUP，直到 CB_RECALL 反向通道触发回收。所有元数据 RPC 都通过 COMPOUND 把 PUTFH/LOOKUP/GETATTR/ACCESS/READDIR 等多个 op 打包进一次 RTT，配合 READDIR 的 attribute bitmap（即 READDIRPLUS 语义）实现"目录遍历 + 子项属性预取"的批量摊销。

三层不是互斥分支而是**条件叠加**：默认所有客户端都享受 timeout + COMPOUND；具备授权条件的 inode 额外升级到 delegation；CB_RECALL 失败或冲突写者出现时优雅降级回 timeout。设计目标是**在协议简单性与一致性强度之间留出可调节空间**，运维代价极低（无需服务端跟踪锁/cap 持有者集合）。

**整体架构**：

```
┌──────────────────────────────────────────────┐
│  VFS Layer (dentry / inode cache)            │
│  - lookup / getattr / readdir 入口           │
├──────────────────────────────────────────────┤
│  NFS Client Cache Layer                      │
│  ├─ Attribute Cache                          │
│  │  ├─ nfs_inode.attrtimeo (动态退避)        │
│  │  ├─ acregmin/acregmax (3s / 60s 默认)     │
│  │  ├─ acdirmin/acdirmax (30s / 60s 默认)    │
│  │  └─ CHANGE attribute 比对（递增计数器）   │
│  ├─ Dentry Cache (复用 VFS dcache)           │
│  │  └─ d_revalidate → nfs_lookup_revalidate  │
│  └─ Delegation Manager                       │
│     ├─ READ / WRITE delegation 状态机        │
│     ├─ CB_RECALL handler（反向通道）         │
│     └─ DELEGRETURN 主动归还                  │
├──────────────────────────────────────────────┤
│  COMPOUND RPC Layer                          │
│  ├─ op 序列打包：PUTFH+LOOKUP+GETATTR        │
│  ├─ READDIR with attr bitmap (READDIRPLUS)   │
│  └─ Sessions (NFSv4.1) / Backchannel         │
├──────────────────────────────────────────────┤
│  RPC / XDR / Transport (TCP / RDMA)          │
└──────────────────────────────────────────────┘
                    ↓ NFSv4 Protocol
              ┌─────────────────┐
              │   NFS Server    │
              │   (state-aware: │
              │    lease/deleg) │
              └─────────────────┘
```

**核心机制**：

#### 机制 1：Attribute Cache + Close-to-Open 一致性

**原理**：观察到大多数 POSIX 应用的元数据访问遵循"打开-读写-关闭"的会话模式，跨会话的并发共享访问占比 < 5%（参见 NFSv4 协议设计论文 USENIX 2000）。因此放弃强一致约束，改为**会话边界的"刷新-回写"协议**：close 时强制 flush 写、open 时强制 GETATTR 验证 CHANGE 属性，会话内部允许任意缓存。这把"一致性义务"从"每次访问"摊销到"每次会话"，省下 90%+ 的中间访问 RPC。

**设计**：
- `nfs_inode.attrtimeo` 动态退避：每次 GETATTR 发现属性未变（CHANGE 相同），timeout 翻倍到 acregmax；一旦命中变更立即重置回 acregmin。这种自适应退避让"长期稳定"的文件 GETATTR 频率自然衰减，"频繁变化"的文件保持高频校验
- `nfs_revalidate_inode()` 是核心校验入口，比对 jiffies + attrtimeo 决定是否发起 GETATTR；命中本地缓存直接返回，未命中则发 RPC
- CHANGE 属性是 NFSv4 引入的**单调递增 64-bit 计数器**（替代 NFSv3 的 ctime+mtime 二元组），任何元数据/数据变更都会推进 CHANGE，客户���只需比对前后两次 CHANGE 即可判断是否失效——比 NFSv3 的双时间戳比对节省了"如何处理时钟回退"的复杂度
- 目录单独有 acdirmin/acdirmax（默认 30s/60s，比文件长 10 倍），因为目录变更频率低且 readdir 代价高（一次完整 readdir 可能跨多个 RPC 分页）
- close 时通过 `nfs_file_flush` 触发 dirty 数据回写并同步刷新 attribute；open 时强制 GETATTR 比对 CHANGE，命中则保留 dentry/page cache，否则 invalidate 整个 inode 的缓存数据

**取舍**：
- ✅ 性能：典型工作负载下 GETATTR 节省 80-95%（重复 stat 同一文件场景），属性命中延迟从 1-5ms RPC 降至 < 1μs 内存查找
- ✅ 协议简单：服务端无需跟踪客户端缓存状态，水平扩展无负担
- ❌ 一致性窗口：2 个客户端之间的 stale 窗口最坏可达 acregmax（默认 60s），不适合实时协作（如多人编辑同一日志）
- ❌ 后端依赖：CHANGE 属性精度依赖底层文件系统，ext3 等只到秒级时同一秒内的二次写无法被检测到（NFSv4.1 的 change_attr_type 协商规避）

#### 机制 2：Delegation 升级 + CB_RECALL 反向回收

**原理**：timeout 兜底意味着即使没有任何并发写者，客户端依然要每隔 60s 发一次 GETATTR——这对"独占访问 / 单写者"场景是浪费。Delegation 的核心思想是**让服务端在 OPEN 时就承诺"这段时间没人会来打扰你"**，客户端凭此承诺可在本地处理所有 GETATTR/OPEN/READ，省下定期重验证。一旦承诺被打破（其他客户端冲突 OPEN），服务端通过反向通道发起 CB_RECALL，客户端必须在 lease 时间（默认 90s）内归还。本质是**乐观锁的协议化**：默认乐观，冲突时悲观回退。

**设计**：
- OPEN 响应 `OPEN_DELEGATE_READ` / `OPEN_DELEGATE_WRITE` / `OPEN_DELEGATE_NONE` 三态，服务端按"是否存在冲突 share"决定是否颁发——无任何并发持有者时颁发 WRITE deleg，仅有 READ 持有者时可向新 reader 颁发 READ deleg
- `nfs_delegation` 结构挂在 inode 上，记录 stateid、type、cred；持 delegation 期间 `nfs_have_delegation()` 检查命中即跳过 GETATTR，OPEN/CLOSE 也仅在本地完成不发 RPC
- 反向通道（NFSv4.0 独立 callback 连接 / NFSv4.1 backchannel 复用 session）传输 CB_RECALL，handler 触发 `nfs_inode_return_delegation()`，先 flush 脏数据再 DELEGRETURN
- Lease 续约通过任何 RPC 隐式完成（NFSv4.1 SEQUENCE op），客户端无 RPC 静默时通过 RENEW 显式续约；lease 超时（默认 90s）后服务端单方面回收所有 delegation/state
- 写 delegation 进一步允许客户端**本地颁发字节范围锁**给应用，无需 LOCK RPC，是元数据 + 数据的联合优化
- delegation 与 attribute cache 是叠加关系：持 deleg 时 attrtimeo 实际上无限大；deleg 撤销后立即降级回 timeout ��式，acregmin 重置生效

**取舍**：
- ✅ 极端性能：独占访问场景 GETATTR/OPEN/CLOSE 的 RPC 完全消除，热文件 stat 性能与本地文件系统持平（< 100ns）
- ✅ 一致性升级：持 delegation 期间获得"强一致"语义（服务端保证无冲突），无 stale 窗口
- ❌ 反向通道脆弱：NAT/防火墙穿透困难，CB_RECALL 不可达时冲突侧 OPEN 必须 hang 至 lease 超时（90s）才能强制回收，对方应用感受 90s 卡顿
- ❌ 服务端状态成本：必须跟踪每个 delegation 的持有者 + lease，在数百万级活跃 inode + 万级客户端规模下，状态表内存与续约心跳成本不可忽略

#### 机制 3：COMPOUND RPC + READDIRPLUS 摊销

**原理**：NFSv3 的"一个 op 一个 RPC"在元数据密集场景代价巨大——一次 `path/to/file` 的 lookup 需要 N 次 LOOKUP RPC（N = 路径深度）+ 1 次 GETATTR，每次往返都吃 RTT。COMPOUND 把多个 op 串成单个 RPC 请求/响应，**用一次网络往返完成"鉴权 + 路径遍历 + 属性获取"全流程**。READDIR 进一步把"目录列表 + 子项属性"合并为一次响应，避免传统 readdir 后还要对每个子项逐个 stat（N+1 problem）。

**设计**：
- COMPOUND 是 NFSv4 唯一的 RPC 入口，op 序列共享同一 current filehandle（CFH）状态，op 间通过 PUTFH/SAVEFH/RESTOREFH 切换 CFH，类似栈机器的隐式参数传递
- 典型 lookup 序列：`PUTROOTFH → LOOKUP(a) → LOOKUP(b) → LOOKUP(c) → GETFH → GETATTR`，6 个 op 一次 RTT
- READDIR 携带 `attr_request` bitmap，服务端在返回目录项时同时填入每项的所请求属性子集，客户端预填充 attribute cache + dentry cache（即 READDIRPLUS 语义，NFSv4 通过 bitmap 自然表达，无需独立 op）
- `nfs_use_readdirplus()` 启发式判断是否需要预取：检测到 readdir 后立刻有大量 stat 调用时启用，避免在纯遍历（如 `ls` 不带 -l`）场景浪费带宽——这是个**自适应反馈环**，错判后下次自动调整
- READDIR cookie + verifier 保证多次分页调用的一致性，verifier 失效时客户端必须从头重读（目录已变更）
- COMPOUND 与 delegation 也有协同：持 deleg 时多个本地 OPEN/CLOSE 不需打包，只有跨边界的 RPC 才走 COMPOUND，避免无效拼接

**取舍**：
- ✅ RTT 摊销：5 层路径 lookup 从 NFSv3 的 5 次 RTT 降到 1 次，10ms RTT 网络下端到端从 50ms 降到 10ms（5× 提升）
- ✅ readdir + stat 联合优化：1000 子项目录的 `ls -l` 从 NFSv3 的 1001 次 RTT 降到 ~10 次（按 8KB 分页），收益 100×
- ❌ 全或无失败语义：COMPOUND 中任一 op 失败则后续 op 全部 NOOP，错误诊断需逐 op 解析 status 数组，调试复杂度高于单 op RPC
- ❌ 启发式误判成本：`nfs_use_readdirplus` 启用后若应用实际不 stat，则白白多传 N × 200B 属性数据，大目录下浪费 10-100KB 带宽

**交互流程**（CB_RECALL 撤销流程）：

```
Client A (deleg)        NFS Server          Client B (新冲突)
     │                      │                      │
     │←──[OPEN ok +─────────│                      │
     │   READ delegation]   │                      │
     │                      │                      │
     │ (持 delegation,      │                      │
     │  本地处理 GETATTR)   │                      │
     │                      │                      │
     │                      │←──[OPEN write]───────│
     │                      │                      │
     │                      │ 发现冲突，需要回收 A │
     │                      │                      │
     │←──[CB_RECALL]────────│ (反向通道)           │
     │                      │                      │
     │ flush dirty,         │                      │
     │ invalidate cache     │                      │
     │                      │                      │
     │──[DELEGRETURN]──────→│                      │
     │                      │                      │
     │                      │──[OPEN ok,──────────→│
     │                      │   no delegation]     │
     │                      │                      │
     │ (回退 timeout 模式)  │ (B 走 timeout 模式)  │
     │                      │                      │
     │ ─ ─ 失败路径 ─ ─     │                      │
     │ × CB_RECALL 不可达   │                      │
     │   (NAT/防火墙)       │                      │
     │                      │ 等待 lease 超时(90s) │
     │                      │ 强制回收 A 的 deleg  │
     │                      │──[B 的 OPEN 响应]───→│
```

**适用场景与已知坑点**：

适用工作负载是弱共享或独占访问的 POSIX 应用（编译、构建、家目录、备份、容器镜像分发），可接受秒级到分钟级的跨客户端可见性延迟。完全不适合需要"写后立即被其他客户端读到"的实时协作场景（如分布式数据库 WAL、协同编辑），那类场景应选择 callback/cap 或 DLM 范式。NFSv4 在数百级客户端规模下运维代价最低，因为服务端默认无状态，水平扩展时不需要协调缓存失效广播。

最关键的两个坑：
1. **CHANGE 属性后端精度退化**：当 NFS 服务端 export 的底层文件系统是 ext3（mtime 秒级精度）时，NFSv4.0 的 CHANGE 属性退化为基于 ctime+mtime 的合成值，**同一秒内的二次写无法被客户端感知**，导致 stale cache 命中。NFSv4.1 引入 `change_attr_type` 协商（FSID 级声明 MONOTONIC_INCR / VERSION_COUNTER 等类型）允许客户端按精度选择重验证策略，但需要服务端 ≥ Linux 4.20 才支持。生产环境应强制使用 ext4/xfs 等纳秒精度后端。
2. **CB_RECALL 反向通道在 NAT/防火墙环境下不可达**：NFSv4.0 的独立 callback 连接需要服务端能反向连接客户端的随机端口，云环境/容器网络下经常被 NAT 阻断。结果是服务端无法回收 delegation，冲突侧的 OPEN 被迫 hang 至 lease 超时（默认 90s）才能强制接管，对方应用观察到长达 1 分半钟的卡顿。NFSv4.1 通过 backchannel 复用客户端发起的 session 连接彻底解决，因此**穿越防火墙部署强烈建议禁用 NFSv4.0 或仅启用 NFSv4.1+**。

### 2.2 CephFS

**方案全景**：

CephFS 客户端元数据缓存采用**「细粒度 capability bits 强一致主线 + MDS 主动 revoke 反向回调 + dentry lease 弱一致补充 + MDCache LRU 容量协同」**的四层叠加设计。Capability（简称 cap）是 CephFS 的元一致性原语：MDS 把每个 inode 的访问权限切成 8 类 14 个比特（Auth/Link/XATTR/File 四组，每组各有 shared/exclusive 两级语义），客户端必须**持有对应位**才能本地缓存或修改相应字段，缓存有效期严格等于 cap 持有期——不是 NFSv4 的 timeout 估算，而是协议级强约束。MDS 维护全局 cap 目录，颁发时根据现有持有者集合自动选择共享或独占模式；当冲突请求到达时，MDS 通过持续连接的 mds session 反向发起 revoke 消息，客户端必须 flush + drop 后回 ACK，整个链路是事务性而非超时性的。在此强一致主线之上，dentry 维度叠加一层轻量 **lease**（秒级 TTL，类似 NFSv4 delegation 但不强保证），用于命中率最高、撤销代价最低的目录项，避免对每个 lookup 都走 cap 协商。最后一层是 **MDCache LRU**：客户端有总量上限（默认 16k inode），逼近上限时主动 trim 冷条目并交还 cap，与 MDS 的 cap 配额（mds_cache_memory_limit）相互协同。

四层不是独立选项而是**协议级嵌套**：cap 决定语义强度（强一致），revoke 决定撤销方式（主动 vs 超时），lease 决定 dentry 复用粒度（弱一致快速通道），LRU 决定容量水位（push back 压力）。设计目标是**在保证 POSIX 强一致语义的前提下，让多客户端并发场景下的元数据缓存命中率最大化**，代价是 MDS 必须维护精确的 cap 持有者状态（per-client per-inode），状态成本远高于 NFSv4 的"无状态默认 + 可选 delegation"。

**整体架构**：

```
┌─────────────────────────────────────────────────┐
│  VFS / FUSE                                     │
│  - lookup / open / getattr / readdir 入口       │
├─────────────────────────────────────────────────┤
│  Client::MDCache                                │
│  ├─ Inode (xlist 挂入 LRU)                      │
│  │  ├─ caps map<mds_rank, Cap>                  │
│  │  └─ cached_attrs (size/mtime/mode/...)       │
│  ├─ Dentry                                      │
│  │  └─ lease (duration / seq / mds)             │
│  └─ LRU 容量管理 (client_cache_size 默认 16k)   │
├─────────────────────────────────────────────────┤
│  Capability Manager                             │
│  ├─ cap bits 跟踪：issued / wanted / pending    │
│  ├─ Auth (As/Ax) Link (Ls/Lx)                   │
│  ├─ XATTR (Xs/Xx) File (Fs/Fx/Fc/Fr/Fw/Fb/Fa/Fl)│
│  └─ revoke handler / flush dirty caps           │
├─────────────────────────────────────────────────┤
│  MetaSession / MDS Client                       │
│  ├─ 长连接 + 心跳 (mds_session_timeout 60s)     │
│  ├─ MClientCaps / MClientLease 消息             │
│  └─ trim_caps / renewcaps                       │
└─────────────────────────────────────────────────┘
              ↓ Ceph MDS Protocol (TCP / msgr2)
        ┌─────────────────────────────────────┐
        │  Metadata Server (MDS)              │
        │  - 全局 cap registry                │
        │  - 主动 revoke / lease 颁发         │
        └─────────────────────────────────────┘
```

**核心机制**：

#### 机制 1：Capability bits 细粒度强一致

**原理**：观察到不同元数据字段的访问模式高度异构——`mode/uid/gid` 几乎只读、`size/mtime` 写者频繁、`xattr` 极少访问、`file content` 需要严格的读写互斥。把整 inode 当作一把锁要么粒度太粗（任何字段冲突就要互踢缓存），要么协议太复杂（NFSv4 的 share reservation 就是反例）。CephFS 的解法是**按字段族切分锁权**：8 类语义（Auth/Link/XATTR/File 各 shared/exclusive）+ File 内部再细分 cache/buffer/lazy 等读写位，让多客户端在不同维度上完全无冲突地共享缓存。本质是 Lustre ibits 锁思路在 POSIX 文件系统语义上的精炼——但 cap 不是通用锁，而是**面向缓存能力的命名权限位**，语义比 ibits 更贴合应用调用。

**设计**：
- 每个 `Inode::caps` 是一个 `map<mds_rank, Cap>`，记录从每个 MDS 持有的 cap 字符串（如 `pAsLsXsFsx` 表示 `Auth/Link/XATTR shared + File shared+exclusive`），三态字段 `issued`（已授予）/`wanted`（应用需要）/`pending`（正在协商）描述当前协议状态
- shared/exclusive 二级语义：例如 `As`（Auth shared）允许多客户端缓存 `mode/uid/gid`，但只读；`Ax`（Auth exclusive）由单一客户端独占持有，期间可本地修改 mode 而不上报 MDS——直到归还时才 flush。File 系列更细：`Fs`（cache size/mtime 元属性）、`Fx`（exclusive 修改属性）、`Fr/Fw`（读写允许）、`Fc`（page cache 缓存）、`Fb`（buffer 缓冲写）、`Fa`（async 异步操作）、`Fl`（lazy 弱一致）
- 当应用调用 `stat` 时，客户端检查 `Inode::caps` 是否覆盖 `As|Ls|Xs|Fs`（足以读全部 stat 字段），命中则零 RPC 返回；缺位则向 MDS 发起 `getattr` 并附带 `wanted` 位提升请求
- MDS 端维护全局 cap 目录，新请求到达时遍历持有者集合判断兼容性：例如 client A 持 `Ax`（exclusive auth），client B 请求 `As`，MDS 必须先 revoke A 的 `Ax`、降级为 `As`，再向 B 颁发 `As`——降级而非直接撤销，最大化保留 A 的可用 cap 子集
- `wanted` 与 `issued` 的解耦：客户端可以"想要"高于"已持"的位（如 wanted=Fw 但 issued=Fr），MDS 在条件允许时异步升级，无需客户端阻塞重试
- cap 与 dentry/inode 的生命周期绑定：cap 释放即缓存字段失效，cap 升级即缓存字段可写，整个流程是协议级原子，无 timeout 估算空间

**取舍**：
- ✅ 强一致 + 高并发：cap 让 8 个语义维度独立共享，多客户端只读场景下命中率接近 100%；POSIX 强一致语义可正确支持 MPI-IO、数据库 WAL 等严格场景
- ✅ 精准撤销：冲突时只回收冲突的 cap 子集，未冲突维度保留——A 改 mode 不会撤销 B 的 size/mtime 缓存
- ✅ 写聚合：持 `Fb`（buffer write）期间客户端可批量缓存写再 flush，比 NFS write-through 节省 80%+ 小写 RPC
- ❌ 状态膨胀：MDS 必须为每个 (client, inode) 维护 cap 记录，10⁵ 客户端 × 10⁶ inode 时 per-MDS 状态表可达 GB 级，cap 持有者数量受 `mds_cache_memory_limit`（默认 4GB）硬约束
- ❌ 协议复杂度：cap 字符串解析、shared/exclusive 兼容矩阵、降级路径、wanted/issued/pending 三态机均显著高于 NFSv4 timeout 模型，client 实现行数 ~10× 于 NFS client
- ❌ 调试困难：cap 状态机异常时（如 dirty cap 卡住、wanted 一直得不到满足），需深入 MDS + client 双侧日志比对 epoch、seq、cap mask，运维门槛高于 NFS 范式

#### 机制 2：MDS 主动 revoke 协议

**原理**：cap 的强一致语义必须配合"撤销可达性"才成立。如果撤销靠超时（NFSv4 lease 90s 模型），则冲突侧最坏要等 90s 才能拿到锁，在多客户端并发改同一目录的场景下完全不可用。CephFS 选择**长连接反向通道 + 主动消息**的协议化撤销：MDS 与客户端之间有持久 session，MDS 发现冲突时立刻通过 session 推送 revoke 消息，客户端在毫秒级 flush 脏数据并 ACK，把"撤销延迟"从超时尺度压到 RTT 尺度。session_timeout 仅作为客户端失联兜底（默认 60s），正常路径完全不依赖。

**设计**：
- session 建立时双向交换 cap 列表与 watermark，之后 MClientCaps 消息（op = `GRANT`/`REVOKE`/`TRUNC`/`FLUSH`/`FLUSHSNAP` 等）作为唯一 cap 状态变更通道，客户端必须按 seq 顺序处理保证不乱序
- 撤销路径：MDS 决策 → 发送 `REVOKE` 给当前持有者，附带要撤销的 cap 位掩码 → 客户端在 cap handler 里执行 `flush_dirty_caps`（持 `Ax/Fb/Fw` 时把脏 mode/buffer/data 回写到 MDS）→ 发回 `MClientCaps op=FLUSH_ACK` → MDS 收到 ACK 才向冲突方颁发新 cap
- 客户端 hang 时的兜底：MDS 在 `mds_session_timeout`（默认 60s）后将 session 标为 stale，再过 `mds_session_autoclose`（默认 5min）evict 该 session，客户端所有 cap 强制失效，对方 cap 请求继续推进；被 evict 客户端后续操作收到 `EBADF` 雪崩，需重 mount 或 `client_reconnect_stale = true` 触发软重连
- 细粒度 flush：revoke 不是"全部回写"，而是按 cap 位精准 flush——撤 `Ax` 只 flush 脏的 mode/uid，撤 `Fb` 只 flush 脏的 page buffer，撤 `Fs` 不需要 flush 数据只需 drop 缓存
- flush 与 revoke 的解耦：client 可以保留 dirty 状态先回 ACK，让 MDS 颁发新 cap 不被磁盘 IO 阻塞——通过 `MClientCaps op=FLUSH`（异步携带 dirty data）+ MDS 端 cap epoch 排序保证最终一致
- revoke 与 lease 协同：dentry lease 是无状态的（MDS 不跟踪持有者），冲突时不发 revoke 而是被动等待 TTL；cap 是强一致的，必须主动 revoke——两者用途互补

**取舍**：
- ✅ 撤销快：正常路径下 cap 撤销在 1 RTT 内完成（典型 IB/万兆 < 1ms，跨数据中心 ~10ms），相比 NFSv4 CB_RECALL 失败回退到 lease 超时（90s），快了 4 个数量级
- ✅ 一致性切换无缝：cap 降级是连续的（exclusive → shared → none），中间态有效，应用观察不到一致性窗口
- ✅ 故障域可控：session 级 evict 把"客户端故障"限制在单 client 范围，不会扩散到整集群（与 Lustre eviction 全节点缓存清零相比，CephFS 只清零受影响 session 的 cap）
- ❌ 反向通道脆弱：session 心跳依赖 TCP 长连接，NAT/防火墙环境下连接保活成本高；session 中断后所有 cap 默认作废，客户端缓存"全清���"重建代价大（10⁵ 数量级 inode 重新协商 cap 可耗时数十秒）
- ❌ 服务端推送负载：MDS 在高并发写场景下要主动推送大量 revoke 消息，单 MDS 处理能力上限约 10-20 万 cap ops/s，超出后 cap 队列堆积导致客户端操作延迟尖刺
- ❌ session 重连歧义：reconnect 阶段 client 需向 MDS 重报 cap 持有声明，期间发生的并发冲突需二次协商；该窗口（默认 45s `mds_reconnect_timeout`）内有限的 cap 状态损失不可避免

#### 机制 3：MDCache LRU + dentry lease

**原理**：cap 强一致虽好，但每个 inode 都协商 cap 在大目录场景过于昂贵——`ls /home`（10⁴ 子项）若每项都走一次 cap 请求，单纯协议开销就让目录遍历变成卡顿源。CephFS 的解法是**dentry 维度叠加一层弱一致 lease**：MDS 在 readdir 响应里顺带颁发批量 dentry lease（带秒级 duration 和 mds session seq），客户端在 lease 内可零 RPC 复用 dentry → inode 的名字解析结果，相当于 NFSv4 acdirmin 但带服务端 seq 校验。同时 client 端的 MDCache 强制总量上限（默认 16k inode），逼近时主动 trim 冷条目并归还 cap，与 MDS 的全局 cap 配额双向协同避免单方面 OOM。

**设计**：
- dentry lease 结构：`(duration_ms, seq, mds_rank)`，MDS 颁发时只承诺"该 dentry 在 duration 内不会被改名/删除"，不保证目标 inode 的属性新鲜——属性新鲜由 cap 决定，lease 只覆盖名字解析这一层
- 命中路径：`lookup("foo")` 命中本地 dentry → 检查 lease 是否过期 + seq 是否仍匹配当前 mds session → 通过则直接返回 dentry 上挂的 inode（inode 字段是否新鲜由 cap 单独保证），否则降级为 cap 协商
- MDCache LRU：每个 Inode/Dentry 挂入 `lru_list`，按 `client_cache_size`（默认 16384 inodes）阈值触发 `trim_cache()`，从 LRU 尾部弹出冷条目并向 MDS 发 `MClientCaps op=RELEASE` 主动归还 cap——这是关键的反压机制：客户端不囤积自己用不到的 cap
- cap thrashing 现象：当 `client_cache_size` 设置过小（如 1024）而工作负载活跃集 > 阈值时，客户端反复 trim 又重新申请同一批 cap，形成 cap ping-pong，MDS RPC 风暴；调优依据是 `ceph daemon ... client cache status` 输出的 `cap_count` 和 `dirty_caps`
- MDS 端反向反压：MDS 通过 `mds_recall_max_caps`（默认 5000/批）+ `mds_recall_warning_threshold`（默认 32k）主动要求 client trim，client 收到 `MClientSession op=RECALL_STATE` 后批量归还冷 cap——这是**双向 LRU**，不仅 client 端按容量 trim，MDS 也可主动驱赶
- lease 与 LRU 协同：trim dentry 时如果 lease 还有效，可一并触发 lease 归还（CEPH_MDS_LEASE_RELEASE）；MDS 收到后从 lease 跟踪表移除，下次冲突操作不需广播 lease 撤销
- lease 与 cap 互补：dentry lease 适合"短期高频复用 + 撤销代价低"（rename 引发 lease 失效，自然过期就行），cap 适合"长期持有 + 撤销代价高"（必须主动 revoke 保证强一致）

**取舍**：
- ✅ 容量可控：`client_cache_size` 给 client 内存占用一个明确上限（16k inode × ~2KB ≈ 32MB），适合内存受限的 FUSE/容器场景
- ✅ readdir 大目录优化：批量 dentry lease 让 1000 项 `ls` 的命中率从 0 提升到 99%（首次 readdir 后），后续 lookup 全部本地完成
- ✅ 双向反压：client 主动 trim + MDS 主动 RECALL_STATE 双管齐下，避免单方面失控（Lustre 的 LRU 是纯客户端单边决策，MDS 无能为力）
- ❌ cap thrashing 调优敏感：`client_cache_size` 默认 16k 对很多 HPC 工作负载偏小，需调到 10⁵-10⁶ 量级，错误调优时性能不升反降（cap RPC 风暴）
- ❌ lease 弱一致空窗：dentry lease duration 内的 rename 仅靠 lease 过期触发失效，与 cap 强一致语义不对齐——应用读到 stale 名字最长 lease duration（默认 ~30s）
- ❌ 非 LRU 友好工作负载效率低：scan-once 大目录遍历会驱赶热数据，缺少类似 Lustre statahead 的访问模式识别——纯 LRU 无法区分"将复用"和"扫一遍即弃"

**交互流程**（Cap Revoke 流程）：

```
Client A (持 Ax/Fb)      MDS                Client B (新写者)
     │                    │                       │
     │  (本地修改 mode、   │                       │
     │   缓存脏 buffer)    │                       │
     │                    │                       │
     │                    │←──[open(file)─────────│
     │                    │   wanted: Ax/Fw]      │
     │                    │                       │
     │                    │ 检查持有者：A 持 Ax   │
     │                    │ 冲突，需 revoke A     │
     │                    │                       │
     │←──[MClientCaps─────│ (反向通道)            │
     │   op=REVOKE Ax|Fb] │                       │
     │                    │                       │
     │ flush dirty mode,  │                       │
     │ flush page buffer, │                       │
     │ drop write cache   │                       │
     │                    │                       │
     │──[MClientCaps─────→│                       │
     │   op=FLUSH_ACK]    │                       │
     │                    │                       │
     │                    │ 向 B 颁发 Ax/Fw       │
     │                    │──[open ok─────────── →│
     │                    │   caps: Ax/Fw]        │
     │                    │                       │
     │ ─ ─ 失败兜底 ─ ─   │                       │
     │ × A 网络中断       │                       │
     │                    │ 60s session_timeout   │
     │                    │ → session stale       │
     │                    │ 5min autoclose        │
     │                    │ → evict A，强制释放   │
     │                    │ A 所有 cap            │
     │                    │──[B 的 open 响应]────→│
     │ A 重连后收 EBADF   │                       │
```

**适用场景与已知坑点**：

适用工作负载是多客户端并发 + 强一致需求 + 低延迟内网 + 可容忍服务端状态成本的场景，如 HPC 共享存储、AI 训练数据集（大规模并行读 + 偶发更新）、容器镜像仓库后端、企业级 NAS 替代。CephFS 在数百到数千客户端规模下表现良好，单 MDS 上限约 10-20 万 cap ops/s，超出可通过 multi-active MDS 子树分区横向扩展。完全不适合**广域网 + 不可信客户端**场景：cap 协议需要双向长连接，session 中断代价大；以及**写共享极端高频**场景：cap ping-pong 退化为 RPC 风暴，单 MDS 处理能力会成为硬瓶颈，比 NFS timeout 兜底范式更差。

最关键的两个坑：
1. **cap thrashing 由 client_cache_size 误配引发**：默认 `client_cache_size = 16384` 在 HPC 大工作负载下经常不够，活跃 inode 集合超过阈值后客户端不断 trim → 再申请，每次 trim 引发 `MClientCaps op=RELEASE` + 后续 cap 重申请，形成双向 RPC 风暴。表现是 MDS CPU 100% 但应用 stat 延迟反而上升 5-10×。诊断依据是 `ceph daemon mds.<id> session ls` 中 `num_caps` 持续震荡，CephFS 生产实践的修复路径是把 `client_cache_size` 调到工作集 1.5× 以上（典型 10⁵-10⁶ 量级），同时调高 `mds_cache_memory_limit` 配套扩容 MDS 端 cap 表。
2. **客户端 hang 引发 EBADF 雪崩**：网络分区或客户端 OS 卡住超过 `mds_session_timeout`（60s）+ `mds_session_autoclose`（5min）时，MDS 单方面 evict session，客户端所有 cap 失效。重连后客户端持有的 fd 全部返回 `EBADF`，应用层（尤其是长跑 daemon、数据库进程）无法优雅恢复，往往需要进程重启。规避方案：开启 `client_reconnect_stale = true` 让客户端在 evict 后尝试软重连恢复 session（牺牲部分一致性），或在应用侧实现 `EBADF` 重试逻辑——但根本上需要保证客户端网络稳定性，CephFS 不是为不可靠链路设计的范式。

### 2.3 Lustre

**方案全景**：

Lustre 把客户端元数据缓存做成「**LDLM 多模式分布式锁强一致主线 + intent-based RPC 把锁请求与元数据查询合并 + statahead 异步预取**」的 HPC 元数据性能三角。LDLM（Lustre Distributed Lock Manager）是绝对主角：客户端任何缓存条目（dentry、inode 属性、目录内容）都必须由一把对应模式的 ibits 锁背书，锁存在则缓存可信，MDS 通过 Blocking AST 主动撤锁来保证一致性，整套机制是「锁即缓存有效期」的强一致语义，不是 NFS 式的 TTL 弱一致。在此基础上，intent layer 把 VFS 的 `lookup → open → getattr` 这种典型多步路径压成一次 MDC RPC，单次往返同时完成名字解析、权限检查、文件打开和锁授予，把 HPC 启动时的 metadata stall 降到最小。再叠一层 statahead：当客户端检测到 `readdir` 后伴随顺序 `stat` 的访问模式时，开一个内核线程异步对窗口内的子项预取属性和锁，让大目录 `ls -l` 这种典型负载的元数据延迟被网络管道化。

整体设计哲学是：**强一致（锁）兜底正确性，合并 RPC（intent）压低关键路径延迟，预取（statahead）把可预测访问模式做成流水线**。这套范式针对 HPC 场景——低延迟内网（IB/RoCE）、大量并发同目录访问、可信任客户端——做了高度专门化，不是通用互联网场景的设计。

**整体架构**：

```
┌──────────────────────────────────────────────────────┐
│  VFS 层 (Linux kernel)                              │
│  └─ inode / dentry cache (内核通用 D-cache)          │
├──────────────────────────────────────────────────────┤
│  llite (Lustre Lite, 客户端 VFS 适配层)              │
│  ├─ ll_inode_info (per-inode Lustre 私有状态)        │
│  ├─ ll_dentry_data (dentry → lock 关联)              │
│  └─ statahead 引擎 (ll_statahead_info, sa thread)    │
├──────────────────────────────────────────────────────┤
│  LDLM Client (分布式锁管理器，客户端侧)              │
│  ├─ 6 模式锁: NL / CR / CW / PR / PW / EX            │
│  ├─ ibits 锁 (LOOKUP / UPDATE / LAYOUT / PERM / XATTR│
│  │            / DOM)                                 │
│  ├─ namespace + lock resource hash                   │
│  └─ Blocking AST handler (响应 MDS 撤锁回调)         │
├──────────────────────────────────────────────────────┤
│  Intent Layer                                       │
│  └─ lookup_intent: IT_OPEN / IT_CREAT / IT_GETATTR  │
│                    / IT_UNLINK / IT_LAYOUT           │
├──────────────────────────────────────────────────────┤
│  MDC (Metadata Client, MDS 的 RPC 客户端)            │
│  └─ mdc_intent_lock / mdc_enqueue / req packing      │
└──────────────────────────────────────────────────────┘
              ↓  Lustre RPC / LNet (TCP/IB/RoCE)
        ┌──────────────────────────┐
        │  MDS / MDT (服务端)       │
        └──────────────────────────┘
```

数据进出方向：VFS 操作命中 dentry/inode 后由 llite 校验 ibits 锁是否仍然有效；锁有效则直接走缓存，锁缺失则下沉到 intent layer 构造一次合并 RPC，由 MDC 发往 MDS。statahead 线程并行旁路注入预取请求。

**核心机制**：

#### 机制 1：LDLM 多模式锁 + ibits 子粒度

**原理**：LDLM 是 Lustre 的核心：把传统单机文件系统的 inode 锁拓展成跨节点分布式锁，客户端持锁即代表它对相应资源有「合法的本地缓存」。锁有 6 种模式（NL/CR/CW/PR/PW/EX），兼容矩阵决定多个客户端能否同时持锁；只读共享走 PR，独占写走 EX。这把缓存一致性问题转换成了分布式锁的兼容判定问题——比 NFS 委托更通用，比 CephFS 单一 capability 模型更精细。

**设计**：元数据资源的关键是 ibits（inode bits）锁：同一把 inode 上的锁不再是整体 EX/PR，而是被切成多个独立比特位——LOOKUP（名字到 inode 的解析有效）、UPDATE（属性 size/mtime/mode）、LAYOUT（数据布局）、PERM（权限）、XATTR、DOM（数据-on-MDT）。每个客户端可以只持有自己用到的那几位，互不干扰。比如客户端 A 在做 `getattr` 持 UPDATE:PR，客户端 B 同时改权限持 PERM:EX，两者完全兼容；只有当 A 也想读权限时才需要协商。锁挂在 `ldlm_resource` 上按资源 ID 哈希索引，客户端通过 `ldlm_lock` 持有引用，dentry/inode 持有锁的反向句柄确保「锁释放则缓存失效」原子绑定。当 MDS 需要授予冲突锁时，向当前持锁客户端发 Blocking AST，客户端在 callback 里 drop 缓存并 cancel 锁。

**取舍**：
- ✅ 优势量化：ibits 把 inode 锁切成 6 个独立维度（LOOKUP/UPDATE/LAYOUT/PERM/XATTR/DOM），独立维度并发率提升约 6×（理论上是 6 个 bit 的笛卡尔积）；LDLM 提供 POSIX 强一致，HPC MPI-IO 场景可正确运行
- ✅ 适用：低延迟可信内网，POSIX 强一致需求
- ❌ 代价量化：单次 LDLM enqueue 在 IB 网络上 ~150-300μs，在 WAN 下放大到 5-50ms，回调风暴下 BL_AST 超时（默认 100s）会触发客户端 eviction，整节点缓存全部作废。锁状态在客户端和 MDS 双副本，per-inode 状态约几百字节，10⁶ 文件持锁 ≈ 数百 MB 内存
- ❌ 不适用：广域网、大规模不可信客户端、写共享极端高频场景（锁 ping-pong）

#### 机制 2：Intent-based RPC

**原理**：VFS 路径 walk 是「逐步」的：`open("/a/b/c")` 在 Linux VFS 里要分解为 `lookup(a) → lookup(b) → lookup(c) → open(c)`，每一步若 cache miss 都是一次 RPC。HPC 启动 10⁴ 进程同时打开同一个共享配置文件时，这种串行 RPC 是��难。Intent RPC 的核心思想是：**让客户端在请求锁的同时声明意图（intent），MDS 一次事务内完成名字解析、属性返回、权限检查、文件打开和锁授予**。

**设计**：`lookup_intent` 结构携带操作语义（`IT_OPEN`、`IT_CREAT`、`IT_GETATTR`、`IT_UNLINK`、`IT_LAYOUT` 等）和操作参数（如 open flags、create mode），在 llite 进入 `ll_lookup_it` 时构造，向下传给 MDC 的 `mdc_intent_lock`。MDS 端识别 intent 后在同一事务里执行：解析路径找到 inode → 检查权限 → 必要时创建/打开 → 准备返回的元数据（属性 + body）→ 授予对应 ibits 锁 → 把锁、元数据、文件 handle 一起塞进同一个 RPC 应答。客户端拿到回包后一次性安装 dentry、inode、open file 和锁。等于把 lookup+stat+open+lock_enqueue 四次 RPC 合并为一次。

**取舍**：
- ✅ 优势量化：典型 HPC `mpirun` 同时 open 共享文件场景，元数据延迟从 4 RTT 降到 1 RTT，启动时间降低 60-75%（论文 Lustre at LLNL/ORNL 报告）；create+open 场景 RPC 次数从 3 降到 1
- ✅ 适用：典型路径 walk + 操作的场景（open/create/getattr/unlink）
- ❌ 代价量化：MDS 端事务复杂度上升约 30%（一次事务做多件事，回滚路径更复杂）；intent 类型 + 错误路径排列组合多，代码复杂度高，新增一种 intent（如 LAYOUT）需要客户端、协议、MDS 三方协同。协议需精确定义每种 intent 的 lock 模式和返回字段，跨版本演进成本高
- ❌ 不适用：纯属性查询（intent 多余）、不可预测的复合操作；纯 getattr 工作负载下 intent 的合并收益退化为 0，但协议复杂度成本（事务回滚 + 跨版本演进）仍存在；缓存命中率 80% 时进入 RPC 的请求已多为 cold path，intent 合并收益边际递减约 80%

**交互流程**（intent-based RPC，最体现 Lustre 特色）：

以 `open("/proj/data/cfg.txt", O_RDONLY)` 为例，客户端 dentry/inode/lock 全部冷启动：

```
Client (llite/MDC)                              MDS (MDT)
─────────────────                              ──────────
ll_lookup_it("/proj/data/cfg.txt")
    │ build lookup_intent {
    │     it_op = IT_OPEN,
    │     it_flags = O_RDONLY,
    │     it_lock_bits = LOOKUP|UPDATE|LAYOUT
    │ }
    ▼
mdc_intent_lock()
    │ pack req: (parent_fid, name, intent)
    │── ldlm_enqueue(intent piggybacked) ───────▶  on MDS:
    │                                              ├─ resolve "/proj/data/cfg.txt"
    │                                              ├─ check perm
    │                                              ├─ open file, alloc handle
    │                                              ├─ grant ibits lock (PR mode)
    │                                              ├─ pack reply:
    │                                              │   { fid, attrs, layout,
    │                                              │     lock_handle, file_handle }
    │                                              │   单一事务完成
    ◀────────── single RPC reply ──────────────────┘
    │ install dentry, inode, ll_inode_info
    │ attach ldlm_lock to dentry
    │ install file handle to fd table
    ▼
return fd
```

之后该客户端对该文件的 `fstat`/`read` 元数据访问全部命中本地缓存（锁仍持有），零 RPC。对比 NFSv3：同样路径需 lookup×3 + open，至少 4 次 RTT，且无强一致保证。

#### 机制 3：Statahead 异步预取

**原理**：HPC 大目录 `ls -l`、AI 训练数据集遍历、备份扫描这类负载有强模式特征：`readdir` 后紧跟对每个 entry 的 `stat`。串行做就是 `dirsize` 次 RPC���statahead 检测这种模式后启动后台预取线程，把窗口内 N 个子项的 lookup+getattr 提前管道化下发，主线程实际执行 `stat` 时已命中缓存。

**设计**：当 llite 在同一目录内连续两次 `lookup` 命中（pattern detected），创建 `ll_statahead_info` 并启动一个内核线程 `sa_thread`。sa_thread 顺序读 readdir 流，对每个 entry 通过 intent layer 异步发 `IT_GETATTR` RPC，请求 LOOKUP+UPDATE 两个 ibits。窗口大小 `statahead_max` 默认 32，可调到 1024+。预取结果挂在 dentry hash 上等主线程认领，主线程的 `stat` 调用直接命中已 populate 的 dentry+inode+lock，跳过 RPC。预取请求批量发出，与主线程操作在网络层流水化。失败或锁冲突时静默丢弃，不影响主线程语义。

**取舍**：
- ✅ 优势量化：大目录（10⁴-10⁵ 文件）`ls -l` 加速 20-30×（窗口=32），元数据 RPC 总耗时被网络管道掩盖；窗口扩大到 1024 时可达 50×+ 但内存压力线性上升
- ✅ 适用：HPC 顺序遍历、AI 数据集加载、备份扫描
- ❌ 代价量化：错检模式时纯浪费——非顺序访问场景预取的 RPC 全部作废，MDS 负载放大 N 倍；小目录（<8 entry）预取启动开销 > 收益；窗口内未消费的锁占内存（每锁几百字节，1000 文件预取 ≈ 数百 KB-MB）。预取线程与主线程的 dentry 安装存在竞态，需要细致的锁
- ❌ 不适用：随机访问、深度优先遍历、内存紧张节点（可关闭 `lctl set_param llite.*.statahead_max=0`）

**适用场景与已知坑点**：

适用场景是 HPC（百节点-万节点规模）、并行计算 MPI-IO、AI 大规模训练数据集、低延迟可信内网（IB/RoCE/低延迟以太网）、需要 POSIX 强一致语义的科学计算工作负载。Lustre 范式对「同一目录大量并发 + 顺序访问 + 网络稳定 + 客户端可信」的优化是同类系统中最深入的，但相应换来的是对网络抖动敏感、广域网不友好、运维复杂。

关键坑点：
1. **statahead 在小目录或非顺序访问下的预取浪费**：默认窗口 32 在 4-8 文件目录里启动开销大于收益，在随机访问应用（如某些数据库索引扫描）会让 MDS 负载放大数倍。Lustre 生产实践要求按工作负载分类调优 `statahead_max`，业务方需提供访问模式信息或主动关闭。
2. **LDLM 锁回调风暴**：单一热点 inode（如共享配置文件被 10⁴ 客户端并发读，写者出现）触发 BL_AST 大规模发送，MDS 出向带宽和客户端响应延迟都会被打爆；BL_AST 在客户端忙时超时（默认 100s），MDS 直接把客户端 evict，整节点本地缓存被强制 drop 重建，重建期间 RPC 风暴自我加剧。这是 Lustre 在广域网部署近乎不可用的根因，缓解依赖 lock-ahead、锁重试、客户端分组等多重补丁，并非单一机制能解。

## 3. 关键决策维度对比

### 3.1 一致性机制：从 timeout 到 cap 到 DLM

**标杆对比**：

| 标杆 | 方案 | Trade-off | 适用场景 |
|------|------|----------|---------|
| NFSv4 | attribute timeout（acregmin/acregmax 3s/60s 默认）+ CTO 语义 + 可选 delegation 升级；CHANGE 计数器单调递增比对 | 强：会话内 GETATTR 节省 80-95%，无服务端状态；弱：跨客户端 stale 窗口最坏 60s，CB_RECALL 反向通道 NAT 穿透困难（冲突侧 hang 至 lease 90s），CHANGE 属性精度依赖后端文件系统精度（ext3 同秒内二次写不可见） | 弱共享或独占访问的 POSIX 应用；不适合实时协作 |
| CephFS | capability bits（8 类 14 比特，Auth/Link/XATTR/File 各 shared/exclusive）+ MDS 主动 revoke + dentry lease 弱一致补充 | 强：POSIX 强一致 + 多维并发命中率近 100%，cap 撤销 1 RTT；弱：MDS 必须维护 per-(client,inode) 状态，10⁵ × 10⁶ 时表可达 GB 级 | 多客户端并发 + 强一致 + 内网；不适合广域网或写共享高频 |
| Lustre | LDLM 6 模式锁（NL/CR/CW/PR/PW/EX）+ ibits 子粒度（LOOKUP/UPDATE/LAYOUT/PERM/XATTR/DOM）+ Blocking AST 撤锁 | 强：POSIX 强一致 + 6 维独立并发，IB 网络 enqueue 150-300μs；弱：BL_AST 超时（100s）触发整节点 eviction，缓存全部作废 | HPC 低延迟可信内网 + MPI-IO；不适合广域网或不可信客户端 |

**约束影响分析**：

- **一致性窗口 = close-to-open（弱一致）**（来源：生成期确认） → 影响：三个标杆均能满足该约束。NFSv4 timeout 范式在该约束下仅需 GETATTR + CHANGE 比对即可达成 CTO 语义；CephFS cap 与 Lustre LDLM 的"强一致维度"在 CTO 工作负载下无法被兑现（应用本身不要求字段级实时可见性），其细粒度撤销机制在该约束下精度高于该约束需求，但仍可作为独占访问加速的可选叠加层（CephFS cap 的 exclusive 模式 / NFSv4 delegation 都是该形态）
- **客户端规模 < 百级**（来源：生成期确认） → 影响：三个标杆的服务端状态在百级规模下都未触及单 MDS 内存硬上限（详见 §3.2），约束在该维度不构成方案排除条件
- **网络拓扑 = 内网（RTT < 10ms）**（来源：生成期确认） → 影响：CephFS cap revoke 与 Lustre BL_AST 的"反向通道脆弱性"在该约束下被极大缓解（NAT 问题不存在、单 RTT 撤销 < 10ms），三个标杆都能在该网络条件下正常工作；NFSv4 CB_RECALL 的 NAT 不可达问题也同样消除。timeout 范式的"无服务端状态"优势在该约束下不依赖网络条件，仍然成立
- **性能目标延迟降低 50-80% + 命中率 70-90%**（来源：proposal.md#Impact） → 影响：一致性窗口越长命中率越高，但与窗口越短跨客户端可见性越强冲突，需在弱一致基线 + 可选升级之间权衡
- **协议要求租约或失效通知两种模式**（来源：proposal.md#Capabilities） → 影响：协议形态在该约束下限定为 timeout 类（租约到期失效）或反向通知类（推送失效）这两种范式，DLM 通用锁不在 proposal 列出的待选范围内

### 3.2 服务端状态预算：无状态 vs 持有者跟踪 vs 锁状态机

**标杆对比**：

| 标杆 | 方案 | Trade-off | 适用场景 |
|------|------|----------|---------|
| NFSv4 | 默认无状态（仅 timeout 协议）；启用 delegation 后跟踪 stateid + lease；NFSv4.1 引入 sessions 跟踪客户端会话 | 强：默认水平扩展无状态负担；弱：delegation 启用后需跟踪每个 (client, inode, deleg) + 心跳续约 | 服务端规模可弹性，运维代价最小化优先 |
| CephFS | 全局 cap registry：per-(client, inode) cap 状态记录（issued/wanted/pending），mds_cache_memory_limit 默认 4GB 硬上限；session 长连接 + 心跳 60s | 强：撤销可达性强、cap 降级精准；弱：状态膨胀严重，10⁵ × 10⁶ 规模需多 active MDS 子树分区 | 状态成本可承担、需要主动撤销可达性 |
| Lustre | LDLM namespace 维护锁双副本（client + MDS），per-inode 锁状态约几百字节，10⁶ 文件 ≈ 数百 MB；BL_AST 超时 100s 触发 eviction | 强：锁兼容矩阵清晰、ibits 让锁数减少；弱：eviction 颗粒度粗（整节点缓存清零），重建期间风暴自我加剧 | HPC 可信集群，节点稳定 + 网络可靠 |

**约束影响分析**：

- **客户端规模 < 百级**（来源：生成期确认） → 影响：以 100 客户端 × 每客户端 10⁴-10⁵ 缓存条目（对应 client 内存预算 100MB-1GB，按客户端侧每条 ~10KB 估，含 dentry/inode/属性合计）为典型工作集，cap 范式 per-(client, inode) 表总量约 10⁶-10⁷ 条目 × 100B 服务端每条 cap 元数据 ≈ 100MB-1GB 服务端状态（注：客户端 10KB/条与服务端 100B/条是不同口径——客户端缓存包含完整 dentry+inode+属性，服务端 cap 仅记录 (client_id, inode_id, cap_bits, seq) 元数据），落在 `mds_cache_memory_limit` 默认 4GB 之内；若按"每客户端 10⁶ 条目"的极端上限取 100 × 10⁶ × 100B ≈ 10GB，超出默认 4GB 约 2.5×，需调高 `mds_cache_memory_limit` 或启用 multi-active MDS 子树分区。具体取值取决于实际客户端数与单客户端工作集（C×F）
- **一致性窗口 = close-to-open（弱一致）**（来源：生成期确认） → 影响：弱一致放弃了"协议级精确撤销"的需求，使无状态 timeout 范式成为可行基线，无需投入服务端状���预算来实现 cap registry 或 LDLM namespace
- **客户端内存预算 100MB-1GB**（来源：proposal.md#Impact） → 影响：服务端状态成本是与客户端缓存容量成正比的，反过来限制可缓存的总条目数；选 cap 范式且每条 cap 1KB 状态时，客户端 1GB 缓存对应服务端潜在 1GB × N_clients 的总状态量
- **网络拓扑 = 内网（RTT < 10ms）**（来源：生成期确认） → 影响：状态同步开销低，cap revoke 心跳和 lease 续约对带宽影响可忽略；这意味着即使选择重状态范式，运行时开销不会成为瓶颈
- **MDS 负载降低 60-80%**（来源：proposal.md#Impact） → 影响：服务端状态维护本身消耗 MDS CPU，过重的 cap revoke 推送可能反向冲销缓存收益

### 3.3 撤销机制：超时被动 vs 反向通道主动 vs 锁回调

**标杆对比**：

| 标杆 | 方案 | Trade-off | 适用场景 |
|------|------|----------|---------|
| NFSv4 | 主路径：timeout 自然失效（acregmax 60s 默认）；可选：delegation 模式下用反向通道发 CB_RECALL，失败回退到 lease 90s 强制回收 | 强：无反向通道时仍可工作；弱：跨客户端可见性最坏 60s，CB_RECALL 失败导致冲突侧 hang 90s | NAT/防火墙环境、可容忍秒级 stale 窗口 |
| CephFS | 长连接 session + MClientCaps op=REVOKE 主动推送，客户端必须按 seq 顺序 ACK；session_timeout 60s 仅作失联兜底 | 强：1 RTT 撤销（< 1ms 内网，~10ms 跨数据中心）；弱：session 中断后所有 cap 作废，10⁵ inode 重建可耗数十秒 | 内网长连接稳定，需要毫秒级撤销可达 |
| Lustre | Blocking AST 反向回调，MDS 通知持锁客户端 drop 缓存并 cancel 锁；BL_AST 超时 100s 后 evict 客户端 | 强：撤销与锁授予是事务性配对；弱：BL_AST 风暴下 MDS 出向带宽打爆，eviction 整节点缓存清零自我加剧风暴 | 内网 + 客户端可信 + 写共享冲突可控 |

**约束影响分析**：

- **一致性窗口 = close-to-open（弱一致）**（来源：生成期确认） → 影响：CTO 接受跨客户端 stale 窗口至会话边界，在该约束下 NFSv4 的"timeout 自然失效"已可独立兑现一致性语义；CephFS REVOKE 与 Lustre BL_AST 的"事务性撤销"在 CTO 工作负载下其精度收益无法被应用感知，但其反向通道机制本身在该约束下并未失效，可作为"独占访问加速"叠加层使用（如 NFSv4 delegation 的 CB_RECALL 形态）
- **客户端规模 < 百级**（来源：生成期确认） → 影响：百级客户端的反向连接管理开销可控，CephFS / Lustre 的反向通道方案在工程实现上无规模障碍；同时 LDLM eviction 的"整节点缓存清零"在百级规模下故障半径小，重建期间 RPC 风暴的总量在 MDS 容量内
- **网络拓扑 = 内网（RTT < 10ms）**（来源：生成期确认） → 影响：CB_RECALL / REVOKE / BL_AST 三种反向通道的"NAT 不可达"和"超时回退"风险被消除（CephFS 与 Lustre 在内网下不会回退到超时路径，NFSv4 CB_RECALL 同样可达），三个标杆在该网络条件下表现等价
- **客户端-MDS 协议需扩展**（来源：proposal.md#What Changes / Impact） → 影响：扩展协议的复杂度差异 100×（NFSv4 timeout 仅需 GETATTR + CHANGE 字段，Lustre LDLM 需引入完整锁管理器），影响实现工作量
- **上述三约束叠加**（CTO + 百级 + 内网） → 影响：在该组合约束下，三个标杆的撤销机制均可正常工作；差异退化为协议复杂度（NFSv4 仅需 GETATTR + CHANGE 字段，CephFS 需 cap 协商 + session 心跳，Lustre 需完整 LDLM 锁管理器），design 阶段需在协议复杂度与撤销精度之间权衡

### 3.4 批量化与预取：COMPOUND vs intent vs statahead

**标杆对比**：

| 标杆 | 方案 | Trade-off | 适用场景 |
|------|------|----------|---------|
| NFSv4 | COMPOUND 把多 op 打包进 1 个 RPC；READDIR with attr bitmap（READDIRPLUS 语义）批量返回属性；nfs_use_readdirplus 启发式自适应判断 | 强：5 层路径 lookup 从 5 RTT 降到 1 RTT（绝对节省 = 4×RTT，10ms RTT 时 40ms，1ms RTT 时 4ms）；1000 项 ls -l 从 1001 RTT 降到 ~10（绝对节省 = ~1000×RTT，10ms RTT 时 10s，1ms RTT 时 1s）；弱：全或无失败语义，启发式误判时浪费 10-100KB 带宽，路径深度 N=2 时收益降为 1 RTT vs 2 RTT（绝对节省退化 60%） | 路径深度大或大目录场景，启发式可调优 |
| CephFS | readdir 时批量颁发 dentry lease 把名字解析批量复用；cap 是按需协商无显式合并；MDS 端 mds_recall_max_caps 5000/批反向反压 | 强：批量 lease 让 1000 项 ls 命中率从 0 提升到 99%；弱：lease 仅覆盖名字层，属性仍需 cap 协商，无法完全消除 RPC；`client_cache_size` 默认 16k 在大目录场景下不足，活跃集 > 阈值触发 cap thrashing，MDS RPC 风暴，批量 lease 收益被 cap 协商抵消 | readdir 后高频 lookup 复用，如 ls 工作流 |
| Lustre | intent RPC 把 lookup+stat+open+lock 4 次 RPC 合成 1 次（语义合并，非语法合并）；statahead 异步预取窗口 32-1024，主线程命中已 populate 的 dentry | 强：mpirun 启动从 4 RTT 降到 1 RTT（绝对节省 = 3×RTT，10ms RTT 时 30ms，1ms RTT 时 3ms），HPC 启动时间降低 60-75%；ls -l 加速 20-30×；弱：错检模式时 MDS 负载放大 N 倍，小目录预取开销 > 收益 | HPC 顺序遍历 + 大窗口预取 + 路径访问模式可预测 |

**约束影响分析**：

- **性能目标延迟降低 50-80%**（来源：proposal.md#Capabilities） → 影响：批量化和预取是延迟降低的主要来源（缓存命中率提升的边际收益已充分讨论），需选择对工作负载贡献最大的批量形式
- **缓存命中率 70-90% 与批量化的隐性交互**（来源：proposal.md#Impact 推导） → 影响：命中率 70-90% 意味着进入 RPC 路径的请求已是 cold path（10-30%），批量化（COMPOUND/intent）只对该尾部生效。在平均延迟口径下（命中率 80% 假设），批量化对总延迟的贡献占比降至 10-30%（即缓存命中场景下批量化收益占比 10-30%）；在 P99 延迟口径下（缓存 miss 主导的尾部场景），批量化收益占比恢复至接近 100%，对长尾请求的延迟降低仍是主要手段。预取（READDIRPLUS/statahead）通过提前 populate 缓存可直接抬高命中率，与批量化形成互补而非重叠
- **网络拓扑 = 内网（RTT < 10ms）**（来源：生成期确认） → 影响：批量化的相对收益（X×）与 RTT 无关，但绝对收益（毫秒数）与 RTT 成正比。以 RTT=10ms（约束上限）计算：5 RTT 路径 lookup 节省 40ms，1000 项 ls -l 节省 ~10s，相对仍为 5× / 100×；以 RTT=1ms（典型 IB/RoCE）计算，绝对收益降至 4ms / 1s，相对收益不变。该量化与对比表数字一致，design 阶段需结合典型路径深度（N=2 时退化 60%）与目录大小判断绝对收益是否值得引入相应协议复杂度
- **一致性窗口 = close-to-open（弱一致）**（来源：生成期确认） → 影响：弱一致允许预取的属性带"陈旧"语义（首次访问时校验），降低了预取的协议复杂度；强一致路径必须为预取条目同步颁发锁/cap，使 statahead 这类异步预取显著昂贵
- **客户端规模 < 百级**（来源：生成期确认） → 影响：服务端可承受 statahead 风格的"投机性预取" RPC 放大（即使错检几次，百级客户端的 MDS 总负载仍在容量范围内），允许较激进的预取窗口

## 引用与追溯

**标杆 NFSv4**：
- RFC 7530：Network File System (NFS) Version 4 Protocol（NFSv4.0）
- RFC 8881：Network File System (NFS) Version 4 Minor Version 1 Protocol（NFSv4.1，含 sessions / backchannel / change_attr_type）
- Linux 内核源码：`fs/nfs/`（attribute cache、delegation manager、COMPOUND 实现）
- Brian Pawlowski et al., "The NFS Version 4 Protocol", USENIX 2000（CTO 语义设计动机）
- Brent Callaghan, *NFS Illustrated*, Addison-Wesley, 2000

**标杆 CephFS**：
- Sage Weil, "Ceph: Reliable, Scalable, and High-Performance Distributed Storage"（PhD thesis, UCSC, 2007）
- Ceph 源码：`src/client/`（MDCache / Capability Manager / MetaSession）、`src/mds/`（cap registry / revoke 调度）
- CephFS 官方文档：https://docs.ceph.com/en/latest/cephfs/（client config / cap thrashing 调优 / mds_cache_memory_limit）
- `ceph daemon mds.<id> session ls` / `ceph daemon client cache status` 运维工具输出格式

**标杆 Lustre**：
- Lustre 源码：`lustre/llite/`（VFS 适配 / statahead 引擎）、`lustre/ldlm/`（分布式锁管理器）、`lustre/mdc/`（MDS RPC 客户端 / intent layer）
- Lustre 官方文档：https://doc.lustre.org/lustre_manual.xhtml（LDLM lock modes / ibits / statahead 配置 / lctl 调优）
- Lustre at LLNL/ORNL 性能报告（intent RPC mpirun 启动时间降低数据来源）
- Peter Braam, "The Lustre Storage Architecture", Cluster File Systems Inc., 2003

**产品级文档锚点**：本特性 Product Traceability 标注"不适用：跨项目设计探索"（proposal.md#Product Traceability），无关联产品级架构或需求文档。

