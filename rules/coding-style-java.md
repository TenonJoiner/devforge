# coding-style-java — Java 编码规范

> 参考 [Google Java Style Guide](https://google.github.io/styleguide/javaguide.html) 与 Java 17+ / LTS 最佳实践。  
> 通用规范（命名、错误处理、内存安全、并发、测试、日志、断言、安全）见 [coding-style.md](coding-style.md)。

## 核心原则

1. **面向对象设计**：组合优于继承；接口优于抽象类；不可变类声明为 `final`。
2. **异常处理**：受检异常用于可恢复的外部错误；非受检异常用于编程错误；禁止空 catch 块。
3. **资源管理**：所有 `AutoCloseable` 资源使用 try-with-resources。
4. **并发安全**：使用 `java.util.concurrent` 替代裸 `synchronized`；共享可变状态通过同步或不可变性保护。
5. **Null 安全**：公共 API 明确 null 契约；内部实现优先使用空集合 / `Optional` 替代 null 传播。

## 命名规范

| 元素 | 规则 | 示例 |
|------|------|------|
| 类 / 接口 | PascalCase，名词短语 | `UserRepository`, `ConnectionFactory` |
| 方法 | camelCase，动词短语 | `findById`, `processPayment` |
| 变量 | camelCase，自解释，禁止缩写（`id`、`url` 等除外），禁止单字母（循环 `i`/`j`/`k` 除外） | `customerName`, `maxRetries` |
| 布尔变量 | `is`/`has`/`can`/`should`/`needs` 前缀 | `isActive`, `hasPermission` |
| 集合变量 | 复数名词，禁止 `List`/`Map` 后缀 | `users`, `orderItems` |
| 常量 / 枚举值 | `SCREAMING_SNAKE_CASE` | `MAX_BUFFER_SIZE`, `Status.PENDING` |
| 泛型参数 | 单个大写字母或描述性名称 | `T`, `E`, `K`, `V`, `InputT` |
| 包名 | 全小写，反向域名 | `com.example.project.service` |
| 测试类 | 被测类名 + `Test` | `UserServiceTest` |
| 测试方法 | camelCase，描述场景与预期 | `shouldThrowWhenUserNotFound` |

## 异常与错误处理

- **受检异常**：仅用于调用者可合理恢复的场景（IO 失败、网络超时）。
- **非受检异常**：用于编程错误、前置条件违反（`IllegalArgumentException`, `IllegalStateException`）。
- **禁止吞错**：catch 块必须处理、记录或重新抛出；空 catch 块必须注释说明原因。
- **保留 cause**：底层异常转换时保留原始异常：`throw new ServiceException("Failed to load user " + id, e)`。
- **API 边界**：统一转换为对外友好错误码，禁止将内部堆栈直接暴露给外部调用者。
- **前置条件**：公共方法入口使用 `Objects.requireNonNull()` 或显式 `if` 检查参数合法性。

## 资源管理与内存安全

- **try-with-resources**：所有 `AutoCloseable` 资源必须使用 try-with-resources；多个资源按声明顺序自动关闭。
- **避免内存泄漏**：集合移除对象时同步清理关联监听器/回调；缓存使用 `WeakReference` 或 `Caffeine`/`Guava Cache`（配置最大容量和过期策略）；线程池/定时器在组件销毁时显式 `shutdown()` + `awaitTermination()`。
- **禁止 `finalize()`**：使用 `PhantomReference` + `ReferenceQueue` 或 try-with-resources 替代。
- **大对象处理**：优先使用 `Stream`/`Iterator` 或分页加载，禁止一次性加载到内存。
- **热路径内存**：延迟敏感的热路径禁止在循环内创建临时对象（`String` 拼接、自动装箱、匿名内部类）；优先使用对象池或复用缓冲区。

## Null 安全策略

- **禁止返回 null 表示空集合**：返回 `Collections.emptyList()` / `emptySet()` / `emptyMap()` 或 `Optional.empty()`。
- **Optional 边界**：返回可能为空的结果时使用 `Optional<T>`；**禁止**作为方法参数、字段类型，禁止嵌套 `Optional`。
- **Null 注解**：使用 `@NonNull` / `@Nullable`（Checker Framework、JetBrains 注解或 JSR-305）标注公共 API 的参数和返回值。
- **防御性检查**：公共方法入口对关键参数使用 `Objects.requireNonNull(param, "param must not be null")`；内部私有方法可依赖调用契约减少重复检查。

## 并发与线程安全

- **优先使用 JUC**：`ConcurrentHashMap`, `CopyOnWriteArrayList`, `BlockingQueue`, `ExecutorService` 替代裸 `synchronized`。
- **锁的选择**：简单临界区用 `synchronized`；需要超时/中断用 `ReentrantLock`（禁止跨方法边界持有，必须同一方法内 lock/unlock 配对）；读多写少用 `ReadWriteLock` 或 `StampedLock`（Java 8+，乐观读性能更优）。
- **原子类**：计数器、标志位优先使用 `AtomicInteger`, `AtomicLong`、`LongAdder`（高并发计数优先 `LongAdder`）。
- **volatile**：仅用于单一变量的可见性保证（如状态标志），禁止用于非原子性的 read-modify-write 操作（如 `volatile++`）。
- **线程池**：使用 `ThreadPoolExecutor` 显式构造；**禁止**无界队列的 `newFixedThreadPool()` / `newSingleThreadExecutor()`（内部 `LinkedBlockingQueue` 有 OOM 风险）；必须配置有界队列、核心/最大线程数、拒绝策略；生命周期结束时 `shutdown()` + `awaitTermination()`。
- **CompletableFuture**：链式组合必须处理异常分支（`exceptionally` / `whenComplete`）；自定义 `Executor` 时避免使用 `ForkJoinPool.commonPool()` 执行阻塞操作。
- **不可变性**：共享数据优先设计为不可变对象（`final` 字段 + 无 setter + 防御性拷贝构造函数）。
- **复杂基础软件**：跨进程/跨 NUMA 节点同步优先使用 `VarHandle`（Java 9+）替代 `Unsafe`；`Unsafe` 仅在无等效能力时使用，且必须封装隔离。禁止在临界区内执行阻塞 IO、日志记录、复杂计算。

## 集合与泛型

- **接口类型**：声明集合变量和参数时使用接口类型（`List`, `Set`, `Map`）而非实现类。
- **泛型**：禁止裸类型（raw type）；无法确定类型参数时使用 `<?>` 通配符。
- **Stream API**：链式调用超过 3 个中间操作时拆分为有命名的中间操作或方法引用；处理 `int`/`long`/`double` 时优先使用 `IntStream`/`LongStream`/`DoubleStream`，禁止通过 `Stream<Integer>`/`Stream<Long>` 装箱；**热路径禁止 Stream**（每次操作创建多个中间对象和 lambda），使用传统 `for` 循环；**禁止无控制使用 `parallel()`**（默认共享 `ForkJoinPool.commonPool()`），如需并行显式指定自定义 `ForkJoinPool`。
- **防御性拷贝**：公共方法返回内部可变集合时，返回不可修改视图（`Collections.unmodifiableList`）或拷贝副本；接收外部传入的可变集合时优先拷贝后再存储。
- **ConcurrentHashMap 复合操作**：使用 `computeIfAbsent`、`compute`、`merge` 替代先 `get` 后 `put` 的非原子操作。

## 现代 Java 特性（Java 14+）

- **Record**：用于不可变 DTO、临时聚合结果。不适用：JPA 实体、需要继承的类、字段过多（> 8 个）。引用类型字段需防御性拷贝：
  ```java
  public record UserDto(String name, List<String> tags) {
      public UserDto { tags = List.copyOf(tags); }
  }
  ```
- **Switch 表达式**：优先使用箭头语法替代传统 switch。
  ```java
  String result = switch (status) {
      case ACTIVE -> "active";
      default -> throw new IllegalArgumentException("Unknown: " + status);
  };
  ```
- **文本块**：多行字符串使用 `"""` 语法；起始 `"""` 置于内容最左对齐位置。
- **Sealed 类**：用于限制继承层次（如 AST 节点、协议消息类型）。
- **模式匹配**：Java 17+ 的 `instanceof` 模式匹配和 Java 21+ 的 switch 模式匹配优先使用，减少显式强制转换。
- **虚拟线程（Java 21+）**：I/O 密集型任务优先使用；CPU 密集型任务继续使用平台线程池。禁止在虚拟线程中执行持有 monitor 锁的长时间操作（会 pin 载体线程）。`ThreadLocal` 开销显著增加，优先使用 `ScopedValue` 替代。

## 序列化与反序列化

- **禁止 Java 原生序列化**：禁止实现 `Serializable` 和使用 `ObjectInputStream`/`ObjectOutputStream`（安全风险：反序列化漏洞、版本兼容性差、性能差）。
- **推荐替代**：配置/元数据用 JSON（Jackson / Gson，关闭默认类型反序列化）；RPC/高性能通信用 Protobuf、Avro、FlatBuffers；进程内缓存用 Kryo（配置类注册器，禁止未注册类反序列化）。
- **反序列化安全**：所有反序列化输入必须经过校验（长度、范围、字段存在性）；禁止反序列化不可信来源的数据为任意对象。

## 反射使用规范

- **缓存反射对象**：`Method`、`Field`、`Constructor` 必须缓存复用，禁止每次调用都 `Class.getDeclaredMethod()`。
- **访问控制**：`setAccessible(true)` 在 Java 9+ 模块化下可能失败；优先使用 `opens` 声明，禁止滥用反射破坏封装。
- **热路径禁止**：延迟敏感路径禁止反射调用（性能开销大）；使用代码生成（Annotation Processor、ByteBuddy）替代运行时反射。
- **类型安全**：反射调用后必须进行类型检查，禁止将反射获取的 `Object` 直接强制转换为目标类型而不校验。

## 测试

- **框架**：JUnit 5（Jupiter）为主；`@ExtendWith(MockitoExtension.class)` 替代 JUnit 4 的 `@RunWith`；使用 `@BeforeEach`, `@AfterEach`, `@BeforeAll`, `@AfterAll`。
- **断言**：使用 `assertThat`（AssertJ 或 Hamcrest）替代 JUnit 基本断言。
- **Mock**：只 mock 外部依赖和边界服务，禁止 mock 值对象（DTO/POJO）。
- **测试隔离**：每个测试独立，不依赖执行顺序；共享状态使用 `@BeforeEach` 重置。
- **参数化测试**：使用 `@ParameterizedTest` + `@ValueSource` / `@CsvSource` 组织测试数据。
- **并发测试**：使用 `@RepeatedTest` 或 JCStress 检测并发 bug；禁止在单元测试中依赖 `Thread.sleep` 做同步。
- **覆盖率**：核心模块 >= 85%，新增代码 >= 95%（见父规范）。

## 工具链

| 类别 | 工具 |
|------|------|
| 构建 | Maven / Gradle（使用 Enforcer Plugin 或 Java Toolchain 锁定版本；优先 LTS：Java 17/21） |
| 格式化 | google-java-format |
| 静态分析 | SpotBugs / Checkstyle / Error Prone |
| 代码质量 | SonarQube / PMD |
| 内存分析 | VisualVM / Eclipse MAT / JFR |
| 测试 | JUnit 5 + AssertJ + Mockito；并发测试使用 JCStress |
| Null 检查 | Checker Framework / NullAway |

## 代码审查清单（Java 特定，≤15 项）

- [ ] 是否使用了 try-with-resources 管理 `AutoCloseable` 资源？
- [ ] 异常处理是否区分了受检/非受检，无空 catch 块，且保留了原始 cause？
- [ ] 并发代码是否使用 JUC 工具？线程池是否有界且生命周期正确管理？
- [ ] 集合返回是否避免 `null`，优先返回空集合或 `Optional`？公共 API 是否防御性拷贝？
- [ ] 是否对关键参数进行了 `Objects.requireNonNull()` 或显式 null 检查？
- [ ] 日志是否使用参数化占位符，且未泄露敏感信息？异步场景 MDC 是否正确传递？
- [ ] 测试是否使用 JUnit 5 + AssertJ，且每个测试相互独立？
- [ ] 命名是否自解释？是否存在无意义缩写或单字母变量？
- [ ] 是否禁止魔法数字/字符串，提取为命名常量（时间常量带单位后缀）？
- [ ] 类/方法是否职责单一？长度异常时是否已审查拆分必要性？
- [ ] 是否使用 `Optional` 替代返回 `null`（且未滥用为参数/字段）？
- [ ] 导入是否按规范分组排序，无 `*` 通配符导入？
- [ ] 热路径是否避免了 Stream、自动装箱、临时对象创建？
- [ ] 是否禁止 Java 原生序列化，使用 Protobuf/JSON 等替代？
- [ ] 反射使用是否缓存了 Method/Field，热路径是否避免反射？
