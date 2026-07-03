---
name: testing-anti-patterns
description: TDD 反模式与陷阱——测试 mock 行为、测试专用方法、不理解依赖就 mock、不完整的 mock
# 本文档改编自 superpowers 项目的 testing-anti-patterns.md
# 原项目: https://github.com/obra/superpowers (MIT License)
---

# 测试反模式

**何时加载**：编写或修改测试、添加 mock、或想在生产类中添加测试专用方法时。

## 概述

测试必须验证真实行为，而非 mock 行为。Mock 是隔离的手段，不是被测试的对象。

**核心原则**：测试代码做了什么，而非 mock 做了什么。

**严格遵循 TDD 可以防止这些反模式。**

## 铁律

```
1. 永远不要测试 mock 行为
2. 永远不要在生产类中添加测试专用方法
3. 永远不要在不理解依赖的情况下 mock
```

## 反模式 1：测试 Mock 行为

### 违规示例

```c
// ❌ 错误：测试 mock 是否存在
void test_wal_append(void **state) {
    wal_t *wal = mock_wal_create();  // mock 对象
    assert_non_null(wal);  // 测试 mock 存在！
    // 这测试的是 mock 能工作，不是 wal_append 能工作
}
```

```typescript
// ❌ 错误：测试 mock 元素存在
test('renders sidebar', () => {
  render(<Page />);
  expect(screen.getByTestId('sidebar-mock')).toBeInTheDocument();
  // 测试的是 mock 存在，不是组件行为
});
```

### 为什么错误

- 你在验证 mock 能工作，而非组件能工作
- 测试在 mock 存在时通过，不存在时失败
- 对真实行为一无所知

### 正确做法

```c
// ✅ 正确：测试真实行为
void test_wal_append(void **state) {
    wal_t *wal = wal_create("test.wal");  // 真实对象
    
    int rc = wal_append(wal, "data", 4);
    assert_int_equal(0, rc);
    
    // 验证真实行为：数据被写入
    assert_int_equal(4, wal_get_size(wal));
    
    wal_close(wal);
}
```

```typescript
// ✅ 正确：测试真实组件或不 mock
test('renders sidebar', () => {
  render(<Page />);  // 不 mock sidebar
  expect(screen.getByRole('navigation')).toBeInTheDocument();
  // 测试真实行为
});

// 或者如果必须 mock sidebar 以隔离：
// 不要断言 mock 存在 - 测试 Page 在 sidebar 存在时的行为
```

### Gate Function

```
断言任何 mock 元素之前：
  问："我在测试真实组件行为还是只是 mock 存在？"

  如果测试 mock 存在：
    停止 - 删除断言或取消 mock

  测试真实行为
```

## 反模式 2：生产类中的测试专用方法

### 违规示例

```c
// ❌ 错误：destroy() 只在测试中使用
typedef struct session {
    workspace_manager_t *workspace_mgr;
    char *id;
} session_t;

// 看起来像生产 API！
void session_destroy(session_t *session) {
    if (session->workspace_mgr) {
        workspace_manager_destroy(session->workspace_mgr, session->id);
    }
    free(session->id);
    free(session);
}

// 在测试中
void teardown(void **state) {
    session_t *session = *state;
    session_destroy(session);  // 使用测试专用方法
}
```

### 为什么错误

- 生产类被测试专用代码污染
- 如果在生产中意外调用会很危险
- 违反 YAGNI 和关注点分离
- 混淆了对象生命周期和实体生命周期

### 正确做法

```c
// ✅ 正确：测试工具处理测试清理
// session 没有 destroy() - 生产中它是无状态的

// 在 tests/test_utils.c
void test_cleanup_session(session_t *session) {
    if (session && session->workspace_mgr) {
        workspace_info_t *info = session_get_workspace_info(session);
        if (info) {
            workspace_manager_destroy(session->workspace_mgr, info->id);
        }
    }
    free(session->id);
    free(session);
}

// 在测试中
void teardown(void **state) {
    test_cleanup_session(*state);
}
```

### Gate Function

```
向生产类添加任何方法之前：
  问："这只在测试中使用吗？"

  如果是：
    停止 - 不要添加
    放到测试工具中

  问："这个类拥有这个资源的生命周期吗？"

  如果否：
    停止 - 这个方法放错类了
```

## 反模式 3：不理解依赖就 Mock

### 违规示例

```c
// ❌ 错误：mock 破坏了测试逻辑
void test_wal_duplicate_detection(void **state) {
    // Mock 阻止了测试依赖的配置写入！
    will_return(__wrap_config_write, 0);
    
    wal_add_server(config);
    wal_add_server(config);  // 应该抛错 - 但不会！
    // 因为 config_write 被 mock 了，配置没写入，检测不到重复
}
```

```python
# ❌ 错误：过度 mock
def test_duplicate_server_detection():
    # Mock 了测试依赖的副作用
    with patch('ToolCatalog.discoverAndCacheTools', return_value=None):
        add_server(config)
        add_server(config)  # 应该抛异常，但不会
```

### 为什么错误

- Mock 的方法有测试依赖的副作用（写配置）
- 为了"安全"而过度 mock 破坏了实际行为
- 测试因错误原因通过或神秘失败

### 正确做法

```c
// ✅ 正确：在正确层级 mock
void test_wal_duplicate_detection(void **state) {
    // 只 mock 慢的部分，保留测试需要的行为
    will_return(__wrap_server_start, 0);  // Mock 服务器启动
    
    wal_add_server(config);  // 配置写入
    int rc = wal_add_server(config);  // 检测到重复 ✓
    assert_int_equal(-EEXIST, rc);
}
```

```python
# ✅ 正确：在正确层级 mock
def test_duplicate_server_detection():
    # 只 mock 慢的外部操作（服务器启动）
    with patch('MCPServerManager.start_server'):
        add_server(config)  # 配置写入
        with pytest.raises(DuplicateServerError):
            add_server(config)  # 检测到重复 ✓
```

### Gate Function

```
Mock 任何方法之前：
  停止 - 先不要 mock

  1. 问："真实方法有什么副作用？"
  2. 问："测试依赖这些副作用吗？"
  3. 问："我完全理解测试需要什么吗？"

  如果依赖副作用：
    在更低层级 mock（实际的慢/外部操作）
    或使用保留必要行为的测试替身
    不是测试依赖的高层方法

  如果不确定测试依赖什么：
    先用真实实现运行测试
    观察实际需要发生什么
    然后在正确层级添加最小 mock

  红旗：
    - "我会 mock 这个以防万一"
    - "这可能慢，最好 mock 它"
    - 不理解依赖链就 mock
```

## 反模式 4：不完整的 Mock

### 违规示例

```c
// ❌ 错误：部分 mock - 只有你认为需要的字段
typedef struct api_response {
    int status;
    char *data;
    // 缺失：下游代码使用的 metadata
} mock_response_t;

mock_response_t mock = {
    .status = 200,
    .data = "success"
    // 缺失 metadata.request_id
};

// 后来：当代码访问 response->metadata->request_id 时崩溃
```

```go
// ❌ 错误：不完整的 mock
mockResponse := &APIResponse{
    Status: "success",
    Data:   map[string]interface{}{"userId": "123", "name": "Alice"},
    // 缺失：Metadata 字段
}

// 下游代码访问 response.Metadata.RequestID 时 panic
```

### 为什么错误

- **部分 mock 隐藏了结构假设** - 你只 mock 了你知道的字段
- **下游代码可能依赖你没包含的字段** - 静默失败
- **测试通过但集成失败** - Mock 不完整，真实 API 完整
- **虚假信心** - 测试对真实行为一无所知

**铁律**：Mock 完整的数据结构（如现实中存在的），而非只 mock 你的直接测试使用的字段。

### 正确做法

```c
// ✅ 正确：镜像真实 API 的完整性
typedef struct api_response {
    int status;
    char *data;
    struct {
        char *request_id;
        time_t timestamp;
    } metadata;
} api_response_t;

api_response_t mock = {
    .status = 200,
    .data = "success",
    .metadata = {
        .request_id = "req-789",
        .timestamp = 1234567890
    }
    // 真实 API 返回的所有字段
};
```

```go
// ✅ 正确：完整的 mock
mockResponse := &APIResponse{
    Status: "success",
    Data:   map[string]interface{}{"userId": "123", "name": "Alice"},
    Metadata: &Metadata{
        RequestID: "req-789",
        Timestamp: 1234567890,
    },
    // 真实 API 返回的所有字段
}
```

### Gate Function

```
创建 mock 响应之前：
  检查："真实 API 响应包含哪些字段？"

  行动：
    1. 检查文档/示例中的实际 API 响应
    2. 包含系统可能在下游消费的所有字段
    3. 验证 mock 完全匹配真实响应模式

  关键：
    如果你在创建 mock，你必须理解整个结构
    部分 mock 在代码依赖遗漏字段时静默失败

  如果不确定：包含所有文档化的字段
```

## 反模式 5：集成测试作为事后补充

### 违规示例

```
✅ 实现完成
❌ 没写测试
"准备测试"
```

### 为什么错误

- 测试是实现的一部分，不是可选的后续工作
- TDD 会捕获这个问题
- 没有测试不能声称完成

### 正确做法

```
TDD 循环：
1. 写失败测试
2. 实现使其通过
3. 重构
4. 然后声称完成
```

## Mock 变得太复杂时

### 警告信号

- Mock 设置比测试逻辑长
- Mock 所有东西才能让测试通过
- Mock 缺少真实组件有的方法
- Mock 改变时测试崩溃

### 考虑

使用真实组件的集成测试通常比复杂 mock 更简单

## TDD 防止这些反模式

### 为什么 TDD 有帮助

1. **先写测试** → 迫使你思考实际在测试什么
2. **看它失败** → 确认测试在测真实行为，不是 mock
3. **最小实现** → 测试专用方法不会悄悄进入
4. **真实依赖** → 在 mock 之前看到测试实际需要什么

**如果你在测试 mock 行为，你违反了 TDD** - 你在没有先看测试对真实代码失败的情况下添加了 mock。

## 快速参考

| 反模式 | 修复 |
|--------|------|
| 断言 mock 元素 | 测试真实组件或取消 mock |
| 生产中的测试专用方法 | 移到测试工具 |
| 不理解就 mock | 先理解依赖，最小化 mock |
| 不完整的 mock | 完全镜像真实 API |
| 测试作为事后补充 | TDD - 测试先行 |
| 过度复杂的 mock | 考虑集成测试 |

## 红旗

- 断言检查 `*-mock` 测试 ID
- 方法只在测试文件中调用
- Mock 设置占测试 >50%
- 移除 mock 后测试失败
- 无法解释为什么需要 mock
- "为了安全起见"而 mock

## 底线

**Mock 是隔离的工具，不是要测试的东西。**

如果 TDD 揭示你在测试 mock 行为，你走错了。

修复：测试真实行为或质疑为什么要 mock。
