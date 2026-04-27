# R3 coding-style-python — Python 编码规范

> **状态**：初版框架，待完善。参考 [PEP 8](https://peps.python.org/pep-0008/)

## 适用范围

本文件定义 Python 语言特定的编码规范。通用规范见 [coding-style.md](coding-style.md)。

## 核心原则

1. **可读性**：代码应该易于阅读和理解
2. **显式优于隐式**：明确表达意图
3. **简单优于复杂**：避免过度设计
4. **类型提示**：使用类型注解提高代码质量

## 命名规范

- 函数/变量：snake_case
- 类：PascalCase
- 常量：SCREAMING_SNAKE_CASE
- 私有成员：_leading_underscore

## 内存管理

- GC 自动管理
- 避免循环引用
- 使用 with 语句管理资源

## 并发

- 使用 threading.Lock + with 语句
- 考虑 GIL 限制
- 使用 multiprocessing 处理 CPU 密集任务

## 测试

- 框架：pytest 或 unittest
- 命��：test_<scenario>
- 使用 fixtures 管理测试数据

## 工具链

- 格式化：black
- 静态分析：pylint / flake8
- 类型检查：mypy

---

**TODO**：补充详细规范和示例
