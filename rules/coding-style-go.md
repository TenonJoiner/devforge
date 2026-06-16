# coding-style-go — Go 编码规范

父规范：[coding-style.md](coding-style.md)。通用原则（命名、错误处理、内存安全、并发、测试、日志、断言、安全）遵循父规范；Go 特有规则以本文件为准。

## 命名规范

| 类别 | 规范 | 示例 |
|------|------|------|
| 包名 | 小写单词，无下划线 | `package userauth` |
| 私有函数/变量 | camelCase | `processRequest`, `maxRetries` |
| 公开函数/变量 | PascalCase | `ProcessRequest`, `MaxRetries` |
| 常量 | 驼峰（公开 PascalCase，私有 camelCase） | `MaxBufferSize`, `defaultTimeout` |
| 类型 | PascalCase | `RequestHandler`, `UserStore` |
| 接口 | 单方法以 `-er` 结尾；多方法用描述性名词 | `Reader`, `CacheManager` |
| 文件命名 | snake_case 描述内容 | `user_handler.go` |
| 测试文件 | 以 `_test.go` 结尾 | `user_handler_test.go` |
| 布尔变量 | `is`/`has`/`can`/`should`/`needs` 前缀 | `isReady`, `hasError` |
| 错误变量 | 以 `Err` 开头 | `ErrNotFound`, `ErrInvalidInput` |

> Go 常量使用驼峰命名，与父规范 `SCREAMING_SNAKE_CASE` 不同。Go 项目遵循本文件规则。

## 错误处理

- 所有返回 `error` 的函数调用必须检查返回值
- 禁止静默吞错（`_ = someFunc()` 仅在资源关闭等无后续逻辑依赖时允许）
- 使用 `fmt.Errorf("...: %w", err)` 包装错误，保留错误链；用 `errors.Is` 判断、`errors.As` 提取具体错误类型
- 区分可恢复错误和不可恢复错误（后者使用 `log.Fatal` 或 `panic` 仅在初始化阶段）

```go
result, err := doSomething()
if err != nil {
    return fmt.Errorf("failed to do something with %q: %w", param, err)
}
if errors.Is(err, ErrNotFound) { ... }
```

## 内存管理

- 依赖 GC，避免手动管理内存
- 小结构体（≤64 字节）直接传值；`[]byte` 和 `map` 本身已是引用类型
- 使用 `sync.Pool` 复用高频分配的临时对象，**Put 前必须重置对象状态**
- 谨慎使用 `unsafe`：仅在经过充分测试的性能关键路径使用，禁止绕过类型安全进行业务逻辑判断
- 谨慎使用 `reflect`：禁止在热路径或安全关键逻辑中使用，优先用类型断言或 code generation
- 避免循环引用（channel 或 goroutine 持有对象引用导致无法 GC）

## defer 使用规范

- 资源释放（`Close`、`Unlock`）使用 `defer` 保证执行，即使后续代码出错
- `defer` 语句紧跟资源获取，不延迟到函数末尾
- `defer` 中的函数参数在注册时求值，注意闭包变量与传参的区别
- `defer` 中调用返回 `error` 的函数会忽略错误；若需处理，在函数末尾显式关闭并检查

```go
f, err := os.Open("file.txt")
if err != nil { return err }
defer f.Close()

// 需要处理关闭错误时
func processFile(path string) (err error) {
    f, err := os.Open(path)
    if err != nil { return err }
    defer func() {
        if cerr := f.Close(); cerr != nil && err == nil {
            err = fmt.Errorf("close file: %w", cerr)
        }
    }()
    // ...
}
```

## panic 与恢复

- `panic` 仅用于不可恢复的编程错误（数组越界、空指针解引用）或初始化失败
- 禁止在业务逻辑中使用 `panic` 作为错误处理手段
- **库代码禁止 `panic`，必须返回 `error`**
- 顶层服务可使用 `recover` 捕获 panic 防止进程崩溃，但须记录日志并优雅降级

```go
func handleRequest(w http.ResponseWriter, r *http.Request) {
    defer func() {
        if rec := recover(); rec != nil {
            log.Printf("panic recovered: %v\n%s", rec, debug.Stack())
            http.Error(w, "internal error", http.StatusInternalServerError)
        }
    }()
    process(r)
}
```

## 代码组织

- 一个文件只负责一个核心概念；文件超过 500 行应审视是否可拆分
- 包名反映职责，不反映层级（`userauth` 而非 `handlers/userauth`）
- 包内文件按职责命名，**禁止堆砌到 `utils.go`**
- **避免 `init()` 函数**；如有必要（如注册表模式），必须文档说明副作用和依赖顺序
- 公开 API 放在包根文件，内部实现放在子文件
- 包级变量使用 `var` 声明并考虑并发安全性；配置类变量应在初始化时设置，运行时不修改
- **禁止循环导入**

## 并发

- 优先使用 channel 进行 goroutine 间通信（"通过通信共享内存"）
- 使用 `sync.Mutex` 保护共享状态；读多写少时优先使用 `sync.RWMutex`，但注意写锁饥饿
- 使用 `sync.WaitGroup` 等待一组 goroutine 完成
- 使用 `context.Context` 控制 goroutine 生命周期和取消
- 避免 goroutine 泄漏：确保每个启动的 goroutine 都有退出路径
- 使用 `atomic` 包处理简单的计数器/标志位，避免锁开销
- **channel 由发送方关闭，禁止重复关闭**；接收方使用 `for range` 或 `v, ok := <-ch` 检测关闭
- **禁止在持有锁时调用可能阻塞的操作**（IO、channel 发送、外部回调）

```go
var wg sync.WaitGroup
for _, item := range items {
    wg.Add(1)
    go func(i Item) { defer wg.Done(); process(i) }(item)
}
wg.Wait()

ctx, cancel := context.WithTimeout(parentCtx, 5*time.Second)
defer cancel()
result, err := doWork(ctx)
```

## Context 使用规范

- 函数需要取消/超时/传递请求元数据时，**第一个参数必须是 `ctx context.Context`**
- `context.Background()` 仅用于 `main`、初始化、测试顶层；`context.TODO()` 仅用于占位待确定场景
- **禁止将 `context.Context` 存储在 struct 中**；应作为参数逐层传递
- **禁止传递 `nil` context**；若不确定，用 `context.Background()`
- 派生 context（`WithTimeout`、`WithCancel`、`WithValue`）必须及时调用 `cancel()` 避免 goroutine 泄漏

```go
func QueryDatabase(ctx context.Context, db *sql.DB, query string) (*sql.Rows, error) {
    return db.QueryContext(ctx, query)
}
```

## 测试

- 框架：内置 `testing`
- 覆盖率阈值遵循父规范（核心模块 ≥ 85%，新增代码 ≥ 95%）
- 优先使用 table-driven 模式组织测试用例
- 测试辅助函数使用 `t.Helper()`
- 大型测试数据放在 `testdata/` 目录下，Go 工具链自动忽略

```go
func TestProcessRequest(t *testing.T) {
    tests := []struct {
        name    string
        input   string
        want    string
        wantErr bool
    }{
        {name: "valid", input: "hello", want: "HELLO"},
        {name: "empty", input: "", wantErr: true},
    }
    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            got, err := ProcessRequest(tt.input)
            if tt.wantErr {
                if err == nil { t.Fatalf("expected error") }
                return
            }
            if err != nil { t.Fatalf("unexpected error: %v", err) }
            if got != tt.want { t.Fatalf("got %q, want %q", got, tt.want) }
        })
    }
}
```

## 工具链

| 工具 | 用途 |
|------|------|
| `gofmt` | 官方格式化，无需配置，必须运行 |
| `goimports` | 自动管理 import，排序并移除未使用的 import |
| `golangci-lint` | 集成多个 linter，关键启用项：`errcheck`、`govet`、`staticcheck`、`bodyclose`、`noctx`、`rowserrcheck` |
| `go test -race` | 竞态检测，CI 中必须启用 |

**典型 CI 检查流程**：
```bash
gofmt -l .
go vet ./...
go test -race ./...
go mod tidy
golangci-lint run
```

## 性能热路径

- 热路径禁止：动态内存分配、无必要锁、阻塞式系统调用、日志记录、`reflect`、`fmt.Sprintf`
- 避免 `time.Now()` 高频调用，必要时缓存时间或使用单调时钟
- 避免字符串与 `[]byte` 的重复转换，使用 `bytes` 包操作缓冲区
- 预分配 slice/map 容量，避免多次扩容
- 使用 `strings.Builder` 替代 `+=` 拼接字符串
- 禁止循环中使用 `time.After`（每次创建新 Timer 导致内存泄漏），改用 `time.NewTicker` + `defer ticker.Stop()`

```go
result := make([]int, 0, len(input))

var b strings.Builder
b.Grow(expectedLen)
for _, s := range items { b.WriteString(s) }
result := b.String()
```

## 接口与依赖

- 接口由消费者定义，不由生产者预先定义（Go 惯例）
- 接口保持小（0-3 个方法），职责单一
- 使用接口实现编译期检查：`var _ MyInterface = (*MyStruct)(nil)`
- 依赖注入通过构造函数参数传递接口，禁止全局变量持有可替换依赖

## 代码审查清单（Go 特定，≤15 项）

- [ ] 命名是否符合 Go 惯例（PascalCase/camelCase，接口 `-er` 后缀）？
- [ ] 错误是否全部检查，是否使用 `%w` 包装保留错误链？
- [ ] 是否有 goroutine 泄漏风险？并发访问共享状态是否受保护？
- [ ] 是否使用 `context` 控制生命周期？ctx 是否作为第一个参数传递？
- [ ] 是否优先使用 table-driven 测试？
- [ ] 是否运行 `gofmt`、`go vet`、`-race`、`go mod tidy`？
- [ ] `defer` 是否紧跟资源获取？`panic` 是否仅用于不可恢复错误？
- [ ] 是否有无文档的 `init()` 函数或 `utils.go` 大杂烩？
- [ ] 循环中启动的 goroutine 是否正确捕获循环变量？
- [ ] `sync.Pool` 复用对象是否重置状态？热路径是否避免 `reflect`、`fmt.Sprintf`？
- [ ] channel 关闭是否由发送方负责，是否有重复关闭风险？
- [ ] 是否使用 `atomic` 替代锁处理简单计数器？依赖注入是否通过构造函数？
- [ ] 是否有不必要的指针使用（小结构体可传值）？
- [ ] `unsafe` 和 `reflect` 使用是否经过充分论证，是否避开热路径？
- [ ] 是否遵循父规范通用原则（命名、错误处理、内存安全、并发、测试、日志）？
