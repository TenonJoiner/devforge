# R3 coding-style — 通用编码规范

## 适用范围

本文件定义**跨语言通用**的编码规范原则。语言特定的规范见：
- C 语言：[coding-style-c.md](coding-style-c.md)
- C++：[coding-style-cpp.md](coding-style-cpp.md)
- Rust：[coding-style-rust.md](coding-style-rust.md)
- Go：[coding-style-go.md](coding-style-go.md)
- Python：[coding-style-python.md](coding-style-python.md)
- Java：[coding-style-java.md](coding-style-java.md)

## 规范选择机制

**自动选择**：
- Agent 在执行代码级 skill 时，读取 `.claude/domain-config.yaml` 中的 `languages.primary`
- 根据主语言自动加载对应的语言特定规范
- 如果有多个主语言，按优先级加载（第一个为主，其他为辅）

**手动覆盖**：
- 用户可以在 skill 调用时指定语言：`/df:tdd --lang=rust`
- 或在 worktree 中创建 `.language` 文件指定当前上下文的语言

## 通用原则

### 1. 命名

**通用规则**（所有语言）：
- 禁止单字母变量（循环变量 i/j/k 除外）
- 禁止匈牙利命名法
- 名称应自解释，避免缩写（除非是领域通用缩写）
- 布尔变量使用 is/has/can/should 前缀

**语言特定**：
- C/C++：snake_case（函数）、PascalCase（类型）
- Rust：snake_case（函数/变量）、PascalCase（类型/trait）
- Go：camelCase（私有）、PascalCase（公开）
- Python：snake_case（函数/变量）、PascalCase（类）
- Java：camelCase（方法/变量）、PascalCase（类）

### 2. 错误处理

**通用规则**：
- 所有可能失败的操作必须有错误处理
- 禁止静默吞错
- 错误信息应包含上下文（操作、参数、原因）
- 区分可恢复错误和不可恢复错误

**语言特定**：
- C：返回错误码 + errno，调用者必须检查返回值
- C++：异常或 std::expected，RAII 保证资源释放
- Rust：Result<T, E>，? 操作符传播错误
- Go：error 返回值，if err != nil 检查
- Python：异常，try-except-finally
- Java：受检异常 + 非受检异常

### 3. 内存安全

**通用规则**：
- 分配与释放必须配对
- 禁止悬垂指针/引用
- 禁止数据竞争
- 禁止缓冲区溢出

**语言特定**：
- C：手动管理 + valgrind 检查，使用 malloc/free 配对
- C++：RAII + unique_ptr/shared_ptr，避免裸指针
- Rust：所有权系统 + 借用检查器，编译期保证
- Go：GC + race detector，避免 unsafe
- Python：GC，避免循环引用
- Java：GC，避免内存泄漏（如未关闭的资源）

### 4. 并发安全

**通用规则**：
- 共享状态必须有同步保护
- 锁的获取和释放必须配对
- 避免死锁（锁序、超时、trylock）
- 最小化临界区

**语言特定**：
- C：pthread_mutex + 手动管理，注意锁序
- C++：std::mutex + RAII guard（lock_guard/unique_lock）
- Rust：Mutex<T> + 类型系统保证，Send/Sync trait
- Go：channel + sync.Mutex，优先使用 channel
- Python：threading.Lock + with 语句
- Java：synchronized + Lock 接口

### 5. 测试

**通用规则**：
- 核心模块覆盖率 ≥ 85%
- 新增代码覆盖率 ≥ 95%
- 测试必须可重复、可隔离
- 测试名称应描述测试场景

**语言特定**：
- C：cmocka，测试函数命名 test_<module>_<scenario>
- C++：gtest / catch2，TEST(Module, Scenario)
- Rust：内置 #[test]，#[cfg(test)] mod tests
- Go：内置 testing，TestXxx(t *testing.T)
- Python：pytest / unittest，test_<scenario>
- Java：JUnit，@Test void testScenario()

## 格式化工具

| 语言 | 格式化工具 | 配置文件 | 说明 |
|------|-----------|---------|------|
| C | clang-format | .clang-format | 基于 LLVM 风格 |
| C++ | clang-format | .clang-format | 基于 LLVM 风格 |
| Rust | rustfmt | rustfmt.toml | 官方工具 |
| Go | gofmt / goimports | - | 官方工具，无需配置 |
| Python | black | pyproject.toml | 无妥协的格式化器 |
| Java | google-java-format | - | Google 风格 |

## 静态分析工具

| 语言 | Linter | 配置文件 | 说明 |
|------|--------|---------|------|
| C | clang-tidy | .clang-tidy | 静态分析 + 代码检查 |
| C++ | clang-tidy | .clang-tidy | 静态分析 + 代码检查 |
| Rust | clippy | - | 官方 linter |
| Go | golangci-lint | .golangci.yml | 集成多个 linter |
| Python | pylint / flake8 | .pylintrc / .flake8 | 代码质量检查 |
| Java | SpotBugs / Checkstyle | - | 静态分析 |

## 内存检查工具

| 语言 | 工具 | 用途 |
|------|------|------|
| C | valgrind | 内存泄漏、越界访问 |
| C | AddressSanitizer (asan) | 内存错误检测 |
| C++ | valgrind / asan | 同 C |
| Rust | miri | unsafe 代码检查 |
| Go | race detector | 数据竞争检测 |
| Python | memory_profiler | 内存使用分析 |
| Java | VisualVM / JProfiler | 内存泄漏分析 |

## 代码审查清单

### 通用检查项

- [ ] 命名是否自解释？
- [ ] 错误处理是否完备？
- [ ] 是否有内存泄漏风险？
- [ ] 是否有并发安全问题？
- [ ] 测试覆盖率是否达标？
- [ ] 是否有明显的性能问题？
- [ ] 代码是否符合语言特定规范？

### 语言特定检查项

参见各语言的 coding-style-<lang>.md 文件。

## 参考资料

- C：[Linux Kernel Coding Style](https://www.kernel.org/doc/html/latest/process/coding-style.html)
- C++：[Google C++ Style Guide](https://google.github.io/styleguide/cppguide.html)
- Rust：[Rust API Guidelines](https://rust-lang.github.io/api-guidelines/)
- Go：[Effective Go](https://go.dev/doc/effective_go)
- Python：[PEP 8](https://peps.python.org/pep-0008/)
- Java：[Google Java Style Guide](https://google.github.io/styleguide/javaguide.html)
