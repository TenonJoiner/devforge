# Defense-in-Depth — 多层验证

## 概述

当你修复由无效数据引起的 bug 时，只在一处添加验证感觉就够了。但单个检查可能被不同的代码路径、重构或并发竞态绕过。

**核心原则**：在数据流经的每一层都添加验证，让 bug 在结构上不可能发生。

## 为什么需要多层

单层验证："我们修复了 bug"
多层验证："我们让 bug 不可能发生"

不同层捕获不同场景：
- 入口校验捕获大多数 bug
- 业务逻辑捕获边界情况
- 不变量断言捕获并发竞态和状态机违规
- 调试日志在其他层失败时提供取证信息

## 四层验证

### Layer 1: 入口校验
**目的**：在 API 边界拒绝明显无效的输入

```c
int wal_open(wal_t *wal, const char *path, const wal_config_t *cfg)
{
    if (!path || path[0] == '\0') {
        log_error("wal_open: path cannot be empty");
        return -EINVAL;
    }
    if (!cfg || cfg->segment_size == 0 || cfg->segment_size > WAL_MAX_SEGMENT_SIZE) {
        log_error("wal_open: invalid segment_size=%zu", cfg ? cfg->segment_size : 0);
        return -EINVAL;
    }
    if (cfg->replication_factor < 1 || cfg->replication_factor > WAL_MAX_REPLICAS) {
        log_error("wal_open: replication_factor=%d out of range [1, %d]",
                  cfg->replication_factor, WAL_MAX_REPLICAS);
        return -EINVAL;
    }
    /* ... proceed */
}
```

### Layer 2: 业务逻辑校验
**目的**：确保数据对此操作有意义

```c
int wal_append_record(wal_t *wal, const void *data, size_t len)
{
    if (wal->state != WAL_STATE_OPEN) {
        log_error("wal_append: wal state=%d, expected OPEN", wal->state);
        return -ESTALE;
    }
    if (wal->write_offset + len > wal->active_seg->capacity) {
        /* 需要段切换，但这里只验证 */
        log_warn("wal_append: record len=%zu exceeds remaining capacity=%zu",
                 len, wal->active_seg->capacity - wal->write_offset);
    }
    /* ... proceed */
}
```

### Layer 3: 不变量断言
**目的**：捕获并发竞态和状态机违规

```c
static void wal_rotate_segment(wal_t *wal)
{
    /* 不变量：段切换时不应有 pending flush */
    assert(wal->pending_flushes == 0);

    /* 不变量：当前段必须已关闭 */
    assert(wal->active_seg->state == SEG_STATE_CLOSED);

    /* 不变量：写偏移量必须对齐 */
    assert(wal->write_offset % WAL_RECORD_ALIGNMENT == 0);

    /* ... proceed with rotation */
}
```

### Layer 4: 调试日志
**目的**：为取证捕获上下文

```c
static int wal_write_segment(wal_t *wal, int fd, const void *buf, size_t len, off_t offset)
{
    log_debug("WAL write: seg=%05u fd=%d offset=%lu len=%zu pending_flushes=%d "
              "state=%d caller=%p",
              wal->active_seg->seq, fd, (unsigned long)offset, len,
              wal->pending_flushes, wal->state,
              __builtin_return_address(0));

    int rc = pwrite(fd, buf, len, offset);
    /* ... */
}
```

## 应用模式

找到 bug 后：

1. **追溯数据流** — 坏值从哪产生？在哪里使用？
2. **映射所有检查点** — 列出数据流经的每个点
3. **在每一层添加验证** — 入口、业务逻辑、不变量、调试日志
4. **测试每一层** — 尝试绕过 Layer 1，验证 Layer 2 能捕获

## 真实案例

Bug：段切换竞态导致 WAL 写入不存在的段文件

**数据流：**
1. 刷盘完成回调 → `pending_flushes` 递减
2. 条件判断 `>= 0`（应为 `== 0`）→ 过早触发段切换
3. `wal_rotate_segment()` 在刷盘进行中被调用
4. 新段尚未创建，`pwrite` 在无效 fd 上写入 → EIO

**添加的四层：**
- Layer 1: `wal_rotate_segment()` 前断言 `pending_flushes == 0`
- Layer 2: `wal_append_record()` 验证 fd 有效性，否则拒绝写入
- Layer 3: 段切换时加写屏障，确保新段创建可见后再唤醒写入者
- Layer 4: 段状态机日志，记录每次状态转换和触发条件

**结果**：段切换竞态彻底消除，零回归

## 关键洞察

四层都是必要的。测试期间，每一层都捕获了其他层漏掉的 bug：
- 不同线程的写入路径绕过了入口校验
- 并发回调绕过了业务逻辑检查
- 条件变量竞态需要不变量断言
- 调试日志发现了时序上的结构性问题

**不要只在一个验证点停止。** 在每一层都添加检查。
