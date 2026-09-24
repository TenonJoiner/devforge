#!/usr/bin/env python3
"""topic 文档客观项 lint。

把机器可验证项从 reviewer 手里拿走，一次性脚本化检查，产出结构化违规清单。
reviewer 的 token 留给判断类问题；lint 报告里的违规项视为已确认问题，直接进修正清单。

用法：
    python3 lint-topic-doc.py <doc.md>

退出码：0 无违规；1 有违规；2 用法错误。
输出：stdout，每行一条违规 `[RULE] line N: 描述`，末行 `N violation(s)` 为计数。

检查项：
  SIZE       行数 ≤500，Unicode 字符数 ≤30000
  ASCII      含框角字符的文本代码块内，同一框的边框行显示宽度一致
  MERMAID    Mermaid 语法规则（别名方向 / 消息引号 / 禁用语法 / 箭头标签保留字符）
  BANNED     禁用词（声明编号 C\\d+、catalog 编号 E-\\d+、"第 N 阶段"/"步骤 N"、
             临时文件路径 /tmp/arch-extract-topic-*、模板引用块残留）
  LINE_NO    行号泄漏——`file.ext:N` 模式出现在正文（frontmatter 除外）
"""
import re
import sys
import unicodedata

MAX_LINES = 500
MAX_CHARS = 30000

BOX_CORNERS = '┌┐├┤└┘'   # 含任一者才认定为组件拓扑图（纯文本清单 / 目录树无这些字符）
BOX_BORDER_HEAD = '┌├└'  # 框体边框行的首字符
BOX_BORDER_TAIL = '┐┤┘'  # 框体边框行的末字符
BOX_VERT = '│'           # 竖直连线行首字符：归入同一框体组，但宽度不参与比较


def dw(text):
    return sum(2 if unicodedata.east_asian_width(c) in ('W', 'F') else 1 for c in text)


def split_frontmatter(lines):
    """返回 (frontmatter_end_idx, body_start_idx)。无 frontmatter 返回 (0, 0)。"""
    if not lines or lines[0].rstrip() != '---':
        return 0, 0
    for i in range(1, len(lines)):
        if lines[i].rstrip() == '---':
            return i + 1, i + 1
    return 0, 0


def iter_code_blocks(lines, start):
    """产出 (block_start_line, lang, block_lines)。lang 为 ``` 后的语言标记（空串表示无）。"""
    i = start
    while i < len(lines):
        m = re.match(r'^```(\S*)\s*$', lines[i])
        if m:
            lang = m.group(1)
            block_start = i + 1
            j = block_start
            while j < len(lines) and not lines[j].startswith('```'):
                j += 1
            yield block_start, lang, lines[block_start:j]
            i = j + 1
        else:
            i += 1


def check_size(lines, text, violations):
    if len(lines) > MAX_LINES:
        violations.append(f"[SIZE] line -: 行数 {len(lines)} 超过 {MAX_LINES}")
    # Python len() 对 str 就是 Unicode 字符数，不受 locale 影响
    if len(text) > MAX_CHARS:
        violations.append(f"[SIZE] line -: 字符数 {len(text)} 超过 {MAX_CHARS}")


def border_corner_count(line):
    """边框行返回其框角字符数（同行并排 N 个框即 2N 个），非边框行返回 0。

    分组比较只按框角数相同者配对：并排整排的上下边框（框角数相同）能互相校验，
    而「整排顶边框 vs 某个较矮框单独的底边框」框角数不同，不会误配。
    """
    s = line.rstrip()
    if len(s) < 2 or s[0] not in BOX_BORDER_HEAD or s[-1] not in BOX_BORDER_TAIL:
        return 0
    return sum(s.count(c) for c in BOX_CORNERS)


def check_box_run(block_start, run, violations):
    """同一框（或同一排框）的边框行必须等宽——拓扑图对齐的实质判据。

    连线行（│）、箭头行（▼）、label 行天然比框体窄，不参与比较：分层图必然含这些行，
    按「整块等宽」判定会稳定误报且无法通过重渲染收敛。
    """
    groups = {}
    for i, line in run:
        n = border_corner_count(line)
        if n:
            groups.setdefault(n, []).append((i, line))
    for borders in groups.values():
        if len(borders) < 2:
            continue
        ref_i, ref_w = borders[0][0], dw(borders[0][1])
        for i, line in borders[1:]:
            w = dw(line)
            if w != ref_w:
                violations.append(
                    f"[ASCII] line {block_start + i + 1}: 边框行宽 {w} 与同组首行（line {block_start + ref_i + 1}）{ref_w} 不一致——框体左右边界未对齐"
                )


def check_ascii_alignment(lines, body_start, violations):
    """组件拓扑图对齐检查：先以框角字符判定是否为拓扑图，再逐框比较边框行宽度。"""
    for block_start, lang, block_lines in iter_code_blocks(lines, body_start):
        if lang and lang not in ('text', 'plain'):
            continue
        if len(block_lines) < 3:
            continue  # 太短非拓扑图
        if not any(c in line for line in block_lines for c in BOX_CORNERS):
            continue  # 无框角字符：纯文本清单 / 目录树 / 代码，不是拓扑图
        run = []
        for i, line in enumerate(block_lines):
            head = line[:1]
            if head not in BOX_BORDER_HEAD and head != BOX_VERT:
                check_box_run(block_start, run, violations)
                run = []
                continue
            if head == '┌' and run and run[-1][1][:1] == '└':
                check_box_run(block_start, run, violations)  # 上下两框紧邻，分属两组
                run = []
            run.append((i, line))
        check_box_run(block_start, run, violations)


def check_mermaid(lines, body_start, violations):
    for block_start, lang, block_lines in iter_code_blocks(lines, body_start):
        if lang != 'mermaid':
            # 检测写了 sequenceDiagram 但语言标记漏了 mermaid
            if not lang and any('sequenceDiagram' in l for l in block_lines):
                violations.append(
                    f"[MERMAID] line {block_start}: 代码块内容是 sequenceDiagram 但语言标记缺失 ```mermaid"
                )
            continue
        for i, line in enumerate(block_lines, start=block_start + 1):
            # 1. participant 别名方向
            if re.search(r'participant\s+"[^"]+"\s+as\s+\w+', line):
                violations.append(
                    f"[MERMAID] line {i}: participant 别名方向反了——正确写法是 participant <引用ID> as \"显示名\"，当前写法会把显示名当引用 ID 导致组件重复"
                )
            # 2. rect rgb 禁用
            if 'rect rgb(' in line:
                violations.append(
                    f"[MERMAID] line {i}: 使用了 rect rgb(...)，硬编码颜色在亮色/暗色主题下不可读——改用 Note over"
                )
            # 3. activate / deactivate / loop / alt
            if re.match(r'^\s*(activate|deactivate|loop|alt)\s', line):
                violations.append(
                    f"[MERMAID] line {i}: 使用了 {line.strip().split()[0]} 高级语法——保持语法最简，时序细节交给编号列表"
                )
            # 4. 消息引号 + 箭头标签保留字符。语法：A->>B: msg，箭头后是接收者 ID，然后才是 ':' + 消息
            arrow_match = re.search(r'(?:->>|-->>|->|-->)\s*[^:\s]+\s*:\s*(.+)$', line)
            if arrow_match:
                msg = arrow_match.group(1).strip()
                # 消息文本含 : 但未用双引号包裹整段
                if ':' in msg and not (msg.startswith('"') and msg.endswith('"')):
                    violations.append(
                        f"[MERMAID] line {i}: 消息文本含 ':' 但未用双引号包裹整段——Mermaid 用 ':' 分隔参与者与消息，未引号包裹会导致渲染断裂"
                    )
                # 未引号包裹时含保留字符
                if not (msg.startswith('"') and msg.endswith('"')):
                    for ch in ('(', ')', '[', ']', '{', '}', '<', '>'):
                        if ch in msg:
                            violations.append(
                                f"[MERMAID] line {i}: 箭头标签文本含未转义的 '{ch}'——Mermaid 语法保留字符，需用 &#40; 等转义或加双引号"
                            )
                            break
                    # 中文冒号
                    if '：' in msg:
                        violations.append(
                            f"[MERMAID] line {i}: 箭头标签含中文冒号 '：'——改用英文冒号外加双引号包裹整段"
                        )


BANNED_PATTERNS = [
    (re.compile(r'\bC\d+\b'), '声明编号'),
    (re.compile(r'\bE-\d+\b'), 'catalog 编号'),
    (re.compile(r'第\s*[\d一二三四五六七八九十]+\s*阶段'), 'skill 阶段号'),
    (re.compile(r'步骤\s*\d+'), 'skill 步骤号'),
    (re.compile(r'/tmp/arch-extract-topic-'), '临时文件路径'),
    (re.compile(r'^\s*>\s*\*\*写作'), '模板引用块残留'),
    (re.compile(r'^\s*>\s*\*\*写什么'), '模板引用块残留'),
    (re.compile(r'^\s*>\s*\*\*不写什么'), '模板引用块残留'),
    (re.compile(r'^\s*>\s*\*\*最低深度'), '模板引用块残留'),
    (re.compile(r'^\s*>\s*\*\*模板使用说明'), '模板引用块残留'),
]

LINE_NO_PATTERN = re.compile(
    r'\b[a-zA-Z_][a-zA-Z0-9_]*\.(?:c|h|cc|cpp|hpp|go|rs|py|java):\d+\b'
)


def check_banned(lines, body_start, violations):
    in_code = False
    for i in range(body_start, len(lines)):
        line = lines[i]
        if line.startswith('```'):
            in_code = not in_code
            continue
        if in_code:
            continue  # 代码块内不查禁用词（结构体定义可能含字段名 C\d 误报）
        for pat, name in BANNED_PATTERNS:
            if pat.search(line):
                violations.append(
                    f"[BANNED] line {i + 1}: 出现{name}（{pat.pattern}）——内部过程制品禁止泄漏到最终文档"
                )


def check_line_no(lines, body_start, violations):
    for i in range(body_start, len(lines)):
        line = lines[i]
        m = LINE_NO_PATTERN.search(line)
        if m:
            violations.append(
                f"[LINE_NO] line {i + 1}: 行号引用 {m.group(0)!r}——行号易腐，禁止出现在最终文档任何位置（正文/表格/备注列），改用函数名/结构体名等稳定标识"
            )


def main():
    if len(sys.argv) != 2:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    with open(sys.argv[1]) as f:
        text = f.read()
    lines = text.splitlines()
    _, body_start = split_frontmatter(lines)

    violations = []
    check_size(lines, text, violations)
    check_ascii_alignment(lines, body_start, violations)
    check_mermaid(lines, body_start, violations)
    check_banned(lines, body_start, violations)
    check_line_no(lines, body_start, violations)

    for v in violations:
        print(v)
    print(f"{len(violations)} violation(s)")
    sys.exit(1 if violations else 0)


if __name__ == '__main__':
    main()
