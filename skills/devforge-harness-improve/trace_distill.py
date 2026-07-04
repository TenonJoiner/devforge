#!/usr/bin/env python3
"""单会话蒸馏（AHE 式分层下钻）。

读取原始 JSONL 事件 + 会话转录 → 生成五层 per-session 诊断报告。
用法: python3 trace_distill.py <events.jsonl> [transcript.jsonl]
"""

import json
import sys
import re
import os
from collections import defaultdict, Counter
from datetime import datetime


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


# === 信号可信度定义 ===
SIGNAL_CONFIDENCE = {
    "anomaly_slow_call": 0.8,
    "anomaly_agent_error": 0.9,
    "anomaly_hook_friction": 0.7,
    "alignment_agent_ignored": 0.9,
    "alignment_read_no_edit_code": 0.8,
    "alignment_read_no_edit_config": 0.3,
    "alignment_read_no_edit_plugin": 0.5,
    "alignment_grep_no_follow": 0.5,
    "recovery_ignore": 0.7,
    "recovery_retry": 0.7,
}

CODE_EXTS = {".py", ".sh", ".go", ".rs", ".c", ".cpp", ".cc", ".h", ".hpp",
             ".js", ".ts", ".jsx", ".tsx", ".java", ".kt", ".swift", ".rb",
             ".php", ".scala", ".clj", ".ex", ".exs"}


def classify_read_file(file_path):
    parts = file_path.strip("/").split("/")
    for i, p in enumerate(parts):
        if p == "skills" and i + 1 < len(parts) and parts[i+1].startswith("devforge-"):
            return ("SKILL.md", "alignment_read_no_edit_plugin")
        if p in ("templates", "agents", "hooks", "rules") and i > 0:
            comp = f"{p}/" if p != "agents" else "agents/*.md"
            return (comp, "alignment_read_no_edit_plugin")
    _, ext = os.path.splitext(file_path)
    if ext.lower() in CODE_EXTS:
        return (None, "alignment_read_no_edit_code")
    return (None, "alignment_read_no_edit_config")


def compute_weighted(comp_signals):
    type_counter = defaultdict(int)
    weighted = 0.0
    details = []
    for detail, confidence, sig_type in comp_signals:
        type_counter[sig_type] += 1
        occurrence = type_counter[sig_type]
        decay = 1.0 / (1.0 + 0.3 * (occurrence - 1))
        weighted += confidence * decay
        details.append(detail)
    return (round(weighted, 1), len(comp_signals), details)


def distill(events_file, transcript_file=""):
    """执行蒸馏，返回诊断报告 Markdown 字符串。"""
    # === 读取事件 ===
    events = []
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
        return "(无事件数据)"

    events.sort(key=lambda e: e.get("seq", 0))

    # Duration fallback: 当 duration_ms=0 时，用 tool_intent._ts 计算
    _intent_index = {}
    for e in events:
        if e.get("type") == "tool_intent" and "_ts" in e:
            _intent_index[e["seq"]] = e

    for e in events:
        if e.get("type") != "tool_call":
            continue
        if (e.get("duration_ms", 0) or 0) > 0:
            continue
        _tool = e.get("tool", "")
        for _iseq in sorted(_intent_index.keys(), reverse=True):
            if _iseq >= e["seq"]:
                continue
            _intent = _intent_index[_iseq]
            if _intent.get("tool") != _tool:
                continue
            _its = _intent.get("_ts", 0)
            if not _its:
                continue
            try:
                _cdt = datetime.strptime(e.get("ts", ""), "%Y-%m-%dT%H:%M:%S")
                _wall_ms = int((_cdt.timestamp() - _its) * 1000)
                if 0 < _wall_ms < 600000:
                    e["duration_ms"] = _wall_ms
            except Exception:
                pass
            break

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

    # === Hook 阻拦检测：FIFO 精确匹配 intent → call ===
    intents_fifo = [(e["seq"], e["tool"]) for e in sorted(tool_intents, key=lambda x: x["seq"])]
    calls_fifo = [(e["seq"], e["tool"]) for e in sorted(tool_calls, key=lambda x: x["seq"])]
    completed_intent_seqs = set()
    call_used = [False] * len(calls_fifo)
    for intent_seq, intent_tool in intents_fifo:
        for i, (call_seq, call_tool) in enumerate(calls_fifo):
            if call_used[i]:
                continue
            if call_seq > intent_seq and call_tool == intent_tool:
                completed_intent_seqs.add(intent_seq)
                call_used[i] = True
                break
    hook_blocks = [e for e in tool_intents if e["seq"] not in completed_intent_seqs]

    # === Hook 阻拦位置分级 ===
    total_event_count = len(events)
    early_blocks = mid_blocks = late_blocks = 0
    for e in hook_blocks:
        seq = e.get("seq", 0)
        if total_event_count > 0:
            ratio = seq / total_event_count
            if ratio < 0.2:
                early_blocks += 1
            elif ratio > 0.8:
                late_blocks += 1
            else:
                mid_blocks += 1
        else:
            mid_blocks += 1

    # === 成功率 ===
    success_rate = 1.0
    if tool_calls:
        success_rate = (len(tool_calls) - len(error_events)) / len(tool_calls)

    # === 会话时长 ===
    duration_min = 0
    try:
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

    # 重试检测
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
            inp = e.get("input_summary", "")[:80]
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

    for i, e in enumerate(events[:-1]):
        if e.get("tool") != "Grep":
            continue
        if e.get("result", {}).get("status") == "error":
            continue
        next_e = events[i+1] if i+1 < len(events) else None
        if next_e and next_e.get("tool") in ("Grep", "Read"):
            continue
        alignment_issues.append({
            "type": "grep_no_follow",
            "seq": e.get("seq"),
            "detail": f"seq={e.get('seq')} Grep 结果未被后续工具消费（下一动作为 {next_e.get('tool', '?') if next_e else '?'}）"
        })

    for i, e in enumerate(events[:-2]):
        if e.get("type") != "agent_dispatch":
            continue
        agent_type = e.get("agent_subtype", "general")
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

    REFERENCE_EXTS = {".md", ".json", ".yaml", ".yml", ".toml", ".txt", ".lock", ".xml", ".csv"}
    for i, e in enumerate(events[:-1]):
        if e.get("tool") != "Read":
            continue
        file_path = e.get("input_summary", "") or ""
        if not file_path:
            continue
        _, ext = os.path.splitext(file_path)
        if ext.lower() in REFERENCE_EXTS:
            continue
        next_e = events[i+1] if i+1 < len(events) else None
        if next_e and next_e.get("tool") in ("Read", "Grep", "Glob"):
            continue
        referenced = False
        for j in range(i+1, min(i+6, len(events))):
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
                "file_path": file_path,
                "detail": f"seq={e.get('seq')} Read({file_path[:60]}) 后 5 步内未编辑/引用该文件"
            })

    # === L4: 恢复行为分类 ===
    recovery_patterns = {"RETRY": [], "ESCALATE": [], "IGNORE": [], "WORKAROUND": []}
    for i, e in enumerate(error_events):
        remaining = events[i+1:i+4]
        if not remaining:
            recovery_patterns["IGNORE"].append(e.get("seq"))
            continue
        next_e = remaining[0]
        if (next_e.get("tool") == e.get("tool") and
            next_e.get("input_summary", "")[:80] == e.get("input_summary", "")[:80]):
            recovery_patterns["RETRY"].append(e.get("seq"))
        elif any(r.get("type") == "agent_dispatch" for r in remaining):
            recovery_patterns["ESCALATE"].append(e.get("seq"))
        elif next_e.get("type") == "tool_call" and next_e.get("tool") != e.get("tool"):
            recovery_patterns["WORKAROUND"].append(e.get("seq"))
        else:
            recovery_patterns["IGNORE"].append(e.get("seq"))

    # === 摩擦评分 (0.0-1.0) ===
    weighted_base = len(tool_calls) + len(skill_events) + len(agent_events)
    friction_signals = 0
    friction_signals += len(error_events) * 2
    friction_signals += early_blocks * 1
    friction_signals += mid_blocks * 3
    friction_signals += late_blocks * 1
    friction_signals += len(alignment_issues)
    friction_signals += len(recovery_patterns["IGNORE"]) * 2
    friction_signals += len(recovery_patterns["RETRY"]) * 2
    slow_calls = [e for e in tool_calls if (e.get("duration_ms", 0) or 0) > 30000]
    friction_signals += len(slow_calls) * 2

    if weighted_base < 5:
        effective_base = weighted_base + (5 - weighted_base) * 0.5
    else:
        effective_base = weighted_base

    friction_score = min(1.0, friction_signals / max(effective_base, 1))

    # === 读取转录 ===
    user_corrections = []
    transcript_missing = False
    if transcript_file and os.path.exists(transcript_file):
        try:
            with open(transcript_file) as f:
                first_line = f.readline().strip()
                if first_line:
                    try:
                        marker = json.loads(first_line)
                        if marker.get("transcript_available") == False:
                            transcript_missing = True
                    except json.JSONDecodeError:
                        pass
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
                        msg = entry.get("message", {}) if isinstance(entry.get("message"), dict) else {}
                        role = (entry.get("role", "") or entry.get("type", "") or msg.get("role", "") or "").lower()
                        if role not in ("user", "human"):
                            continue
                        text = entry.get("content", "") or entry.get("text", "") or msg.get("content", "") or json.dumps(entry)
                        text_lower = text.lower()
                        if "<local-command" in text_lower or "<system-reminder>" in text_lower:
                            continue
                        if role == "user" and (text.strip().startswith("<command-name>") or text.strip().startswith("<command-message>")):
                            continue
                        cn_kw = ["不要", "别", "不对", "错了", "重新", "不要改", "不是这个", "换一个", "不应该"]
                        en_kw = ["no,", "wrong", "incorrect", "don't", "do not", "stop", "that's not", "that is not", "redo", "start over", "try again", "instead"]
                        if any(kw in text_lower for kw in cn_kw + en_kw):
                            user_corrections.append({
                                "ts": entry.get("ts", entry.get("timestamp", "")),
                                "snippet": text[:200]
                            })
        except Exception:
            pass

    # === 异常检测 ===
    anomalies = []
    for e in events:
        d = e.get("duration_ms", 0) or 0
        if d > 60000:
            anomalies.append({
                "type": "slow_call",
                "component": "tool",
                "detail": f"慢调用: {e.get('tool','')} ({d//1000}s)"
            })
    for e in agent_events:
        if e.get("exit_code") is not None and e.get("exit_code") != 0:
            anomalies.append({
                "type": "agent_error",
                "component": f"agents/{e.get('agent_subtype','general')}.md",
                "detail": f"Agent 异常退出: {e.get('agent_subtype','')} exit_code={e.get('exit_code')}"
            })
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
    component_signals = defaultdict(list)

    for a in anomalies:
        comp = a.get("component", "unknown")
        atype = a.get("type", "")
        conf = SIGNAL_CONFIDENCE.get(f"anomaly_{atype}", 0.5)
        component_signals[comp].append((a["detail"], conf, f"anomaly_{atype}"))
        if atype == "hook_friction":
            component_signals["rules/"].append((
                f"Hook 阻拦反映的规则问题: {a['detail']}", conf, f"anomaly_{atype}"))

    for ai in alignment_issues:
        atype = ai["type"]
        if atype == "agent_result_ignored":
            conf = SIGNAL_CONFIDENCE["alignment_agent_ignored"]
            component_signals["agents/*.md"].append((ai["detail"], conf, atype))
        elif atype == "read_no_edit":
            file_path = ai.get("file_path", "")
            comp, conf_type = classify_read_file(file_path) if file_path else (None, "alignment_read_no_edit_config")
            conf = SIGNAL_CONFIDENCE.get(conf_type, 0.3)
            if comp:
                component_signals[comp].append((ai["detail"], conf, atype))
            else:
                component_signals["SKILL.md"].append((ai["detail"], conf, atype))
        elif atype == "grep_no_follow":
            conf = SIGNAL_CONFIDENCE["alignment_grep_no_follow"]
            component_signals["SKILL.md"].append((ai["detail"], conf, atype))
        else:
            component_signals["SKILL.md"].append((ai["detail"], 0.5, atype))

    if len(recovery_patterns["IGNORE"]) >= 3:
        conf = SIGNAL_CONFIDENCE["recovery_ignore"]
        component_signals["SKILL.md"].append((
            f"错误被静默忽略 {len(recovery_patterns['IGNORE'])} 次（缺少错误处理指导）", conf, "recovery_ignore"))
    if len(recovery_patterns["RETRY"]) >= 3:
        conf = SIGNAL_CONFIDENCE["recovery_retry"]
        component_signals["SKILL.md"].append((
            f"重复尝试同一操作 {len(recovery_patterns['RETRY'])} 次（缺少退出条件）", conf, "recovery_retry"))

    for default_comp in ["SKILL.md", "agents/*.md", "hooks/", "rules/", "templates/"]:
        if default_comp not in component_signals:
            component_signals[default_comp] = []

    weighted_components = {}
    for comp, sigs in component_signals.items():
        weighted_components[comp] = compute_weighted(sigs)

    # === 输出五层诊断报告 ===
    tool_counter = Counter(e.get("tool", "unknown") for e in tool_calls)
    agent_counter = Counter(e.get("agent_subtype", "general") for e in agent_events)

    lines = []
    lines.append(f"""## Session Trace Report
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
        lines.append("| **Hook 阻拦详情** | " + " / ".join(f"{e.get('tool','')}(seq={e.get('seq')})" for e in hook_blocks[:5]) + " |")
        pos_parts = []
        if early_blocks: pos_parts.append(f"初期{early_blocks}")
        if mid_blocks: pos_parts.append(f"中期{mid_blocks}")
        if late_blocks: pos_parts.append(f"末期{late_blocks}")
        if pos_parts:
            lines.append("| **Hook 位置分布** | " + " / ".join(pos_parts) + " （初期=前20% / 末期=后20%）|")

    lines.append(f"""
### L2: Skill 下钻
| Skill | 工具调用 | 错误 | Agent | 耗时 | 重试 | 成功率 |
|-------|---------|------|-------|------|------|-------|""")
    for sk, st in sorted(skill_stats.items(), key=lambda x: x[1]["calls"], reverse=True):
        err_rate = f"{st['errors']/st['calls']:.0%}" if st["calls"] > 0 else "-"
        lines.append(f"| {sk} | {st['calls']} | {st['errors']} | {st['agents']} | {st['dur_ms']//1000}s | {st['retries']} | {err_rate} |")

    if alignment_issues:
        lines.append(f"""
### L3: 执行对齐
- 共 {len(alignment_issues)} 个对齐问题""")
        for ai in alignment_issues[:8]:
            lines.append(f"- {ai['detail']}")

    lines.append(f"""
### L4: 恢复分类
| 模式 | 次数 | 含义 |
|------|------|------|
| RETRY | {len(recovery_patterns['RETRY'])} | 同工具重试 |
| ESCALATE | {len(recovery_patterns['ESCALATE'])} | 派遣 Agent 求助 |
| WORKAROUND | {len(recovery_patterns['WORKAROUND'])} | 换工具绕行 |
| IGNORE | {len(recovery_patterns['IGNORE'])} | 忽略继续 |""")

    if component_signals:
        lines.append("""
### L5: 组件归因
| 目标组件 | 信号数 | 加权信号 | 摘要 |
|----------|--------|---------|------|""")
        for comp, (w, raw, details) in sorted(weighted_components.items(), key=lambda x: x[1][0], reverse=True):
            summary = details[0][:80] if details else "-"
            lines.append(f"| {comp} | {raw} | {w} | {redact(summary)} |")

        lines.append("")
        lines.append("### L5b: 信号-事件明细")
        lines.append("| 目标组件 | 详情 |")
        lines.append("|---|---|")
        for comp in sorted(component_signals):
            for detail, confidence, sig_type in component_signals[comp][:20]:
                lines.append(f"| {comp} | {redact(detail[:120])} |")

    lines.append("""
### 工具使用
| Tool | Calls | Errors |
|------|-------|--------|""")
    for tool, count in tool_counter.most_common(10):
        err_count = sum(1 for e in error_events if e.get("tool") == tool)
        lines.append(f"| {tool} | {count} | {err_count} |")

    if agent_events:
        lines.append("""
### Agent 派遣
| Agent | 次数 |
|-------|------|""")
        for agent, count in agent_counter.most_common():
            lines.append(f"| {agent} | {count} |")

    if user_corrections:
        lines.append(f"""
### 用户纠正信号
- 检测到 {len(user_corrections)} 次可能的用户纠正""")
        for uc in user_corrections[:3]:
            snippet = redact(uc["snippet"])
            lines.append(f"  - ...{snippet[-120:]}")

    if anomalies:
        lines.append("""
### 异常
""")
        for a in anomalies[:10]:
            lines.append(f"- [{a['component']}] {redact(a['detail'])}")

    lines.append("""
### 事件时间线（前 30 条）
| Seq | Tool | Type | Active Skill | Summary |
|-----|------|------|-------------|---------|""")
    for e in events[:30]:
        seq = e.get("seq", "?")
        tool = e.get("tool", "")
        etype = e.get("type", "")[:6]
        askill = e.get("active_skill", "")[:15]
        summary = redact((e.get("input_summary", "") or "")[:50])
        lines.append(f"| {seq} | {tool} | {etype} | {askill} | {summary} |")
    if len(events) > 30:
        lines.append(f"| ... | ... | ... | ... | (省略 {len(events)-30} 条) |")

    # === 数据质量检查 ===
    dq_warnings = []
    all_dur = [e.get("duration_ms", 0) or 0 for e in tool_calls]
    if all_dur and all(d == 0 for d in all_dur):
        dq_warnings.append("duration_ms 全为 0：PreToolUse/PostToolUse hook 未正确记录耗时，慢调用检测和 Skill 耗时统计失效")
    if len(skill_events) == 0 and len(agent_events) == 0 and len(tool_calls) > 10:
        dq_warnings.append("零 Skill/Agent 事件：会话可能未使用 DevForge skill，或 agent_dispatch 采集缺失")
    if duration_min > 480:
        dq_warnings.append(f"会话时长 {duration_min}min（{duration_min//60}h）异常长，可能为跨天/跨周末会话，非数据采集错误但摩擦评分等时间敏感指标可能失真")
    if alignment_issues:
        read_only = sum(1 for a in alignment_issues if a["type"] == "read_no_edit")
        if read_only == len(alignment_issues) and read_only > 3:
            dq_warnings.append(f"对齐问题 {read_only}/{len(alignment_issues)} 均为 Read-未编辑，可能全部为探索性阅读而非流程缺陷")

    if dq_warnings:
        lines.append("""
### 数据质量""")
        for w in dq_warnings:
            lines.append(f"- ⚠ {w}")

    return "\n".join(lines)


def main():
    if len(sys.argv) < 2:
        print("用法: python3 trace_distill.py <events.jsonl> [transcript.jsonl]", file=sys.stderr)
        sys.exit(1)

    events_file = sys.argv[1]
    transcript_file = sys.argv[2] if len(sys.argv) > 2 else ""

    if not os.path.exists(events_file):
        print(f"错误: 事件文件不存在: {events_file}", file=sys.stderr)
        sys.exit(1)

    report = distill(events_file, transcript_file)
    print(report)


if __name__ == "__main__":
    main()
