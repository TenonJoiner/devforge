# R3 coding-style-rust — Rust 编码规范

> **状态**：初版框架，待完善。参考 [Rust API Guidelines](https://rust-lang.github.io/api-guidelines/)

## 适用范围

本文件定义 Rust 语言特定的编码规范。通用规范见 [coding-style.md](coding-style.md)。

## 核心原则

1. **所有权系统**：理解并正确使用所有权、借用、生命周期
2. **类型安全**：利用类型系统表达约束
3. **错误处理**：使用 Result<T, E>，避免 panic
4. **unsafe 边界**：最小化 unsafe 代码，明确不变量

## 命名规范

- 函数/变量：snake_case
- 类型/Trait：PascalCase
- 常量：SCREAMING_SNAKE_CASE
- 生命周期：'a, 'b（小写单字母）

## 内存管理

- 所有权系统自动管理
- 使用 Box/Rc/Arc 处理堆分配
- 避免不必要的 clone

## 并发

- 使用 Mutex<T> + Arc
- 类型系统保证线程安全（Send/Sync）
- 使用 channel 传递消息

## 测试

- 框架：内置 #[test]
- 模块：#[cfg(test)] mod tests
- 命名：test_<scenario>

## 工具链

- 格式化：rustfmt
- 静态分析：clippy
- 内存检查：miri（unsafe 代码）

---

**TODO**：补充详细规范和示例
