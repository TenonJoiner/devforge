# coding-style — C 语言编码规范

## 适用范围

- `**/*.c`
- `**/*.h`

## 与通用规范的关系

- 本文件是 [coding-style.md](coding-style.md) 的 C 语言特化。通用原则（命名、错误处理、内存安全、并发、测试、日志、断言、安全）见父规范，此处仅细化 C 特有规则。
- 冲突时以本文件为准。

## 格式

- 使用 `clang-format` 自动格式化（LLVM 风格，由 hook 自动执行）
- 缩进：4 空格（Tab 宽度 4，文件内不使用 Tab）
- 行宽：100 字符
- 花括号：K&R 风格（函数定义换行，控制语句不换行）
- 指针声明：`int *p`（星号靠变量名）

## 命名

| 类型 | 规范 | 示例 |
|------|------|------|
| 函数 | `snake_case`，动词开头 | `wal_append_record` |
| 结构体/联合体 | `snake_case` + `_t` | `wal_record_t` |
| 枚举 | `snake_case` + `_e` | `wal_status_e` |
| 枚举值 | `SCREAMING_SNAKE_CASE` | `WAL_STATUS_OK` |
| 类型别名 | 与底层类型同名，后缀 `_t` | `wal_tid_t` |
| 宏/常量 | `SCREAMING_SNAKE_CASE` | `WAL_MAX_RECORD_SIZE` |
| 局部变量 | `snake_case` | `record_size` |
| 局部变量（布尔） | `is`/`has`/`can`/`should`/`needs` 前缀 | `is_valid` |
| 全局变量 | `g_` 前缀 | `g_wal_fd` |
| 静态全局变量 | `s_` 前缀 | `s_wal_cache` |
| 结构体成员 | `snake_case` | `record->data_len` |

- 禁止单字母变量（循环 `i`/`j`/`k` 除外）、匈牙利命名法、`_` 开头的标识符

## 头文件组织

- `.h`：对外接口、前向声明、宏常量、内联辅助函数
- `.c`：实现细节、静态函数、内部宏、全局变量定义
- 所有 `.h` 使用 `#pragma once` 或标准 include guard
- 包含顺序：同名 `.h`（优先）→ 系统头 `<>` → 项目公共头 `"` → 模块内部头 `"`
- `.h` 中优先前向声明，减少编译依赖；内部声明放入 `<module>_internal.h`

## 宏纪律

- 用 `static inline` 或枚举替代宏；宏仅用于：条件编译、字符串拼接、`offsetof`、属性包装
- 宏参数必须加括号：`#define SQUARE(x) ((x) * (x))`
- 多语句宏用 `do-while(0)`：
  ```c
  #define CLEANUP(ptr) do { free(ptr); (ptr) = NULL; } while (0)
  ```
- 禁止：宏内定义局部变量、无参数"宏函数"隐藏副作用、嵌套 >2 层

## 类型系统

- 禁止对指针类型使用 `typedef`（隐藏指针语义）
- 输入指针参数和局部变量尽可能 `const`；字符串字面量用 `const char *`
- 涉及二进制协议/持久化/网络时，优先使用 `<stdint.h>` 固定宽度类型
- 使用 `<stdbool.h>` 的 `bool`/`true`/`false`

## 内存管理

- 每次分配（`malloc`/`calloc`/`realloc` 或自定义分配器）必须在同一抽象层级有对应释放路径
- 分配返回值必须检查；失败返回错误码或 graceful 降级，禁止裸 `exit()`（初始化阶段除外）
- 禁止 `alloca`、VLA 大缓冲区、`realloc(ptr, 0)`；`free` 后置空是强制的
- 分配大小计算必须检查溢出：
  ```c
  if (nmemb > 0 && size > SIZE_MAX / nmemb) return -ENOMEM;
  void *p = calloc(nmemb, size);
  if (!p) return -ENOMEM;
  ```
- 自定义分配器（如 `mem_alloc`）必须全局统一使用，禁止混用 `malloc`/`free`
- 暴露数据结构指针给其他线程/持久化介质前，确保写入已完成（`memory_order_release`）；读取共享指针后用 `memory_order_acquire`

## 错误处理

- 每个函数返回值必须被检查或显式忽略：`(void)close(fd)`
- 返回 `int` 的函数：成功 0，失败返回负错误码；返回指针的函数：失败返回 `NULL`
- 同一模块内统一返回码风格
- 错误路径必须有日志记录或错误码传播（通用原则见父规范）
- `goto cleanup` 模式：
  ```c
  int wal_init(wal_t *wal) {
      int rc = 0;
      void *buf = NULL;
      int fd = -1;
      fd = open(wal->path, O_RDWR);
      if (fd < 0) { rc = -errno; goto cleanup; }
      buf = malloc(WAL_BUF_SIZE);
      if (!buf) { rc = -ENOMEM; goto cleanup; }
      wal->fd = fd; wal->buf = buf; return 0;
  cleanup:
      if (fd >= 0) (void)close(fd);
      free(buf); return rc;
  }
  ```
  - 只能有一个 `cleanup` 标签；跳转前设置好 `rc`；释放前检查有效性；禁止从 `cleanup` 再次 `goto`；释放函数返回值显式忽略

## 并发

- 锁的获取和释放必须在同一函数层级配对（通用原则见父规范）
- 多锁场景遵守全局一致性锁顺序；禁止持锁时调用可能再次获取锁的外部回调
- 优先使用 C11 `<stdatomic.h>`，原子操作内存顺序必须显式指定；复合原子操作（CAS 循环）正确处理 ABA 问题
- 无锁结构需有正确性证明或 TSan/helgrind 验证

## 安全

- 字符串操作优先 `snprintf`、`strlcpy`；禁止 `gets`/`strcpy`/`strcat`/`sprintf`
- `strncpy` 必须显式终止：`dst[n - 1] = '\0'`
- 格式化字符串必须是字符串字面量或经过校验，禁止用户输入直接作为 format 参数
- 分配大小计算使用 `size_t`，检查溢出；避免有符号与无符号混用比较
- 位运算操作数必须是无符号类型，禁止对有符号整数位移

## 热路径与性能

- 热路径禁止：`malloc`/`free`、无必要锁、系统调用（IO 路径除外）、日志记录、复杂分支链
- 性能关键分支使用 `__builtin_expect(cond, 1/0)`
- 频繁访问的共享数据结构考虑 `__attribute__((aligned(64)))`
- 热路径小型辅助函数标记 `static inline`；禁止将 >20 行或含复杂控制流的函数标记 `inline`

## 断言

- `assert` 只用于检测内部不变量；禁止用于用户输入、网络数据、磁盘 IO 等外部错误
- 发布版本 `assert` 可能被关闭，后续代码不能依赖其副作用

## 测试

- 使用 **cmocka**，测试函数命名：`test_<module>_<scenario>`
- 覆盖率要求见父规范（核心 ≥ 85%，新增 ≥ 95%）
- 每个测试独立，使用 `setup`/`teardown` 管理资源，禁止测试间泄漏

## 工具

- `clang-format`（hook 自动执行）、`clang-tidy`、`valgrind`
- **AddressSanitizer (ASan)**、**ThreadSanitizer (TSan)**、**MemorySanitizer (MSan)**

## 可移植性

- GCC/Clang 扩展属性封装到宏，非 GCC 编译器回退到空定义
- 涉及网络协议/持久化格式使用显式字节序转换（`htole64`/`le64toh` 等）
- 禁止头文件循环 `#include`；互相引用数据结构用前向声明
- 禁止通过不同类型指针访问同一内存（严格别名规则）；类型双关用 `union` 或显式 `memcpy`
- 编译必须开启 `-Wall -Wextra -Werror -Wstrict-prototypes -Wshadow -Wcast-align -Wmissing-prototypes`

## 构建与链接

- 默认所有符号 `static`，仅对外暴露的函数/变量显式导出
- 禁止依赖全局变量初始化顺序；使用显式 `module_init()`/`module_fini()`
- 禁止在 `.h` 中定义非 `static inline` 的函数或变量；全局变量 `extern` 声明在 `.h`，定义在唯一的 `.c`

## 提交前检查清单

- [ ] `clang-format` 已运行（hook 自动完成）
- [ ] `clang-tidy` 无新增警告
- [ ] 新分配都有释放路径，返回值已检查或显式忽略
- [ ] 锁在同一函数层级配对，热路径无新增 `malloc`/锁
- [ ] `goto cleanup` 符合规范（单一标签、前置 `rc`、释放返回值显式忽略）
- [ ] 新增代码有对应测试，覆盖率达标（见父规范）
- [ ] 无新增循环依赖，编译通过且 `-Wall -Wextra -Werror` 无警告
- [ ] 新增原子操作显式指定内存顺序，新增公共函数有原型声明（`.h` 中声明或 `static`）
- [ ] 注释与代码一致，无过期注释
- [ ] 格式化字符串非用户输入直接传入
- [ ] 无 `alloca`/VLA 大缓冲区，`free` 后置空
