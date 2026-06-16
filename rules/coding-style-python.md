# coding-style-python — Python 编码规范

> 语言特定规范。通用规范见 [coding-style.md](coding-style.md)。冲突时以本文件为准。

## 适用范围

- `**/*.py`, `**/*.pyi`

## 命名规范

| 类型 | 风格 | 示例 |
|------|------|------|
| 函数/变量 | `snake_case` | `calculate_checksum(data)` |
| 类 | `PascalCase` | `class ConnectionPool:` |
| 常量 | `SCREAMING_SNAKE_CASE` | `DEFAULT_TIMEOUT = 30` |
| 私有成员 | `_leading_underscore` | `self._internal_state` |
| 模块/包名 | `snake_case` | `file_parser.py`, `networking` |
| 布尔变量 | `is_`/`has_`/`can_`/`should_`/`needs_` 前缀 | `is_connected`, `has_data` |
| 异常类 | `PascalCase` + `Error` 后缀 | `class ConfigError(ValueError):` |
| 类型变量 | `T` / `TypeVar` 描述性名称 | `T = TypeVar("T")` |

**禁区**：禁止单字母变量（循环 `i`/`j`/`k` 除外）、匈牙利命名法、`_` 开头的公共 API。

## 格式化

- 行宽：88 字符（Black 默认）
- 缩进：4 空格
- 引号：双引号优先（字符串含单引号时除外）
- 空行：顶级函数/类之间 2 空行，类内方法之间 1 空行
- 导入顺序：标准库 → 第三方 → 本地模块，每组之间 1 空行
- 每文件末尾保留 1 个空行

## 类型注解

- 所有函数参数和返回值必须标注类型（`__init__` 返回 `None` 可省略）
- 使用 `from __future__ import annotations` 避免运行时导入开销（Python 3.7+）
- 容器类型优先使用内置泛型（Python 3.9+）：`list[str]`, `dict[str, int]`, `set[str]`, `tuple[int, ...]`
- 复杂类型使用 `typing` 模块：`Callable`, `Protocol`, `TypeVar`, `Generic`
- 使用 `|` 替代 `Union`（Python 3.10+）：`str | None` 替代 `Optional[str]`
- 禁止滥用 `Any` 逃避类型检查；使用 `TypedDict` 定义结构化字典，`NamedTuple` 或 `@dataclass` 定义记录类型
- 优先使用 `Protocol` 定义鸭子类型接口，而非强制继承抽象基类

## 包组织与模块结构

- 一个模块只负责一个核心概念；模块超过 500 行应审视是否拆分
- 包内公开 API 在 `__init__.py` 中显式导出（`__all__`），内部实现放入子模块
- 使用绝对导入，禁止相对导入（`from .module import x` 仅在包内部重构时允许）
- 禁止循环导入；若两模块需要互相引用类型，使用 `TYPE_CHECKING` 条件导入
- 禁止 `from module import *`（除非 `__init__.py` 中配合 `__all__` 控制导出）

```python
from typing import TYPE_CHECKING
if TYPE_CHECKING:
    from .peer import Peer  # 仅类型检查期导入，避免循环依赖
```

## 错误处理

- 禁止裸 `except:`，必须捕获具体异常类型（如 `except ValueError:`）
- 禁止空的 `except` 分支静默吞错；至少记录日志或重新抛出
- 使用 `try-except-finally` 确保资源释放，`finally` 只用于清理
- 自定义异常继承自 `Exception` 或标准异常，以 `Error` 结尾
- 错误信息包含上下文（操作、参数、原因），使用 `raise ... from e` 保留异常链
- 区分可恢复错误与不可恢复错误（详见父规范 §2）
- 可恢复：外部依赖失败 → 捕获并返回错误/重试；不可恢复：编程错误 → 使用 `assert` 或立即抛出

```python
try:
    with open(path, "r") as f:
        data = f.read()
except FileNotFoundError as e:
    raise ConfigError(f"无法读取配置文件: {path}") from e
```

## 断言与不变量

- `assert` 只用于检测程序内部不变量（不可能发生的情况）
- **禁止**用 `assert` 处理用户输入、网络数据、磁盘 IO 等外部错误
- 发布版本中 `assert` 可被 `python -O` 关闭，assert 后的代码不能依赖其副作用

## 内存管理

- 依赖 GC 自动管理，但避免循环引用（尤其是 `__del__` 与闭包捕获）
- 使用 `with` 语句管理资源（文件、锁、连接），确保异常路径下释放
- 使用 `weakref` 处理缓存或观察者模式中的循环引用
- 大数据量处理使用生成器（`yield`）避免内存膨胀，禁止在循环中累积大列表
- 使用 `__slots__` 减少内存占用（仅当类实例数量极大且属性固定时）

```python
def process_large_file(path: str) -> Iterator[Record]:
    with open(path, "r") as f:
        for line in f:
            yield parse_record(line)
```

## 数据类与结构化类型

| 场景 | 推荐方案 | 不推荐 |
|------|---------|--------|
| 简单不可变记录 | `@dataclass(frozen=True)` | `namedtuple`（扩展性差） |
| 可变数据容器 | `@dataclass` | 裸 `dict`（无类型安全） |
| 需要验证/序列化 | `pydantic.BaseModel` | 手动 `__init__` 验证 |
| 配置对象 | `@dataclass` + `__post_init__` | 全局 `dict` |
| 纯类型标注字典 | `TypedDict` | `dict[str, Any]` |

- `pydantic` 仅用于 IO 边界（API 请求/响应、配置文件加载），禁止在核心算法内部使用（运行时开销大）
- `dataclass` 优先于手动编写 `__init__`/`__repr__`/`__eq__`

## 并发

### 线程安全

- 使用 `threading.Lock` + `with` 语句，临界区只保护必要的数据访问
- 禁止在临界区内执行 IO 或复杂计算
- 禁止在持有锁时调用可能再次获取锁的外部回调（避免死锁）

```python
with self._lock:
    self._counter += 1
```

### GIL 规避与 CPU 密集型任务

- 纯 Python CPU 密集型任务使用 `multiprocessing` 或 `concurrent.futures.ProcessPoolExecutor`
- 禁止在性能关键路径使用纯 Python 多线程处理 CPU 密集型任务（GIL 限制）
- C 扩展应在长时间计算中释放 GIL（`Py_BEGIN_ALLOW_THREADS` / `Py_END_ALLOW_THREADS`）
- 共享状态最小化，优先使用消息传递（`queue.Queue`、`multiprocessing.Queue`）

### asyncio

- I/O 密集型并发使用 `asyncio` + `async`/`await`
- 使用 `asyncio.Lock` 而非 `threading.Lock` 在 async 代码中
- **禁止**在 async 函数中调用阻塞同步 API（如 `time.sleep`、`requests.get`）；使用 `await asyncio.sleep()`、`aiohttp` 等异步替代
- 需要从同步代码调用 async 函数时，使用 `asyncio.run()` 或显式事件循环管理；禁止在已运行事件循环的线程中嵌套调用 `asyncio.run()`

```python
async def fetch_all(urls: list[str]) -> list[bytes]:
    tasks = [asyncio.create_task(fetch(url)) for url in urls]
    return await asyncio.gather(*tasks)
```

## 日志

- 使用标准库 `logging` 模块，禁止 `print` 输出诊断信息
- 日志级别分层（详见父规范 §7）：`ERROR` / `WARN` / `INFO` / `DEBUG` / `TRACE`
- 使用参数化形式：`logger.info("Processing %d records", count)`，禁止运行时字符串拼接
- 禁止在日志中输出敏感信息（密码、Token、个人身份信息）
- 在库代码中使用 `logging.getLogger(__name__)` 获取模块级 logger，禁止根 logger 配置

## 配置与依赖

- 配置从环境变量或配置文件读取，禁止硬编码环境相关值；使用 `pydantic-settings` 或 `@dataclass` + `__post_init__` 定义配置 schema
- 使用 `pyproject.toml` 作为项目元数据和依赖声明的标准格式
- 运行时依赖与开发依赖分离；版本约束使用 `>=` 或兼容版本说明，禁止无约束依赖（`*`）
- 禁止在运行时依赖中引入仅开发使用的工具（如 `pytest`、`black`、`mypy`）

## 性能

- 热路径禁止：动态内存分配（大对象创建）、无必要的锁、日志记录、系统调用（详见父规范 §8）
- 列表推导优先于 `for` 循环构建列表；生成器表达式优先于列表推导处理大数据
- 字符串拼接使用 `str.join()`，禁止循环中 `+=` 拼接字符串
- 使用 `collections.deque` 替代 `list` 实现 FIFO 队列
- 使用 `functools.lru_cache` 缓存纯函数结果（注意参数必须可哈希）
- 性能关键代码使用 `cProfile` / `line_profiler` 分析后再优化，禁止过早优化

## 安全

- 字符串/缓冲区操作使用长度限制版本，禁止无界操作
- 禁止 `eval()`、`exec()` 处理不可信输入；使用 `ast.literal_eval()` 解析可信字面量
- SQL 查询使用参数化查询，禁止字符串拼接 SQL
- 命令执行使用参数列表（`subprocess.run(["cmd", arg1, arg2])`），禁止 `shell=True` 处理动态输入
- 输入数据必须校验（长度、范围、格式）后再使用
- 反序列化不可信数据时使用安全格式（JSON、MessagePack），禁止 `pickle` 处理网络输入
- 文件路径使用 `pathlib.Path` 并校验路径遍历（`Path.resolve()` 后检查是否在允许目录内）

## 测试

- 框架：pytest
- 命名：`test_<scenario>` 或 `test_<module>_<scenario>`
- 使用 fixtures 管理测试数据和依赖，测试数据与测试逻辑分离
- 使用 `pytest.raises` 验证异常抛出
- 使用 `pytest.mark.parametrize` 组织多组输入测试
- 核心模块覆盖率 >= 85%，新增代码覆盖率 >= 95%（详见父规范 §5）
- 每个测试只验证一个概念，禁止一个测试验证多个不相关的行为
- 单元测试执行时间 < 1 秒/个；超过 100ms 的测试标记为 `@pytest.mark.slow`

```python
import pytest

@pytest.mark.parametrize("input,expected", [
    ("hello", 5),
    ("", 0),
])
def test_string_length(input: str, expected: int) -> None:
    assert len(input) == expected

def test_parse_empty_string_raises() -> None:
    with pytest.raises(ValueError, match="空输入"):
        parse_data("")
```

## 工具链

| 工具 | 用途 | 配置 |
|------|------|------|
| black | 格式化 | `pyproject.toml` |
| ruff | 静态分析 + import 排序 | `pyproject.toml` |
| mypy | 类型检查 | `pyproject.toml` |
| pytest | 测试框架 | `pyproject.toml` |
| pytest-cov | 覆盖率 | `pyproject.toml` |
| bandit | 安全扫描 | `pyproject.toml` |

## 代码审查清单

### 通用检查项（详见父规范 §审查清单）

- [ ] 命名是否自解释？是否存在无意义缩写？
- [ ] 错误处理是否完备？是否有静默吞错？可恢复与不可恢复错误是否区分正确？
- [ ] 是否有内存泄漏风险？分配与释放是否配对？资源在错误路径下是否释放？
- [ ] 是否有并发安全问题？锁是否配对？临界区是否最小化？是否定义了锁顺序？
- [ ] 测试覆盖率是否达标（核心 >= 85%，新增 >= 95%）？
- [ ] 是否有明显的性能问题（热路径上的分配/锁/系统调用）？
- [ ] 代码是否符合 Python 特定规范（本文件）？
- [ ] 是否有循环依赖或过度耦合？

### Python 特定检查项

- [ ] 命名是否自解释且符合 snake_case / PascalCase？
- [ ] 所有函数是否有类型注解？是否通过 mypy 检查？
- [ ] 是否避免了裸 except？异常链是否保留（`raise ... from e`）？
- [ ] 资源管理是否使用 with 语句？
- [ ] 是否有循环引用风险？大数据处理是否使用生成器？
- [ ] 并发代码是否使用正确的锁类型（threading vs asyncio）？async 函数中是否避免阻塞调用？
- [ ] CPU 密集型任务是否使用多进程而非多线程？
- [ ] 测试是否覆盖正常路径和异常路径？是否使用 parametrize 组织数据？
- [ ] 是否通过 black + ruff + mypy + bandit 检查？
- [ ] 日志是否使用参数化形式？是否泄露敏感信息？
- [ ] 配置是否从环境变量/文件加载，无硬编码环境值？
- [ ] 是否禁止 `eval`/`exec`/`pickle` 处理不可信输入？
