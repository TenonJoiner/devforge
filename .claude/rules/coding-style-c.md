# R3 coding-style — C 语言编码规范

## 适用范围

`- **/*.c`
`- **/*.h`

## 与 clang-format 的关系

- **clang-format** 只处理纯语法格式（缩进、换行、空格、括号位置），由 H2 `post-edit-format` hook 自动执行，人工无需讨论。
- **本文件** 约束 `clang-format` 无法检查的语义与设计规则：命名、内存管理、错误处理、并发安全、头文件组织、宏纪律、性能原则等。

---

## 格式

- 使用 `clang-format` 自动格式化，配置基于 LLVM 风格
- 缩进：4 空格（Tab 宽度也设为 4，但文件内不使用 Tab 字符）
- 行宽：100 字符
- 花括号：K&R 风格
  - **函数定义**：开括号换行
  - **控制语句**（`if`/`for`/`while`/`switch`）：开括号不换行
- 指针声明：`int *p`（星号靠变量名）

---

## 命名

| 类型 | 规范 | 示例 |
|------|------|------|
| 函数 | `snake_case`，动词开头 | `wal_append_record` |
| 结构体/联合体 | `snake_case` + `_t` | `wal_record_t` |
| 枚举 | `snake_case` + `_e` | `wal_status_e` |
| 枚举值 | `SCREAMING_SNAKE_CASE`，可加前缀 | `WAL_STATUS_OK` |
| 类型别名 | 与底层类型同名，后缀 `_t` | `wal_tid_t` |
| 宏/常量 | `SCREAMING_SNAKE_CASE` | `WAL_MAX_RECORD_SIZE` |
| 局部变量 | `snake_case` | `record_size` |
| 全局变量 | `g_` 前缀 | `g_wal_fd` |
| 静态全局变量 | `s_` 前缀 | `s_wal_cache` |
| 结构体成员 | `snake_case` | `record->data_len` |

### 命名禁区
- 禁止单字母变量（循环变量 `i`/`j`/`k` 除外）
- 禁止匈牙利命名法
- 禁止 `_` 开头的标识符（保留给系统/编译器）

---

## 头文件组织

### `.h` 与 `.c` 的职责边界
- **`.h` 文件**：对外暴露的接口、数据结构前向声明、宏常量、内联辅助函数
- **`.c` 文件**：实现细节、静态函数、内部宏、全局变量定义

### include guard
所有 `.h` 文件必须使用 `#pragma once`，或标准 include guard：
```c
#ifndef MODULE_FILENAME_H
#define MODULE_FILENAME_H
/* ... */
#endif /* MODULE_FILENAME_H */
```

### 包含顺序
```c
#include 对应 .c 的同名 .h（优先）

#include <系统头文件>

#include "项目公共头文件"

#include "模块内部头文件"
```

- 系统头文件用 `<>`，项目头文件用 `""`
- 禁止在 `.h` 中无节制地包含其他 `.h`，优先使用前向声明减少编译依赖

### 内部头文件
仅供模块内部使用的声明放入 `<module>_internal.h`，不对外暴露。

---

## 宏的使用纪律

### 什么时候用宏，什么时候不用
- **用 `static inline` 替代宏**：简单的常量表达式、小型辅助函数
- **用枚举替代宏**：一组相关的离散常量
- **只能用宏的场景**：条件编译、编译期字符串拼接、`offsetof`、包装 `__attribute__`

### 宏编写安全规范
```c
/* 参数必须加括号 */
#define SQUARE(x) ((x) * (x))

/* 多语句宏必须用 do-while(0) */
#define CLEANUP(ptr)         \
    do {                     \
        free(ptr);           \
        (ptr) = NULL;        \
    } while (0)
```

### 禁止的宏反模式
- 🚩 宏内部定义局部变量（除非名字唯一且带前缀，避免隐藏变量）
- 🚩 无参数的"宏函数"隐藏副作用
- 🚩 宏嵌套过深（>2 层）

---

## 类型系统

### `typedef` 使用边界
- 对结构体、联合体、枚举使用 `typedef` 是推荐的
- **禁止**对指针类型使用 `typedef`（如 `typedef int* wal_int_p`），这会隐藏指针语义

### `const` 正确性
- 输入指针参数：如果能保证不修改，声明为 `const`
- 局部变量：如果能保证不修改，声明为 `const`
- 字符串字面量：使用 `const char *`

### 固定宽度整数
涉及二进制协议、持久化结构、网络传输时，优先使用 `<stdint.h>` 中的固定宽度类型：
- `uint32_t`、`int64_t`、`size_t`、`ssize_t`

### 布尔值
使用 `<stdbool.h>` 的 `bool`、`true`、`false`，而不是自定义宏。

---

## 内存管理

### 分配与释放配对
- 每次内存分配（`malloc`/`calloc`/`realloc` 或项目自定义分配器如 `mem_alloc`、`pool_alloc`、`slab_alloc`）都必须在同一抽象层级有对应的释放路径
- 禁止"跨层泄漏"：A 模块分配的内存交给 B 模块后，必须明确由谁负责释放

### 分配失败处理
- 所有分配函数返回值必须检查
- 分配失败必须返回错误码或触发 graceful 降级，禁止裸 `exit()`（除非初始化阶段且确实无法继续）

### 禁止的内存操作
- 禁止 `alloca` 和变长数组（VLA）作为大缓冲区
- 禁止 `realloc(ptr, 0)`（行为未定义，应显式 `free(ptr); ptr = NULL`）
- 禁止双重释放（`free` 后置空指针是强制的）

```c
free(ptr);
ptr = NULL;  /* 强制 */
```

---

## 错误处理

### 返回值检查铁律
**每个函数返回值必须被检查或显式忽略。**
```c
if (wal_write(wal, buf, len) < 0) {
    log_error("wal_write failed");
    return -EIO;
}

/* 显式忽略 */
(void)close(fd);
```

### 错误传播
- 错误路径必须有日志记录或错误码传播
- 禁止静默吞错（空的 `if` 分支、空的 `else`）
- 错误信息应包含上下文（文件名、偏移、errno 等）

### `goto cleanup` 规范
C 语言允许多出口统一清理，但必须遵守以下模式：
```c
int wal_init(wal_t *wal)
{
    int rc = 0;
    void *buf = NULL;
    int fd = -1;

    fd = open(wal->path, O_RDWR);
    if (fd < 0) {
        rc = -errno;
        goto cleanup;
    }

    buf = malloc(WAL_BUF_SIZE);
    if (!buf) {
        rc = -ENOMEM;
        goto cleanup;
    }

cleanup:
    if (rc < 0 && fd >= 0) {
        close(fd);
        wal->fd = -1;
    }
    free(buf);
    return rc;
}
```

**规范**：
- `cleanup` 标签只能有一个
- 跳转到 `cleanup` 前必须设置好 `rc`
- 释放资源前检查有效性（`fd >= 0`、`ptr != NULL`）
- 禁止从 `cleanup` 中再次 `goto` 到别处

---

## 并发

### 锁的配对原则
- 锁的获取和释放必须在**同一函数层级**配对
- 禁止跨函数边界持有锁（除非有显式的 lock/unlock API 且文档明确说明）

### 锁序（Lock Ordering）
- 如果必须同时持有多个锁，遵守全局定义的一致性锁顺序
- 禁止在持有锁时调用可能再次获取锁的外部回调函数（除非锁可重入）

### RAII 风格封装
优先使用辅助宏或 `__attribute__((cleanup))` 封装锁生命周期：
```c
/* 示例：使用 __attribute__((cleanup)) */
#define MUTEX_GUARD(mtx) __attribute__((cleanup(mutex_unlock_guard))) mutex_lock(mtx)
```

### 无锁结构
- 使用无锁结构前必须有充足的正确性证明或 TSan/helgrind 验证
- 禁止在热路径上为了代码简单而使用全局锁

---

## 安全

### 字符串与缓冲区
- 字符串操作使用 `strncpy`、`strncat`、`snprintf` 等长度限制版本
- 禁止 `gets`、`strcpy`、`strcat`、`sprintf`
- 使用 `strncpy` 后必须显式终止 `dst[n-1] = '\0'`

### 格式化字符串
- 格式化字符串必须是字符串字面量或经过严格校验
- 禁止用户输入直接作为 `printf`/`syslog` 的 format 参数

### 整数安全
- 分配大小计算使用 `size_t`，检查溢出：
```c
if (nmemb > 0 && size > SIZE_MAX / nmemb) {
    return -ENOMEM;  /* 溢出 */
}
void *p = calloc(nmemb, size);
```
- 避免有符号与无符号整数混用比较

---

## 热路径与性能

### 热路径禁止清单
- 🚩 `malloc` / `free`
- 🚩 无必要的锁
- 🚩 系统调用（`write`/`read` 除外，如果是 IO 热路径）
- 🚩 日志记录（除非能确认是罕见错误路径）
- 🚩 复杂的分支链（优先表驱动或提前返回）

### 分支预测提示
对性能关键的分支：
```c
if (__builtin_expect(cond, 1)) { /* likely */ }
if (__builtin_expect(cond, 0)) { /* unlikely */ }
```

### 缓存行对齐
频繁访问的共享数据结构考虑使用 `__attribute__((aligned(64)))` 避免 false sharing。

---

## 断言与不变量

### `assert` 的使用边界
- `assert` **只用于检测程序内部不变量**（不可能发生的情况）
- **禁止**用 `assert` 处理用户输入、网络数据、磁盘 IO 等外部错误
- 发布版本中 `assert` 可能被关闭，所以 `assert` 后的代码不能依赖其副作用

### 推荐模式
```c
/* 外部错误：必须处理 */
if (fd < 0) {
    return -errno;
}

/* 内部不变量：assert */
assert(wal->magic == WAL_MAGIC);
```

---

## 注释

### 必须加注释的场景
- 复杂的算法、非直观的性能优化
- 接口契约（参数是否可为 NULL、谁负责释放、调用时是否需要持有锁）
- 全局锁顺序、重要的并发假设
- `TODO` / `FIXME` / `XXX` 必须附带上下文说明或后续 task 引用

### 禁止的注释
- 解释"代码在做什么"（What）而非"为什么这样做"（Why）
- 与代码明显不一致的过期注释
- 无意义的任务编号注释（如 `// task-1234`）

---

## 可移植性

### 编译器属性封装
将 GCC/Clang 扩展属性封装到宏中，非 GCC 编译器可回退到空定义：
```c
#ifndef __GNUC__
#define __attribute__(x)
#endif

#define WAL_HOT __attribute__((hot))
#define WAL_COLD __attribute__((cold))
#define WAL_ALIGNED(x) __attribute__((aligned(x)))
```

### 字节序
涉及网络协议或持久化格式时，使用显式的字节序转换函数（`htole64`/`le64toh` 等），不要依赖宿主机的字节序。

---

## 提交前检查清单

在 `git commit` 前确认：
- [ ] `clang-format` 已运行（H2 hook 自动完成）
- [ ] 新引入的内存分配都有释放路径
- [ ] 所有函数返回值已被检查或显式忽略
- [ ] 锁的获取和释放在同一函数层级配对
- [ ] 热路径上没有新增 `malloc` 或锁
- [ ] `goto cleanup` 模式符合规范（单一标签、前置设置 rc）
