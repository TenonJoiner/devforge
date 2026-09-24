#!/usr/bin/env python3
"""ASCII Art 组件拓扑图渲染器。

输入：JSON 结构描述（组件框 + 连线），输出对齐的 ASCII Art。
中文/全角字符按双宽（East Asian Width = W/F）计算，保证跨行对齐。

用法：
    python3 ascii-art-render.py <structure.json>

JSON schema：
{
  "rows": [
    {
      "boxes": [
        {"id": "<box-id>", "lines": ["<line1>", "<line2>", ...]},
        ...
      ],
      "hlinks": [
        {"from": "<box-id>", "to": "<box-id>", "label": "<可选>"}
      ]
    },
    ...
  ],
  "vlinks": [
    {"from": "<box-id>", "to": "<box-id>", "label": "<可选>"}
  ]
}

约束：
- hlink 只能连接**同一行内自左向右相邻**的两个 box——跳过中间 box 的连线会横穿它
- vlink 的 to 必须是 from 的**下一行**中的 box——同行连接用该行的 hlinks，
  跨多行的折线其横段会横穿中间行的 box
违反上述约束时 render() 报错退出，不输出破损图。

布局规则：
- rows 自上而下排列；每行内 boxes 自左向右排列
- 若两 box 间有 hlink，间距 = max(HGAP_MIN, label 宽度 + 6)；否则 HGAP_MIN
- row 高度 = 该行最高 box 的高度；行间垂直间距 VGAP（留位给 vlink）
- hlink label 写在连线中段同行，覆盖该段连线字符（"── label ──▶" 形式）
- vlink 支持直线（两 box 水平中点对齐）和 L 型折线（不对齐时先竖后横再竖）；
  L 型折线的横段走在**源 row 所有 box 的下方**，避免横穿同行更高的 box
- 同一 from box 的多个 vlink 自动错开起点（from_cx ± 偏移），偏移收敛在 box 宽度内
- vlink label 写在竖段 1 第二行右侧（from_cx + 2, from_y + 1）

输出：ASCII Art 写入 stdout。调用方（主会话/agent）将其嵌入 markdown 代码块。
"""
import json
import sys
import unicodedata
from collections import defaultdict

CH = {
    'tl': '┌', 'tr': '┐', 'bl': '└', 'br': '┘',
    'h': '─', 'v': '│',
    'arrow_r': '▶', 'arrow_d': '▼',
}

HGAP_MIN = 8   # 同行 box 间最小水平间距（容纳箭头 + 留白）
VGAP = 4       # 相邻 row 间垂直间距（容纳 vlink 竖段 + label 行 + 横段行）


def dw(text):
    """显示宽度：East Asian Wide/Fullwidth 计 2，其他计 1。"""
    return sum(2 if unicodedata.east_asian_width(c) in ('W', 'F') else 1 for c in text)


def pad(text, width):
    """按显示宽度右填充空格至 width。"""
    diff = width - dw(text)
    if diff < 0:
        raise ValueError(f"pad 目标宽度 {width} 小于文本显示宽度 {dw(text)}: {text!r}")
    return text + ' ' * diff


def render_box(lines):
    """单个 box 渲染为字符行列表，返回 (lines, width, height)。宽度 = max(dw(line)) + 4。"""
    if not lines:
        lines = ['']
    inner_w = max(dw(l) for l in lines)
    width = inner_w + 4
    out = [CH['tl'] + CH['h'] * (width - 2) + CH['tr']]
    for line in lines:
        out.append(CH['v'] + ' ' + pad(line, inner_w) + ' ' + CH['v'])
    out.append(CH['bl'] + CH['h'] * (width - 2) + CH['br'])
    return out, width, len(out)


class Canvas:
    """显示宽度画布。双宽字符占两个 cell，第二 cell 用 '\\0' 占位，渲染时跳过。"""

    def __init__(self, width, height):
        self.width = width
        self.height = height
        self.cells = [[' '] * width for _ in range(height)]

    def put(self, x, y, text):
        if y < 0 or y >= self.height:
            return
        cx = x
        for c in text:
            w = 2 if unicodedata.east_asian_width(c) in ('W', 'F') else 1
            if cx + w > self.width:
                return
            self.cells[y][cx] = c
            if w == 2:
                self.cells[y][cx + 1] = '\0'
            cx += w

    def render(self):
        lines = []
        for row in self.cells:
            s = ''.join(c for c in row if c != '\0')
            lines.append(s.rstrip())
        while lines and not lines[-1]:
            lines.pop()
        return '\n'.join(lines)


def layout(spec):
    """计算所有 box 的 (x, y, w, h)。返回 (boxes_map, box_renders, box_rows, canvas_w, canvas_h)。

    结构非法（空 row / box id 重复）时抛 ValueError——id 重复会让后一个盒体覆盖前一个。
    """
    box_renders = {}
    box_rows = {}
    for row_idx, row in enumerate(spec['rows']):
        if not row['boxes']:
            raise ValueError(f"rows[{row_idx}] 的 boxes 为空——每个 row 至少要有一个 box")
        for box in row['boxes']:
            if box['id'] in box_renders:
                raise ValueError(f"box id 重复：{box['id']}——id 是连线端点与布局的唯一标识")
            box_renders[box['id']] = render_box(box['lines'])
            box_rows[box['id']] = row_idx

    boxes_map = {}
    y = 0
    for row_idx, row in enumerate(spec['rows']):
        row_height = max(box_renders[b['id']][2] for b in row['boxes'])
        x = 0
        prev_box_id = None
        for box in row['boxes']:
            box_id = box['id']
            _, w, h = box_renders[box_id]
            if prev_box_id is not None:
                gap = HGAP_MIN
                for link in row.get('hlinks', []):
                    if link['from'] == prev_box_id and link['to'] == box_id:
                        label = link.get('label', '')
                        if label:
                            gap = max(gap, dw(label) + 6)
                        break
                x += gap
            boxes_map[box_id] = (x, y, w, h)
            x += w
            prev_box_id = box_id
        y += row_height + (VGAP if row_idx < len(spec['rows']) - 1 else 0)

    canvas_w = max((x + w for x, y, w, h in boxes_map.values()), default=0) + 20
    canvas_h = max((y + h for x, y, w, h in boxes_map.values()), default=0)
    return boxes_map, box_renders, box_rows, canvas_w, canvas_h


def row_bottoms(spec, boxes_map):
    """每行所有 box 的底边 y——L 型折线的横段必须走在这条线以下。"""
    return {row_idx: max(boxes_map[b['id']][1] + boxes_map[b['id']][3] for b in row['boxes'])
            for row_idx, row in enumerate(spec['rows'])}


def validate_links(spec, boxes_map, box_rows):
    """连线拓扑校验：hlink 限同行相邻、vlink 限相邻两行。违反时抛 ValueError。"""
    for link in spec.get('vlinks', []):
        fr, to = link['from'], link['to']
        if fr not in boxes_map or to not in boxes_map:
            raise ValueError(f"vlink 引用了不存在的 box id：{fr} → {to}")
        if box_rows[to] == box_rows[fr]:
            raise ValueError(
                f"同行 box 之间不能用 vlink（{fr} → {to}）：同行相邻请改用 hlinks，"
                f"不相邻的同行 box 之间无法直连——请拆成多段或调整 rows"
            )
        if box_rows[to] != box_rows[fr] + 1:
            raise ValueError(
                f"vlink 跨越了 {abs(box_rows[to] - box_rows[fr])} 行（{fr} → {to}）："
                f"折线的横段会横穿中间行的 box——请拆成相邻行间的多段 vlink，或重排 rows"
            )
    for row in spec['rows']:
        for link in row.get('hlinks', []):
            fr, to = link['from'], link['to']
            if fr not in boxes_map or to not in boxes_map:
                raise ValueError(f"hlink 引用了不存在的 box id：{fr} → {to}")
            if box_rows[fr] != box_rows[to]:
                raise ValueError(f"hlink 只能连接同一行内的 box（{fr} → {to}）：跨行连接请用 vlinks")
            ids = [b['id'] for b in spec['rows'][box_rows[fr]]['boxes']]
            if ids.index(to) != ids.index(fr) + 1:
                raise ValueError(
                    f"hlink 只能连接同行内自左向右相邻的两个 box（{fr} → {to}）："
                    f"跳过中间 box 的连线会横穿它"
                )


def draw_hlink(canvas, boxes_map, link):
    """同行两 box 间绘制横向连线。label 覆盖连线中段，同行显示。"""
    fx, fy, fw, fh = boxes_map[link['from']]
    tx, ty, tw, th = boxes_map[link['to']]
    y = fy + min(fh, th) // 2  # 取两盒较矮者的垂直中点，箭头才落在目标盒的侧边上
    x1 = fx + fw
    x2 = tx
    label = link.get('label', '')
    if label:
        lw = dw(label)
        mid = (x1 + x2) // 2
        lx1 = mid - lw // 2
        lx2 = lx1 + lw
        for x in range(x1, lx1 - 1):
            canvas.put(x, y, CH['h'])
        canvas.put(lx1, y, label)
        for x in range(lx2 + 1, x2 - 1):
            canvas.put(x, y, CH['h'])
        canvas.put(x2 - 1, y, CH['arrow_r'])
    else:
        for x in range(x1, x2 - 1):
            canvas.put(x, y, CH['h'])
        canvas.put(x2 - 1, y, CH['arrow_r'])


def draw_vlink(canvas, boxes_map, link, from_cx, from_row_bottom):
    """纵向连线：from box 底部 from_cx → to box 顶部中点。不对齐画 L 型。

    布局约定（VGAP=4）：
      y=from_y     竖段1 起点
      y=from_y+1   竖段1 + label 行（label 写在横段中点上方，避开竖段）
      y=from_y+2   竖段1 终点 = mid_y，横段所在行
      y=from_y+3   竖段2 + 箭头 = to_y-1
    """
    fx, fy, fw, fh = boxes_map[link['from']]
    tx, ty, tw, th = boxes_map[link['to']]
    to_cx = tx + tw // 2
    from_y = fy + fh
    to_y = ty

    if from_cx == to_cx:
        for y in range(from_y, to_y - 1):
            canvas.put(from_cx, y, CH['v'])
        canvas.put(from_cx, to_y - 1, CH['arrow_d'])
        label = link.get('label', '')
        if label:
            canvas.put(from_cx + 2, from_y + 1, label)
    else:
        # 横段走源 row 全部 box 的下方，否则会横穿同行更高的 box
        mid_y = max((from_y + to_y) // 2, from_row_bottom + 1)
        for y in range(from_y, mid_y + 1):
            canvas.put(from_cx, y, CH['v'])
        x_start, x_end = min(from_cx, to_cx), max(from_cx, to_cx)
        for x in range(x_start, x_end + 1):
            canvas.put(x, mid_y, CH['h'])
        for y in range(mid_y + 1, to_y - 1):
            canvas.put(to_cx, y, CH['v'])
        canvas.put(to_cx, to_y - 1, CH['arrow_d'])
        label = link.get('label', '')
        if label:
            label_w = dw(label)
            label_x = (x_start + x_end) // 2 - label_w // 2
            canvas.put(label_x, mid_y - 1, label)


def render(spec):
    boxes_map, box_renders, box_rows, canvas_w, canvas_h = layout(spec)
    validate_links(spec, boxes_map, box_rows)
    bottoms = row_bottoms(spec, boxes_map)
    canvas = Canvas(canvas_w, canvas_h)
    for box_id, (x, y, w, h) in boxes_map.items():
        lines, _, _ = box_renders[box_id]
        for i, line in enumerate(lines):
            canvas.put(x, y + i, line)
    for row in spec['rows']:
        for link in row.get('hlinks', []):
            draw_hlink(canvas, boxes_map, link)
    vlinks_by_from = defaultdict(list)
    for link in spec.get('vlinks', []):
        vlinks_by_from[link['from']].append(link)
    for from_id, links in vlinks_by_from.items():
        fx, fy, fw, fh = boxes_map[from_id]
        base_cx = fx + fw // 2
        n = len(links)
        offsets = [0] if n == 1 else [(i - (n - 1) / 2) * 4 for i in range(n)]
        for link, off in zip(links, offsets):
            start_cx = min(max(int(base_cx + off), fx), fx + fw - 1)  # 收敛在 box 宽度内
            draw_vlink(canvas, boxes_map, link, from_cx=start_cx,
                       from_row_bottom=bottoms[box_rows[from_id]])
    return canvas.render()


def main():
    if len(sys.argv) != 2:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    with open(sys.argv[1]) as f:
        spec = json.load(f)
    try:
        print(render(spec))
    except ValueError as e:
        print(f"渲染失败：{e}", file=sys.stderr)
        sys.exit(2)


if __name__ == '__main__':
    main()
