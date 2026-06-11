# Drawio XML 生成规范

本模板定义从架构描述生成 drawio XML 的技术规范。agent 在生成 `.drawio` 文件前必须读取本模板。

---

## 基础 XML 结构

每个 `.drawio` 文件必须以此结构开头：

```xml
<mxGraphModel adaptiveColors="auto">
  <root>
    <mxCell id="0"/>
    <mxCell id="1" parent="0"/>
    <!-- 所有 diagram 元素 parent="1" -->
  </root>
</mxGraphModel>
```

- `id="0"`：根层，空 cell
- `id="1"`：默认父层
- 所有 diagram 元素使用 `parent="1"`
- **禁止 XML 注释**（`<!-- -->` 严格禁止）
- 特殊字符转义：`&amp;`、`&lt;`、`&gt;`、`&quot;`

---

## 节点（形状）

### 通用矩形节点（组件/模块/子系统）

```xml
<mxCell id="N1" value="组件名" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#dae8fc;strokeColor=#6c8ebf;" vertex="1" parent="1">
  <mxGeometry x="120" y="80" width="120" height="60" as="geometry"/>
</mxCell>
```

**标准样式表**：

| 语义 | fillColor | strokeColor | 字体颜色 |
|------|-----------|-------------|---------|
| 核心组件 | `#dae8fc` | `#6c8ebf` | `#000000` |
| 外部依赖/第三方 | `#f5f5f5` | `#666666` | `#333333` |
| 数据存储 | `#fff2cc` | `#d6b656` | `#000000` |
| 用户/客户端 | `#d5e8d4` | `#82b366` | `#000000` |
| 网络/通信 | `#e1d5e7` | `#9673a6` | `#000000` |
| 进程/运行时 | `#f8cecc` | `#b85450` | `#000000` |

### 圆角与形状变体

- 普通组件：`rounded=1`
- 数据库/存储：`shape=cylinder;`
- 用户/角色：`shape=actor;`
- 云端/集群：`shape=cloud;`
- 容器边界：`shape=swimlane;`（泳道，用于分组）

---

## 边（连接线）

### 基本边

```xml
<mxCell id="E1" value="调用/数据流" style="edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;jettySize=auto;html=1;" edge="1" parent="1" source="N1" target="N2">
  <mxGeometry relative="1" as="geometry"/>
</mxCell>
```

**关键规则**：每条边必须有 `<mxGeometry relative="1" as="geometry"/>` 作为子元素。禁止自闭合 `<mxCell .../>` 作为边。

### 箭头样式

| 语义 | endArrow | startArrow |
|------|----------|------------|
| 同步调用 | `classic` | `none` |
| 异步消息 | `open` | `none` |
| 双向通信 | `classic` | `classic` |
| 数据依赖 | `none` | `none` |
| 继承/实现 | `block` | `none`（dashed=1） |

在 style 中附加：`endArrow=classic;startArrow=none;`

### 边的 strokeColor

- 默认：`#666666`
- 错误/异常路径：`#b85450`（红色）
- 成功/正常路径：`#82b366`（绿色）

---

## 图示类型约定

### 结构图（Structure Diagram）

**布局**：分层布局，上层依赖下层
- 用户/客户端在最上层
- API 网关/入口层在中间上层
- 核心服务/组件在中间层
- 数据存储在最下层
- 外部依赖放在最左侧或最右侧

**节点间距**：水平 40px，垂直 40px
**节点尺寸**：宽 120-160px，高 60-80px

**分组（容器）**：

```xml
<mxCell id="G1" value="子系统A" style="swimlane;whiteSpace=wrap;html=1;fillColor=#f5f5f5;strokeColor=#666666;" vertex="1" parent="1">
  <mxGeometry x="100" y="200" width="400" height="300" as="geometry"/>
</mxCell>
<!-- 组内元素 parent="G1" -->
<mxCell id="N2" value="组件A1" ... parent="G1">
```

### 时序图（Sequence Diagram）

**布局**：
- 参与者（生命线）水平排列，从左到右
- 每个参与者 x 间隔 180px
- 消息从上往下按时间顺序排列，y 间隔 50px

**生命线**：

```xml
<mxCell id="L1" value="Client" style="shape=umlLifeline;perimeter=lifelinePerimeter;whiteSpace=wrap;html=1;fillColor=#d5e8d4;strokeColor=#82b366;" vertex="1" parent="1">
  <mxGeometry x="100" y="80" width="100" height="400" as="geometry"/>
</mxCell>
```

**消息（同步）**：

```xml
<mxCell id="M1" value="request()" style="html=1;verticalAlign=bottom;endArrow=block;entryX=0.5;entryY=0;" edge="1" parent="1" source="L1" target="L2">
  <mxGeometry relative="1" as="geometry">
    <Array as="points">
      <mxPoint x="250" y="130"/>
    </Array>
  </mxGeometry>
</mxCell>
```

**返回消息（虚线）**：

```xml
<mxCell ... style="...;dashed=1;" ...>
```

### 状态机图（State Machine Diagram）

**布局**：
- 初始状态：顶部或左侧（黑色实心圆）
- 终止状态：底部或右侧（双圆环）
- 中间状态：按转换流向排列

**状态节点**：

```xml
<mxCell id="S1" value="Idle" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#dae8fc;strokeColor=#6c8ebf;" vertex="1" parent="1">
  <mxGeometry x="200" y="100" width="100" height="60" as="geometry"/>
</mxCell>
```

**初始状态**：

```xml
<mxCell id="Start" style="ellipse;whiteSpace=wrap;html=1;fillColor=#000000;" vertex="1" parent="1">
  <mxGeometry x="245" y="50" width="10" height="10" as="geometry"/>
</mxCell>
```

**转换边**：标签写触发事件和守卫条件

```xml
<mxCell id="T1" value="connect / [valid]" style="edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;jettySize=auto;html=1;" edge="1" parent="1" source="Start" target="S1">
  <mxGeometry relative="1" as="geometry"/>
</mxCell>
```

### 数据流图（Data Flow Diagram）

**布局**：
- 数据源在左侧
- 处理节点在中间，按处理顺序从左到右
- 存储/目标在右侧
- 数据流箭头标注数据类型或格式

**数据源/目标**：菱形或带标签的箭头端点
**处理节点**：矩形（标准组件样式）
**数据存储**：圆柱体（`shape=cylinder;`）

---

## 多页 Diagram

单文件包含多种图示类型时，使用多页：

```xml
<mxGraphModel ...>
  <root>
    <mxCell id="0"/>
    <mxCell id="1" parent="0"/>
    <!-- 第1页内容 -->
  </root>
</mxGraphModel>
```

多页通过 drawio 的 `<diagram>` 标签包装。每页一个 `<diagram>`：

```xml
<mxfile ...>
  <diagram id="page1" name="结构图">
    <mxGraphModel ...>...结构图内容...</mxGraphModel>
  </diagram>
  <diagram id="page2" name="时序图">
    <mxGraphModel ...>...时序图内容...</mxGraphModel>
  </diagram>
</mxfile>
```

> 注：多页文件在 draw.io Desktop 中自动分页显示。单页文件用 `<mxGraphModel>` 即可。

---

## 常见错误排查

| 问题 | 原因 | 解决 |
|------|------|------|
| 图打开空白 | 缺少 root cells id="0"/id="1" | 确保基本结构完整 |
| 边不显示 | 边是自闭合标签 | 必须包含 `<mxGeometry>` 子元素 |
| 节点重叠 | 坐标计算错误 | 检查 x/y 坐标和宽高 |
| 文件打不开 | XML 格式错误 | 验证标签闭合、特殊字符转义 |
| 样式不生效 | style 字符串格式错误 | 确保 key=value; 格式，分号分隔 |

---

## 参考

完整 XML 参考（边路由、容器、层、标签、元数据、暗色模式等）：
https://raw.githubusercontent.com/jgraph/drawio-mcp/main/shared/xml-reference.md
