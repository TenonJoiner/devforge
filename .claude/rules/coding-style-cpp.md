# R3 coding-style-cpp — C++ 编码规范

> **状态**：初版框架，待完善。参考 [Google C++ Style Guide](https://google.github.io/styleguide/cppguide.html)

## 适用范围

本文件定义 C++ 语言特定的编码规范。通用规范见 [coding-style.md](coding-style.md)。

## 核心原则

1. **RAII**：资源获取即初始化，使用智能指针管理资源
2. **避免裸指针**：优先使用 unique_ptr/shared_ptr
3. **异常安全**：保证基本异常安全或强异常安全
4. **模板使用边界**：避免过度模板化，保持代码可读性

## 命名规范

- 函数：snake_case
- 类/结构体：PascalCase
- 成员变量：snake_case_（后缀下划线）
- 常量：kPascalCase

## 内存管理

- 优先使用 std::unique_ptr
- 共享所有权使用 std::shared_ptr
- 避免 std::auto_ptr（已废弃）
- 使用 make_unique/make_shared

## 并发

- 使用 std::mutex + std::lock_guard
- 避免手动 lock/unlock
- 使用 std::atomic 处理原子操作

## 测试

- 框架：gtest 或 catch2
- 命名：TEST(Module, Scenario)

## 工具链

- 格式化：clang-format
- 静态分析：clang-tidy
- 内存检查：valgrind / AddressSanitizer

---

**TODO**：补充详细规范和示例
