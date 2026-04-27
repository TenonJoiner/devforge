# R3 coding-style-java — Java 编码规范

> **状态**：初版框架，待完善。参考 [Google Java Style Guide](https://google.github.io/styleguide/javaguide.html)

## 适用范围

本文件定义 Java 语言特定的编码规范。通用规范见 [coding-style.md](coding-style.md)。

## 核心原则

1. **面向对象**：合理使用继承和多态
2. **异常处理**：区分受检异常和非受检异常
3. **资源管理**：使用 try-with-resources
4. **并发**：使用 java.util.concurrent 包

## 命名规范

- 方法/变量：camelCase
- 类/接口：PascalCase
- 常量：SCREAMING_SNAKE_CASE
- 包名：小写，点分隔

## 内存管理

- GC 自动管理
- 避免内存泄漏（未关闭的资源）
- 使用 try-with-resources 管理资源

## 并发

- 使用 synchronized 或 Lock 接口
- 使用 java.util.concurrent 工具类
- 避免死锁

## 测试

- 框架：JUnit
- 命名：@Test void testScenario()
- 使用 @Before/@After 管理测试状态

## 工具链

- 格式化：google-java-format
- 静态分析：SpotBugs / Checkstyle
- 内存分析：VisualVM / JProfiler

---

**TODO**：补充详细规范和示例
