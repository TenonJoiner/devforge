# 主题 1: 缓存对象粒度与数据结构 — 标杆方案空间

## 维度 1.1: 缓存对象粒度

### 方案 A: Dentry 级缓存（Linux VFS dcache）

**标杆来源**: [Linux VFS](https://docs.kernel.org/6.0/filesystems/vfs.html)

**原理**:
- 缓存目录项（dentry）作为基本单位，每个 dentry 表示路径中的一个组件
- Dentry 包含指向父 dentry 的指针、关联 inode 的指针、子 dentry 哈希列表
- 核心思想：路径解析是文件系统最频繁的操作，缓存路径组件比缓存完整 inode 更高效

**设计**:
- 数据结构：`struct dentry` 包含 `d_parent`、`d_inode`、`d_child`、`d_hash` 等字段
- 控制流：路径解析时逐级查找 dcache，命中则直接返回，未命中则创建新 dentry 并加载 inode
- 接口形态：`d_lookup()` 在哈希表中查找 dentry，`d_alloc()` 分配新 dentry

**取舍**:
- **放大**: 路径解析性能（O(1) 哈希查找 vs O(log n) 树查找）
- **牺牲**: 内存开销（每个路径组件都需要独立 dentry 对象，包含多个指针字段）
- **适用场景**: 路径解析密集型工作负载（如 `ls -R`、编译构建）
- **不适用场景**: 大量小文件场景下内存占用过高

---

### 方案 B: Inode 级缓存（NFS client attribute cache）

**标杆来源**: [NFS client](https://avidandrew.com/understanding-nfs-caching.html), [NFS attribute caching](https://gist.github.com/denji/8743267)

**原理**:
- 缓存文件属性（inode）作为基本单位，通过文件句柄（fh）索引
- 核心思想：属性查询（stat/getattr）是分布式文件系统的主要开销，缓存属性可减少 RPC 调用
- 使用 TTL 机制控制缓存有效期，平衡一致性与性能

**设计**:
- 数据结构：`struct nfs_inode` 包含 `fattr`（文件属性）、`cache_validity`（有效性位图）、`attrtimeo`（属性超时时间）
- 控制流：getattr 时先检查缓存有效性和 TTL，未过期则直接返回，过期则发起 RPC 刷新
- 接口形态：`nfs_refresh_inode()` 更新缓存，`nfs_check_inode_attributes()` 验证有效性

**取舍**:
- **放大**: 属性查询性能（避免 RPC 往返延迟，典型节省 1-10ms）
- **牺牲**: 一致性（TTL 期间可能读到过期数据）、路径解析效率（需额外维护 name→fh 映射）
- **适用场景**: 属性查询密集型工作负载（如 `find`、`du`）、可容忍弱一致性
- **不适用场景**: 强一致性需求、频繁路径解析场景

---

### 方案 C: Inode+Dentry 混合缓存（CephFS client）

**标杆来源**: [CephFS MDS cache](https://docs.ceph.com/en/latest/cephfs/mdcache/), [CephFS distributed metadata cache](https://oneuptime.com/blog/post/2026-03-31-rook-distributed-metadata-cache-cephfs/view)

**原理**:
- 同时缓存 inode 和 dentry，两者通过指针关联
- Inode 缓存文件属性和能力（capabilities），dentry 缓存路径映射
- 核心思想：结合路径解析和属性查询的优势，通过能力机制实现强一致性

**设计**:
- 数据结构：`Inode` 对象包含属性和能力位图，`Dentry` 对象包含名称和指向 Inode 的指针
- 控制流：路径解析时查找 dentry 缓存，属性访问时检查 inode 能力有效性
- 接口形态：`Client::lookup()` 查找 dentry，`Client::_getattr()` 获取属性并验证能力

**取舍**:
- **放大**: 同时优化路径解析和属性查询，支持强一致性（通过能力撤销机制）
- **牺牲**: 内存开销（需同时维护两种对象）、复杂度（能力管理、失效传播）
- **适用场景**: 混合工作负载、需要强一致性的分布式文件系统
- **不适用场景**: 内存受限环境、简单的只读场景

---

### 方案 D: 路径级缓存（FUSE passthrough）

**标杆来源**: [FUSE client cache](https://docs.ezmeral.hpe.com/datafabric-customer-managed/80/AdministratorGuide/MapRfusePOSIXClient-TuneCache.html)

**原理**:
- 缓存完整路径到元数据的映射，避免逐级解析
- 核心思想：对于频繁访问的固定路径（如配置文件、日志目录），完整路径缓存可最小化查找开销

**设计**:
- 数据结构：哈希表，key 为完整路径字符串，value 为元数据结构体
- 控制流：路径查找时先在完整路径缓存中查找，未命中再回退到逐级解析
- 接口形态：`path_cache_lookup(const char *path)` 返回缓存的元数据或 NULL

**取舍**:
- **放大**: 热点路径访问性能（单次哈希查找 vs 多次 dentry 查找）
- **牺牲**: 内存开销（路径字符串占用空间大）、缓存失效复杂度（父目录变更需失效所有子路径）
- **适用场景**: 路径访问模式高度集中（如 Web 服务器访问固定资源）
- **不适用场景**: 路径访问模式分散、频繁目录重命名

---

## 维度 1.2: 索引数据结构

### 方案 A: 哈希表索引（Linux VFS dcache）

**标杆来源**: [Linux VFS](https://docs.kernel.org/6.0/filesystems/vfs.html)

**原理**:
- 使用哈希表实现 O(1) 平均查找时间
- 哈希键为 `(parent_dentry, name)` 二元组，确保同名文件在不同目录下不冲突
- 核心思想：元数据查找是随机访问模式，哈希表比树结构更高效

**设计**:
- 数据结构：全局哈希表 `dentry_hashtable[]`，每个桶是链表头
- 哈希函数：`hash = hash_32(parent_dentry_ptr ^ hash_name(name))`
- 冲突解决：链地址法，同一桶内的 dentry 通过 `d_hash` 字段链接
- 控制流：`d_lookup()` 计算哈希值，遍历对应桶的链表，比较 parent 和 name

**取舍**:
- **放大**: 查找性能（O(1) 平均，最坏 O(n) 当哈希冲突严重）
- **牺牲**: 内存局部性（链表节点分散，缓存行利用率低）、范围查询能力（无法高效列举某目录下所有子项）
- **量化数据**: Linux 内核默认哈希表大小为 `2^(PAGE_SHIFT + 9)`，64 位系统约 256K 桶
- **适用场景**: 随机访问为主、查找性能优先
- **不适用场景**: 需要范围查询、内存极度受限

---

### 方案 B: Radix Tree 索引（路径前缀匹配）

**标杆来源**: [Adaptive Radix Tree](https://www.researchgate.net/publication/261087784_The_adaptive_radix_tree_ARTful_indexing_for_main-memory_databases), [Radix tree vs Hash table](https://stackoverflow.com/questions/78170850/radix-tree-vs-hashtable)

**原理**:
- 使用基数树（Radix Tree）按路径前缀组织元数据
- 核心思想：文件系统路径具有层次结构，前缀树可利用路径公共前缀减少内存占用，支持前缀查询

**设计**:
- 数据结构：每个节点包含部分路径字符串、子节点指针数组、叶子节点存储元数据
- 自适应节点大小：根据子节点数量选择 Node4/Node16/Node48/Node256（ART 优化）
- 控制流：从根节点开始，逐字符匹配路径，到达叶子节点返回元数据
- 接口形态：`radix_tree_lookup(tree, path)` 返回元数据，`radix_tree_insert(tree, path, metadata)` 插入

**取舍**:
- **放大**: 内存效率（公共前缀只存储一次）、前缀查询能力（如列举 `/home/user/*`）
- **牺牲**: 查找性能（O(k) k 为路径长度，vs 哈希表 O(1)）、实现复杂度（节点分裂/合并逻辑）
- **量化数据**: ART 论文显示内存占用比哈希表低 30-50%，查找性能慢 10-20%
- **适用场景**: 路径前缀重复度高、需要前缀查询、内存受限
- **不适用场景**: 路径长度差异大、纯随机访问

---

### 方案 C: B+Tree 索引（有序范围查询）

**标杆来源**: [B-Tree vs Hash Table](https://substack.com/home/post/p-163038316), [Database indexing](http://designgurus.io/blog/database-indexing)

**原理**:
- 使用 B+Tree 维护有序的元数据索引
- 核心思想：支持范围查询（如列举目录内容）和有序遍历，适合需要排序输出的场景

**设计**:
- 数据结构：内部节点存储键和子节点指针，叶子节点存储键值对并通过链表连接
- 键设计：`(parent_inode, name)` 复合键，确保同一目录的子项聚集在相邻叶子节点
- 控制流：查找时从根节点二分查找到叶子节点，范围查询时顺序遍历叶子链表
- 接口形态：`btree_lookup(tree, key)` 单点查找，`btree_range_query(tree, start_key, end_key)` 范围查询

**取舍**:
- **放大**: 范围查询性能（O(log n + m) m 为结果数量）、有序遍历能力
- **牺牲**: 单点查找性能（O(log n) vs 哈希表 O(1)）、写入性能（节点分裂开销）
- **量化数据**: 典型 B+Tree 扇出 100-200，3 层可索引 100 万条目
- **适用场景**: 需要目录列举、排序输出、范围查询
- **不适用场景**: 纯随机访问、写入密集型工作负载

---

### 方案 D: 多级索引（GlusterFS inode table + dentry cache）

**标杆来源**: [GlusterFS inode datastructure](https://gluster-documentations.readthedocs.io/en/latest/Developer-guide/datastructure-inode/), [GlusterFS performance tuning](https://docs.gluster.org/en/latest/Administrator-Guide/Performance-Tuning/)

**原理**:
- 第一级：inode 哈希表，按 inode 号索引
- 第二级：dentry 哈希表，按 `(parent_inode, name)` 索引
- 核心思想：分离 inode 和 dentry 索引，支持多路径访问同一 inode（硬链接）

**设计**:
- 数据结构：
  - `inode_table`: 哈希表，key 为 inode 号，value 为 `inode_t` 结构体
  - `dentry_table`: 哈希表，key 为 `(parent_inode, name)` 哈希值，value 为 `dentry_t` 结构体
- 控制流：
  - 路径解析：查找 dentry_table 获取 inode 号，再查找 inode_table 获取 inode
  - 属性访问：直接查找 inode_table
- 接口形态：`inode_find(inode_table, ino)` 查找 inode，`dentry_find(dentry_table, parent, name)` 查找 dentry

**取舍**:
- **放大**: 支持硬链接（多个 dentry 指向同一 inode）、灵活的失效策略（可独立失效 dentry 或 inode）
- **牺牲**: 查找开销（两次哈希查找 vs 一次）、内存开销（两个哈希表）
- **适用场景**: 需要支持硬链接、复杂的缓存失效策略
- **不适用场景**: 内存受限、不使用硬链接的简单场景

---

## 维度 1.3: 属性存储方式

### 方案 A: 完整 Inode 副本（Linux VFS inode cache）

**标杆来源**: [Linux VFS](https://docs.kernel.org/6.0/filesystems/vfs.html)

**原理**:
- 缓存完整的 `struct inode`，包含所有文件属性和文件系统特定数据
- 核心思想：简化缓存管理，避免部分属性缺失导致的二次查询

**设计**:
- 数据结构：`struct inode` 包含通用字段（`i_mode`、`i_size`、`i_mtime` 等）和文件系统私有字段（通过 `i_private` 指针）
- 内存布局：固定大小的通用部分 + 可变大小的私有部分
- 控制流：inode 分配时一次性分配完整结构体，释放时整体回收
- 接口形态：`iget_locked(sb, ino)` 分配或查找 inode，`iput(inode)` 释放引用

**取舍**:
- **放大**: 访问性能（所有属性一次加载，无需二次查询）、实现简单
- **牺牲**: 内存占用（即使只需要部分属性也缓存全部）、缓存行浪费（冷属性占用缓存行）
- **量化数据**: Linux `struct inode` 约 600-800 字节（含文件系统私有数据）
- **适用场景**: 内存充足、属性访问模式不可预测
- **不适用场景**: 内存受限、只访问少量属性（如只需 size 和 mtime）

---

### 方案 B: 增量属性（NFS readdirplus）

**标杆来源**: [NFS attribute caching](https://gist.github.com/denji/8743267)

**原理**:
- 只缓存当前需要的属性子集，按需加载其他属性
- NFS readdirplus 在目录列举时批量返回子项的基本属性（type、size、mtime），避免后续逐个 getattr
- 核心思想：减少内存占用，同时通过批量操作减少 RPC 往返

**设计**:
- 数据结构：`struct nfs_fattr` 包含有效性位图 `valid`，标记哪些字段已缓存
- 批量接口：`READDIRPLUS` RPC 一次返回多个文件的属性
- 控制流：访问未缓存属性时触发 `GETATTR` RPC 补充，更新 `valid` 位图
- 接口形态：`nfs_getattr(inode, attr_mask)` 指定需要的属性，按需加载

**取舍**:
- **放大**: 内存效率（只缓存需要的属性）、批量操作性能（readdirplus 减少 RPC 次数）
- **牺牲**: 访问延迟（未缓存属性需二次查询）、实现复杂度（位图管理、部分失效）
- **量化数据**: readdirplus 可将 `ls -l` 的 RPC 次数从 O(n) 降至 O(1)
- **适用场景**: 内存受限、属性访问模式可预测（如只需 size 和 mtime）
- **不适用场景**: 属性访问模式随机、需要频繁访问全部属性

---

### 方案 C: 分层存储（热属性 + 冷属性分离）

**标杆来源**: [Cache line alignment](https://stackoverflow.com/questions/39971639/what-does-cacheline-aligned-mean), [Efficient metadata caching](https://www.researchgate.net/publication/266261579_MetaCache_Efficient_Metadata_Caching_in_Linux_file_system)

**原理**:
- 将频繁访问的热属性（size、mtime、mode）和冷属性（uid、gid、xattr）分离存储
- 热属性紧凑排列在缓存行对齐的结构体中，冷属性按需分配
- 核心思想：优化缓存行利用率，减少冷属性对热路径的污染

**设计**:
- 数据结构：
  - `struct hot_attr` (64 字节，缓存行对齐): `ino`, `size`, `mtime`, `mode`, `nlink`
  - `struct cold_attr` (可变大小): `uid`, `gid`, `atime`, `ctime`, `xattr`
- 内存布局：`hot_attr` 数组连续分配，`cold_attr` 按需分配并通过指针关联
- 控制流：热路径只访问 `hot_attr`，冷属性访问时检查指针是否为空，为空则加载
- 接口形态：`get_hot_attr(ino)` 返回热属性，`get_cold_attr(ino)` 按需加载冷属性

**取舍**:
- **放大**: 缓存行利用率（热属性紧凑排列，一次加载多个条目）、热路径性能
- **牺牲**: 实现复杂度（需分析属性访问频率）、冷属性访问延迟（需额外指针跳转）
- **量化数据**: 热属性 64 字节可容纳 8 个条目/缓存行，vs 完整 inode 800 字节只能容纳 1 个
- **适用场景**: 属性访问频率差异大、热路径性能敏感
- **不适用场景**: 属性访问频率均匀、实现复杂度不可接受

---

### 方案 D: 压缩存储（CephFS capability + 位图编码）

**标杆来源**: [CephFS MDS cache](https://docs.ceph.com/en/latest/cephfs/mdcache/)

**原理**:
- 使用位图编码能力（capabilities）和属性有效性，减少布尔字段占用
- 对于稀疏属性（如 xattr），使用变长编码或外部存储
- 核心思想：牺牲少量 CPU 开销换取内存占用降低

**设计**:
- 数据结构：
  - `caps`: 32 位位图，每位表示一种能力（FILE_RD、FILE_WR、FILE_CACHE 等）
  - `valid`: 32 位位图，标记哪些属性已缓存
  - `xattr`: 指向外部哈希表的指针，只在有 xattr 时分配
- 控制流：检查能力时位运算 `caps & CAP_FILE_RD`，访问 xattr 时检查指针非空
- 接口形态：`has_cap(inode, cap_mask)` 检查能力，`get_xattr(inode, name)` 按需加载

**取舍**:
- **放大**: 内存占用（位图 vs 布尔数组节省 8��空间）、稀疏属性内存效率
- **牺牲**: CPU 开销（位运算 vs 直接访问）、可读性（位图编码不如结构体字段直观）
- **量化数据**: 32 位位图可表示 32 种能力，vs 32 个 bool 字段占用 32 字节
- **适用场景**: 内存极度受限、属性种类多但大部分为空
- **不适用场景**: CPU 性能敏感、属性访问频率极高

---

## 标杆方案对比矩阵

### 维度 1.1: 缓存对象粒度

| 方案 | 路径解析性能 | 属性查询性能 | 内存占用 | 一致性支持 | 实现复杂度 | 典型应用 |
|------|------------|------------|---------|----------|----------|---------|
| Dentry 级 | ★★★★★ | ★★★☆☆ | ★★☆☆☆ | ★★★☆☆ | ★★★☆☆ | Linux VFS |
| Inode 级 | ★★☆☆☆ | ★★★★★ | ★★★☆☆ | ★★★★☆ | ★★☆☆☆ | NFS client |
| 混合缓存 | ★★★★☆ | ★★★★☆ | ★★☆☆☆ | ★★★★★ | ★★★★☆ | CephFS |
| 路径级 | ★★★★★ | ★★★★☆ | ★☆☆☆☆ | ★★☆☆☆ | ★★☆☆☆ | FUSE |

### 维度 1.2: 索引数据结构

| 方案 | 查找性能 | 范围查询 | 内存占用 | 缓存行利用率 | 实现复杂度 | 典型应用 |
|------|---------|---------|---------|------------|----------|---------|
| 哈希表 | ★★★★★ | ★☆☆☆☆ | ★★★☆☆ | ★★☆☆☆ | ★★☆☆☆ | Linux dcache |
| Radix Tree | ★★★★☆ | ★★★★★ | ★★★★☆ | ★★★☆☆ | ★★★★☆ | 路径前缀匹配 |
| B+Tree | ★★★☆☆ | ★★★★★ | ★★★☆☆ | ★★★★☆ | ★★★☆☆ | 有序遍历 |
| 多级索引 | ★★★★☆ | ★★☆☆☆ | ★★☆☆☆ | ★★☆☆☆ | ★★★★☆ | GlusterFS |

### 维度 1.3: 属性存储方式

| 方案 | 访问性能 | 内存占用 | 缓存行利用率 | 灵活性 | 实现复杂度 | 典型应用 |
|------|---------|---------|------------|-------|----------|---------|
| 完整副本 | ★★★★★ | ★★☆☆☆ | ★★☆☆☆ | ★★★☆☆ | ★★☆☆☆ | Linux VFS |
| 增量属性 | ★★★☆☆ | ★★★★☆ | ★★★☆☆ | ★★★★★ | ★★★★☆ | NFS |
| 分层存储 | ★★★★☆ | ★★★★☆ | ★★★★★ | ★★★☆☆ | ★★★★☆ | 性能优化 |
| 压缩存储 | ★★★☆☆ | ★★★★★ | ★★★★☆ | ★★★★☆ | ★★★★★ | CephFS |

---

## 关键 Trade-off 总结

### 1. 查找性能 vs 内存占用
- **哈希表**：O(1) 查找但内存占用高（需预分配大表）
- **Radix Tree**：O(k) 查找但内存占用低（公共前缀共享）
- **权衡点**：路径前缀重复度 >30% 时 Radix Tree 更优

### 2. 路径解析 vs 属性查询
- **Dentry 级**：优化路径解析，属性查询需额外跳转
- **Inode 级**：优化属性查询，路径解析需额外映射
- **权衡点**：路径解析占比 >60% 选 Dentry 级，<40% 选 Inode 级

### 3. 内存效率 vs 访问延迟
- **完整副本**：零延迟但内存占用高
- **增量属性**：内存占用低但可能需二次查询
- **权衡点**：内存受限且属性访问模式可预测时选增量

### 4. 缓存行利用率 vs 实现复杂度
- **分层存储**：高缓存行利用率但需分析访问模式
- **完整副本**：实现简单但缓存行浪费
- **权衡点**：热路径性能提升 >20% 时值得分层

---

## 适用性评估框架

选择方案时需考虑以下因素：

1. **工作负载特征**
   - 路径解析 vs 属性查询比例
   - 随机访问 vs 顺序访问
   - 读密集 vs 写密集

2. **资源约束**
   - 可用内存大小
   - CPU 性能预算
   - 缓存行大小（64 字节 vs 128 字节）

3. **一致性需求**
   - 强一致性（需能力机制）
   - 弱一致性（TTL 足够）
   - 最终一致性（失效通知）

4. **扩展性需求**
   - 是否需要硬链接
   - 是否需要范围查询
   - 是否需要前缀匹配

---

## 参考文献

- [Linux VFS Documentation](https://docs.kernel.org/6.0/filesystems/vfs.html)
- [CephFS Distributed Metadata Cache](https://docs.ceph.com/en/latest/cephfs/mdcache/)
- [Understanding NFS Caching](https://avidandrew.com/understanding-nfs-caching.html)
- [NFS Attribute Caching Performance Impact](https://gist.github.com/denji/8743267)
- [Adaptive Radix Tree Paper](https://www.researchgate.net/publication/261087784_The_adaptive_radix_tree_ARTful_indexing_for_main-memory_databases)
- [GlusterFS Inode Datastructure](https://gluster-documentations.readthedocs.io/en/latest/Developer-guide/datastructure-inode/)
- [Efficient Metadata Caching in Linux](https://www.researchgate.net/publication/266261579_MetaCache_Efficient_Metadata_Caching_in_Linux_file_system)
- [CephFS Distributed Metadata Cache Analysis](https://oneuptime.com/blog/post/2026-03-31-rook-distributed-metadata-cache-cephfs/view)
