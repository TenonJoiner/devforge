# R3 coding-style-go — Go 编码规范

> **状态**：初版框架，待完善。参考 [Effective Go](https://go.dev/doc/effective_go)

## 适用范围

本文件定义 Go 语言特定的编码规范。通用规范见 [coding-style.md](coding-style.md)。

## 核心原则

1. **简洁性**：保持代码简单直接
2. **接口设计**：小接口，组合优于继承
3. **错误处理**：显式检查 error 返回值
4. **并发**：使用 goroutine 和 channel

## 命名规范

- 函数/变量（私有）：camelCase
- 函数/变量（公开）：PascalCase
- 包名：小写单词，无下划线
- 接口：单方法接口以 -er 结尾

## 内存管理

- GC 自动管理
- 避免不必要的指针
- 使用 sync.Pool 复用对象

## 并发

- 优先使用 channel
- 使用 sync.Mutex 保护共享状态
- 使用 sync.WaitGroup 等待 goroutine

## 测试

- 框架：内置 testing
- 命名：TestXxx(t *testing.T)
- 基准测试：BenchmarkXxx(b *testing.B)

## 工具链

- 格式化：gofmt / goimports
- 静态分析：golangci-lint
- 竞态检测：go test -race

---

**TODO**：补充详细规范和示例
