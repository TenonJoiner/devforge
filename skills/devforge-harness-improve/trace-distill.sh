#!/bin/bash
# trace-distill.sh — 单会话蒸馏（AHE 式分层下钻）
# 读取原始 JSONL 事件 + 会话转录 → 生成五层 per-session 诊断报告
# 用法: trace-distill.sh <events.jsonl> [transcript.jsonl] > report.md

set -e

if ! command -v python3 &>/dev/null; then
    echo "错误: 需要 python3，但未找到" >&2
    exit 1
fi

EVENTS_FILE="${1:-/dev/stdin}"
TRANSCRIPT_FILE="${2:-}"

EVENTS_FILE="$EVENTS_FILE" TRANSCRIPT_FILE="${TRANSCRIPT_FILE:-}" python3 <<'PYEOF'
import json, sys, re, os
from collections import defaultdict, Counter

# === 脱敏 ===
REDACT_PATTERNS = [
    (re.compile(r"sk-[a-zA-Z0-9]{20,}"), "***REDACTED***"),
    (re.compile(r"ghp_[a-zA-Z0-9]{36}"), "***REDACTED***"),
    (re.compile(r"AKIA[A-Z0-9]{16}"), "***REDACTED***"),
    (re.compile(r"xox[baprs]-[a-zA-Z0-9-]+"), "***REDACTED***"),
    (re.compile(r"-----BEGIN [A-Z ]+ PRIVATE KEY-----[\s\S]*?-----END [A-Z ]+ PRIVATE KEY-----"), "***REDACTED***"),
    (re.compile(r"sshpass\s+-p\s*\S+"), "sshpass -p ***REDACTED***"),
    (re.compile(r"\b(PASSWORD|PASSWD|PASS|SECRET|MYSQL_PWD|PGPASSWORD|DB_PASS|API_KEY|AUTH_TOKEN|ACCESS_KEY|SECRET_KEY)\s*=\s*\S+", re.IGNORECASE), r"\1=***REDACTED***"),
    (re.compile(r"(://)[^:@/\s]+:[^@/\s]+(@)"), r"\1***REDACTED***\2"),
]

def redact(text):
    for pattern, replacement in REDACT_PATTERNS:
        text = pattern.sub(replacement, text)
    return text

# === 读取事件 ===
events = []
events_file = os.environ['EVENTS_FILE']
with open(events_file) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            events.append(json.loads(line))
        except json.JSONDecodeError:
            continue

if not events:
    print("(无事件数据)")
    sys.exit(0)

# 按 seq 排序
events.sort(key=lambda e: e.get("seq", 0))

# === 基本信息 ===
session_id = events[0].get("session", "unknown")
first_ts = events[0].get("ts", "")
last_ts = events[-1].get("ts", "")
total_events = len(events)

# === 统计分类 ===
tool_intents = [e for e in events if e.get("type") == "tool_intent"]
tool_calls = [e for e in events if e.get("type") == "tool_call"]
skill_events = [e for e in events if e.get("type") == "skill_invoke"]
agent_events = [e for e in events if e.get("type") == "agent_dispatch"]
error_events = [e for e in tool_calls if e.get("result", {}).get("status") == "error"]

# === Hook 阻拦检测：有 intent 但无对应 completion ===
# 为每个 intent 查找同 tool 的后续 call（在 3 个 seq 内）
intent_seqs = {e["seq"]: e for e in tool_intents}
completed_seqs = set()
for e in tool_calls:
    for intent_seq in intent_seqs:
        if 0 < e["seq"] - intent_seq <= 3 and intent_seqs[intent_seq]["tool"] == e["tool"]:
            completed_seqs.add(intent_seq)
hook_blocks = []
for seq, intent in intent_seqs.items():
    if seq not in completed_seqs:
        hook_blocks.append(intent)

# === 成功率 ===
success_rate = 1.0
if tool_calls:
    success_rate = (len(tool_calls) - len(error_events)) / len(tool_calls)

# === 会话时长 ===
duration_min = 0
try:
    from datetime import datetime
    t1 = datetime.strptime(first_ts, "%Y-%m-%dT%H:%M:%S")
    t2 = datetime.strptime(last_ts, "%Y-%m-%dT%H:%M:%S")
    duration_min = max(1, int((t2 - t1).total_seconds() / 60))
except Exception:
    total_dur = sum(e.get("duration_ms", 0) or 0 for e in events)
    duration_min = total_dur // 60000 + 1

# === Skill 列表与统计 ===
skills_used = list(set(
    (e.get("input_summary", "") or "").split()[0] or "unknown"
    for e in skill_events
))

# Per-skill 统计
skill_stats = {}
skill_boundaries = []
for i, e in enumerate(events):
    if e.get("type") == "skill_invoke":
        skill_boundaries.append(i)

for j, start_idx in enumerate(skill_boundaries):
    end_idx = skill_boundaries[j+1] if j+1 < len(skill_boundaries) else len(events)
    skill_name = (events[start_idx].get("input_summary", "") or "").split()[0] or "unknown"
    skill_events_range = events[start_idx:end_idx]
    skill_tool_calls = [e for e in skill_events_range if e.get("type") == "tool_call"]
    skill_errors = [e for e in skill_tool_calls if e.get("result", {}).get("status") == "error"]
    skill_agents = [e for e in skill_events_range if e.get("type") == "agent_dispatch"]
    skill_dur = sum(e.get("duration_ms", 0) or 0 for e in skill_events_range)

    if skill_name not in skill_stats:
        skill_stats[skill_name] = {"calls": 0, "errors": 0, "agents": 0, "dur_ms": 0, "retries": 0}
    skill_stats[skill_name]["calls"] += len(skill_tool_calls)
    skill_stats[skill_name]["errors"] += len(skill_errors)
    skill_stats[skill_name]["agents"] += len(skill_agents)
    skill_stats[skill_name]["dur_ms"] += skill_dur

# 重试检测：在 skill 边界内检测连续 2+ 次同 tool 的相似 input
for j, start_idx in enumerate(skill_boundaries):
    end_idx = skill_boundaries[j+1] if j+1 < len(skill_boundaries) else len(events)
    skill_name = (events[start_idx].get("input_summary", "") or "").split()[0] or "unknown"
    skill_range = events[start_idx:end_idx]
    retries = 0
    prev_tool = ""
    prev_input = ""
    consecutive = 0
    for e in skill_range:
        if e.get("type") != "tool_call":
            continue
        tool = e.get("tool", "")
        inp = e.get("input_summary", "")[:60]
        if tool == prev_tool and inp == prev_input:
            consecutive += 1
            if consecutive == 2:
                retries += 1
        else:
            consecutive = 0
        prev_tool = tool
        prev_input = inp
    if skill_name in skill_stats:
        skill_stats[skill_name]["retries"] = retries

# === L3: 执行对齐分析 ===
alignment_issues = []

# 模式 1: Grep 后无跟进操作
for i, e in enumerate(events[:-1]):
    if e.get("tool") != "Grep":
        continue
    if e.get("result", {}).get("status") == "error":
        continue
    next_e = events[i+1] if i+1 < len(events) else None
    if next_e and next_e.get("tool") in ("Grep", "Read"):
        continue  # 再次搜索/读取视为对齐
    alignment_issues.append({
        "type": "grep_no_follow",
        "seq": e.get("seq"),
        "detail": f"seq={e.get('seq')} Grep 结果未被后续工具消费（下一动作为 {next_e.get('tool', '?') if next_e else '?'}）"
    })

# 模式 2: Agent 派遣后结果未被引用
for i, e in enumerate(events[:-2]):
    if e.get("type") != "agent_dispatch":
        continue
    agent_type = e.get("agent_subtype", "general")
    # 检查后 3 个事件是否引用了 agent 的发现
    referenced = False
    for j in range(i+1, min(i+4, len(events))):
        later = events[j]
        later_input = later.get("input_summary", "") or ""
        if agent_type != "general" and agent_type in later_input:
            referenced = True
            break
    if not referenced and agent_type != "general":
        alignment_issues.append({
            "type": "agent_result_ignored",
            "seq": e.get("seq"),
            "detail": f"seq={e.get('seq')} Agent({agent_type}) 结果未被后续 3 步引用"
        })

# 模式 3: Read 后未引用文件路径
for i, e in enumerate(events[:-1]):
    if e.get("tool") != "Read":
        continue
    file_path = e.get("input_summary", "") or ""
    if not file_path:
        continue
    # 检查后续 3 步是否编辑/引用该文件
    referenced = False
    for j in range(i+1, min(i+4, len(events))):
        later = events[j]
        later_input = later.get("input_summary", "") or ""
        if later.get("tool") in ("Edit", "Write", "MultiEdit") and file_path in later_input:
            referenced = True
            break
        if file_path.split("/")[-1] in later_input:
            referenced = True
            break
    if not referenced:
        alignment_issues.append({
            "type": "read_no_edit",
            "seq": e.get("seq"),
            "detail": f"seq={e.get('seq')} Read({file_path[:60]}) 后 3 步内未编辑/引用该文件"
        })

# === L4: 恢复行为分类 ===
recovery_patterns = {"RETRY": [], "ESCALATE": [], "IGNORE": [], "WORKAROUND": []}
for i, e in enumerate(error_events):
    remaining = events[i+1:i+4]
    if not remaining:
        recovery_patterns["IGNORE"].append(e.get("seq"))
        continue

    next_e = remaining[0]
    # RETRY: 同 tool + 相似 input
    if (next_e.get("tool") == e.get("tool") and
        next_e.get("input_summary", "")[:40] == e.get("input_summary", "")[:40]):
        recovery_patterns["RETRY"].append(e.get("seq"))
    # ESCALATE: 派遣 Agent
    elif any(r.get("type") == "agent_dispatch" for r in remaining):
        recovery_patterns["ESCALATE"].append(e.get("seq"))
    # WORKAROUND: 不同 tool（且不是 Skill/Agent）
    elif next_e.get("type") == "tool_call" and next_e.get("tool") != e.get("tool"):
        recovery_patterns["WORKAROUND"].append(e.get("seq"))
    else:
        recovery_patterns["IGNORE"].append(e.get("seq"))

# === 摩擦评分 (0.0-1.0) ===
# 分母使用加权基准而非 total_events，避免长会话（事件多）稀释摩擦信号
# 基准 = 工具调用数 + skill/agent 调度数，反映真正有操作的动作数量
weighted_base = len(tool_calls) + len(skill_events) + len(agent_events)
friction_signals = 0
friction_signals += len(error_events) * 2
friction_signals += len(hook_blocks) * 3
friction_signals += len(alignment_issues)
friction_signals += len(recovery_patterns["IGNORE"]) * 2
friction_signals += len(recovery_patterns["RETRY"]) * 2
max_signals = max(weighted_base, 1)
friction_score = min(1.0, friction_signals / max_signals)

# === 读取转录 ===
transcript_file = os.environ.get('TRANSCRIPT_FILE', '')
user_corrections = []
transcript_missing = False
if transcript_file and os.path.exists(transcript_file):
    try:
        with open(transcript_file) as f:
            first_line = f.readline().strip()
            # 检查 transcript 缺失标记（由 trace-upload.sh 写入）
            if first_line:
                try:
                    marker = json.loads(first_line)
                    if marker.get("transcript_available") == False:
                        transcript_missing = True
                except json.JSONDecodeError:
                    pass
            # 非标记 → 回退指针，正常解析
            if not transcript_missing:
                f.seek(0)
                for line in f:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        entry = json.loads(line)
                    except json.JSONDecodeError:
                        continue
                    text = json.dumps(entry)
                    if any(kw in text.lower() for kw in [
                        "不要", "别", "stop", "不对", "错了", "重新",
                        "不要改", "不是这个", "换一个", "不应该"
                    ]):
                        user_corrections.append({
                            "ts": entry.get("ts", entry.get("timestamp", "")),
                            "snippet": text[:200]
                        })
    except Exception:
        pass

# === 异常检测 ===
anomalies = []
# 超时
for e in events:
    d = e.get("duration_ms", 0) or 0
    if d > 60000:
        anomalies.append({
            "type": "slow_call",
            "component": "tool",
            "detail": f"慢调用: {e.get('tool','')} ({d//1000}s)"
        })
# Agent 异常退出
for e in agent_events:
    if e.get("exit_code") is not None and e.get("exit_code") != 0:
        anomalies.append({
            "type": "agent_error",
            "component": f"agents/{e.get('agent_subtype','general')}.md",
            "detail": f"Agent 异常退出: {e.get('agent_subtype','')} exit_code={e.get('exit_code')}"
        })
# Hook 阻拦（大量同类拦截）
if len(hook_blocks) >= 3:
    block_tools = Counter(e.get("tool","") for e in hook_blocks)
    for tool, cnt in block_tools.most_common():
        if cnt >= 3:
            anomalies.append({
                "type": "hook_friction",
                "component": "hooks/",
                "detail": f"Hook 反复阻拦 {tool}: {cnt} 次（可能规则过严）"
            })

# === 组件归因 ===
# 映射表：信号来源 → [归属组件列表]
# 一个信号可能归属多个组件（如 hook 阻拦同时涉及 hooks/ 和 rules/）
component_signals = defaultdict(list)
for a in anomalies:
    comp = a.get("component", "unknown")
    component_signals[comp].append(a["detail"])
    # hook_friction 同时关联 rules/（hook 执行的是 rules 定义的规则）
    if a.get("type") == "hook_friction":
        component_signals["rules/"].append(f"Hook 阻拦反映的规则问题: {a['detail']}")

# 对齐问题归因
for ai in alignment_issues:
    if "agent" in ai["type"]:
        component_signals["agents/*.md"].append(ai["detail"])
    elif ai["type"] == "read_no_edit":
        # Read 后无编辑可能涉及 SKILL.md（流程缺失）或 templates/（模板未指引后续操作）
        component_signals["SKILL.md"].append(ai["detail"])
        component_signals["templates/"].append(ai["detail"])
    else:
        component_signals["SKILL.md"].append(ai["detail"])

# 恢复问题
if len(recovery_patterns["IGNORE"]) >= 3:
    component_signals["SKILL.md"].append(f"错误被静默忽略 {len(recovery_patterns['IGNORE'])} 次（缺少错误处理指导）")
if len(recovery_patterns["RETRY"]) >= 3:
    component_signals["SKILL.md"].append(f"重复尝试同一操作 {len(recovery_patterns['RETRY'])} 次（缺少退出条件）")

# 确保 SKILL.md、agents/、hooks/、rules/、templates/ 始终在归因表中出现
# （即使无信号也列为 0，提醒 harness-engineer 检查所有组件）
for default_comp in ["SKILL.md", "agents/*.md", "hooks/", "rules/", "templates/"]:
    if default_comp not in component_signals:
        component_signals[default_comp] = []  # 空列表 → aggregate 中列为 0 信号

# === 输出五层诊断报告 ===
tool_counter = Counter(e.get("tool", "unknown") for e in tool_calls)
agent_counter = Counter(e.get("agent_subtype", "general") for e in agent_events)

print(f"""## Session Trace Report
- session: {session_id}
- duration: {duration_min}min | events: {total_events} | skills: {", ".join(skills_used) if skills_used else "none"}
- friction_score: {friction_score:.2f} (success={success_rate:.0%})

### L1: 会话概览
| 指标 | 值 |
|------|-----|
| 总事件 | {total_events} |
| 成功率 | {success_rate:.0%} |
| Skill 调用 | {len(skill_events)} |
| Agent 派遣 | {len(agent_events)} |
| Hook 阻拦 | {len(hook_blocks)} |
| 执行对齐问题 | {len(alignment_issues)} |
| 用户纠正 | {len(user_corrections)}{' (transcript 未采集)' if transcript_missing else ''} |""")

if hook_blocks:
    print("| **Hook 阻拦详情** |", " / ".join(f"{e.get('tool','')}(seq={e.get('seq')})" for e in hook_blocks[:5]), "|")

print(f"""
### L2: Skill 下钻
| Skill | 工具调用 | 错误 | Agent | 耗时 | 重试 | 成功率 |
|-------|---------|------|-------|------|------|-------|""")
for sk, st in sorted(skill_stats.items(), key=lambda x: x[1]["calls"], reverse=True):
    err_rate = f"{st['errors']/st['calls']:.0%}" if st["calls"] > 0 else "-"
    print(f"| {sk} | {st['calls']} | {st['errors']} | {st['agents']} | {st['dur_ms']//1000}s | {st['retries']} | {err_rate} |")

if alignment_issues:
    print(f"""
### L3: 执行对齐
- 共 {len(alignment_issues)} 个对齐问题""")
    for ai in alignment_issues[:8]:
        print(f"- {ai['detail']}")

print(f"""
### L4: 恢复分类
| 模式 | 次数 | 含义 |
|------|------|------|
| RETRY | {len(recovery_patterns['RETRY'])} | 同工具重试 |
| ESCALATE | {len(recovery_patterns['ESCALATE'])} | 派遣 Agent 求助 |
| WORKAROUND | {len(recovery_patterns['WORKAROUND'])} | 换工具绕行 |
| IGNORE | {len(recovery_patterns['IGNORE'])} | 忽略继续 |""")

if component_signals:
    print("""
### L5: 组件归因
| 目标组件 | 信号数 | 摘要 |
|----------|--------|------|""")
    for comp, sigs in sorted(component_signals.items(), key=lambda x: len(x[1]), reverse=True):
        sig_count = len(sigs)
        summary = sigs[0][:80] if sigs else "-"
        print(f"| {comp} | {sig_count} | {redact(summary)} |")

    print("")
    print("### L5b: 信号-事件明细")
    print("| 目标组件 | 详情 |")
    print("|---|---|")
    for comp in sorted(component_signals):
        for sig in component_signals[comp][:20]:
            print(f"| {comp} | {redact(sig[:120])} |")

# 工具使用摘要
print("""
### 工具使用
| Tool | Calls | Errors |
|------|-------|--------|""")
for tool, count in tool_counter.most_common(10):
    err_count = sum(1 for e in error_events if e.get("tool") == tool)
    print(f"| {tool} | {count} | {err_count} |")

if agent_events:
    print("""
### Agent 派遣
| Agent | 次数 |
|-------|------|""")
    for agent, count in agent_counter.most_common():
        print(f"| {agent} | {count} |")

if user_corrections:
    print(f"""
### 用户纠正信号
- 检测到 {len(user_corrections)} 次可能的用户纠正""")
    for uc in user_corrections[:3]:
        snippet = redact(uc["snippet"])
        print(f"  - ...{snippet[-120:]}")

if anomalies:
    print("""
### 异常
""")
    for a in anomalies[:10]:
        print(f"- [{a['component']}] {redact(a['detail'])}")

print("""
### 事件时间线（前 30 条）
| Seq | Tool | Type | Active Skill | Summary |
|-----|------|------|-------------|---------|""")
for e in events[:30]:
    seq = e.get("seq", "?")
    tool = e.get("tool", "")
    etype = e.get("type", "")[:6]
    askill = e.get("active_skill", "")[:15]
    summary = redact((e.get("input_summary", "") or "")[:50])
    print(f"| {seq} | {tool} | {etype} | {askill} | {summary} |")
if len(events) > 30:
    print(f"| ... | ... | ... | ... | (省略 {len(events)-30} 条) |")
PYEOF
