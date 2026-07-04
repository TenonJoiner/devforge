#!/usr/bin/env python3
"""跨会话聚合（组件级诊断）。

读取多份 per-session 蒸馏报告 → 生成跨开发者热点分析。
用法: python3 aggregate.py <report_dir>
"""

import sys
import os
import re
from collections import defaultdict, Counter


def parse_reports(report_dir):
    """解析 report_dir 下所有 .md 蒸馏报告，返回 sessions 列表。"""
    reports = []
    for fname in sorted(os.listdir(report_dir)):
        if not fname.endswith(".md"):
            continue
        fpath = os.path.join(report_dir, fname)
        with open(fpath) as f:
            reports.append({"file": fname, "content": f.read()})

    kv_row_re = re.compile(r"^\|\s*(.+?)\s*\|\s*(.+?)\s*\|")
    skill_row_re = re.compile(r"^\|\s*(\S+)\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|\s*(\d+)s\s*\|\s*(\d+)\s*\|\s*(\S+)\s*\|")
    recovery_row_re = re.compile(r"^\|\s*(\w+)\s*\|\s*(\d+)\s*\|")
    component_row_re = re.compile(r"^\|\s*(\S+)\s*\|\s*(\d+)\s*\|\s*(?:([\d.]+)\s*\|\s*)?(.+?)\s*\|")
    tool_row_re = re.compile(r"^\|\s*(\S+)\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|")
    agent_row_re = re.compile(r"^\|\s*(\S+)\s*\|\s*(\d+)\s*\|")
    anomaly_item_re = re.compile(r"^-\s*\[(\S+)\]\s+(.+)")
    detail_row_re = re.compile(r"^\|\s*(\S+)\s*\|\s*(.+?)\s*\|")

    sessions = []
    parse_errors = []

    for r in reports:
        content = r["content"]
        lines = content.split("\n")

        s = {
            "session": "unknown",
            "file": r["file"],
            "duration_min": 0,
            "events": 0,
            "friction_score": 0.0,
            "success_rate": 0.0,
            "skills": [],
            "skill_stats": {},
            "alignment_count": 0,
            "recovery": {},
            "components": {},
            "hook_blocks": 0,
            "correction_count": 0,
            "tools": {},
            "agents": {},
            "anomaly_count": 0,
            "anomaly_items": [],
            "signal_details": [],
            "dq_warnings": [],
            "hook_pos_early": 0,
            "hook_pos_mid": 0,
            "hook_pos_late": 0,
        }

        current_section = None

        for line in lines:
            ls = line.strip()

            if ls.startswith("- session:"):
                s["session"] = ls.split(":", 1)[1].strip()
            elif ls.startswith("- duration:"):
                m = re.search(r"duration:\s*(\d+)min\s*\|\s*events:\s*(\d+)", ls)
                if m:
                    s["duration_min"] = int(m.group(1))
                    s["events"] = int(m.group(2))
                sm = re.search(r"skills:\s*(.+)", ls)
                if sm and sm.group(1).strip() != "none":
                    s["skills"] = [sk.strip() for sk in sm.group(1).split(",") if sk.strip()]
            elif ls.startswith("- friction_score:"):
                m = re.search(r"friction_score:\s*([\d.]+)\s*.*success=(\d+)%", ls)
                if m:
                    s["friction_score"] = float(m.group(1))
                    s["success_rate"] = int(m.group(2)) / 100

            if ls.startswith("### L1:"):
                current_section = "L1"
                continue
            elif ls.startswith("### L2:"):
                current_section = "L2"
                continue
            elif ls.startswith("### L3:"):
                current_section = "L3"
                continue
            elif ls.startswith("### L4:"):
                current_section = "L4"
                continue
            elif ls.startswith("### L5:"):
                current_section = "L5"
                continue
            elif ls.startswith("### L5b"):
                current_section = "L5b"
                continue
            elif ls.startswith("### 工具使用"):
                current_section = "tools"
                continue
            elif ls.startswith("### Agent"):
                current_section = "agents"
                continue
            elif ls.startswith("### 异常"):
                current_section = "anomalies"
                continue
            elif ls.startswith("### 用户纠正"):
                current_section = "corrections"
                continue
            elif ls.startswith("### 数据质量"):
                current_section = "data_quality"
                continue
            elif ls.startswith("### "):
                current_section = None
                continue

            if ls.startswith("|---") or ls.startswith("| --") or not ls.startswith("|"):
                continue

            if current_section == "L1":
                m = kv_row_re.match(ls)
                if m:
                    key = m.group(1).strip()
                    val = m.group(2).strip()
                    if "Hook 阻拦" in key:
                        try:
                            s["hook_blocks"] = int(val)
                        except ValueError:
                            pass

            elif current_section == "L2":
                m = skill_row_re.match(ls)
                if m:
                    s["skill_stats"][m.group(1)] = {
                        "calls": int(m.group(2)),
                        "errors": int(m.group(3)),
                        "agents": int(m.group(4)),
                        "dur_s": int(m.group(5)),
                        "retries": int(m.group(6)),
                        "error_rate_str": m.group(7),
                    }

            elif current_section == "L3":
                if ls.startswith("|- 共"):
                    m = re.search(r"共\s*(\d+)\s*个", ls)
                    if m:
                        s["alignment_count"] = int(m.group(1))

            elif current_section == "L4":
                m = recovery_row_re.match(ls)
                if m:
                    key = m.group(1).strip()
                    try:
                        s["recovery"][key] = int(m.group(2))
                    except ValueError:
                        pass

            elif current_section == "L5":
                m = component_row_re.match(ls)
                if m:
                    weighted_val = float(m.group(3)) if m.group(3) else float(m.group(2))
                    s["components"][m.group(1).strip()] = {
                        "signals": int(m.group(2)),
                        "weighted": weighted_val,
                        "summary": (m.group(4) or "").strip(),
                    }

            elif current_section == "L5b":
                m = detail_row_re.match(ls)
                if m:
                    s["signal_details"].append({
                        "component": m.group(1).strip(),
                        "detail": m.group(2).strip(),
                    })

            elif current_section == "tools":
                m = tool_row_re.match(ls)
                if m:
                    s["tools"][m.group(1)] = {"calls": int(m.group(2)), "errors": int(m.group(3))}

            elif current_section == "agents":
                m = agent_row_re.match(ls)
                if m:
                    s["agents"][m.group(1)] = int(m.group(2))

            elif current_section == "anomalies":
                m = anomaly_item_re.match(ls)
                if m:
                    s["anomaly_count"] += 1
                    s["anomaly_items"].append({
                        "component": m.group(1).strip(),
                        "detail": m.group(2).strip(),
                    })

            elif current_section == "corrections":
                m = re.search(r"检测到\s+(\d+)\s+次", ls)
                if m:
                    s["correction_count"] = int(m.group(1))

            elif current_section == "data_quality":
                if ls.startswith("- "):
                    s["dq_warnings"].append(ls[2:].strip())

            if "Hook 位置分布" in ls:
                hm = re.search(r"初期(\d+)", ls)
                if hm:
                    s["hook_pos_early"] = int(hm.group(1))
                hm = re.search(r"中期(\d+)", ls)
                if hm:
                    s["hook_pos_mid"] = int(hm.group(1))
                hm = re.search(r"末期(\d+)", ls)
                if hm:
                    s["hook_pos_late"] = int(hm.group(1))

        sessions.append(s)

    return sessions, len(reports)


def aggregate(sessions):
    """跨会话聚合，返回 (report_lines, check_data)。"""
    check_data = {}  # for self-check
    total_sessions = len(sessions)

    # --- 组件故障热点 ---
    component_hotspots = defaultdict(lambda: {"total_signals": 0, "total_weighted": 0.0, "sessions": 0, "summaries": []})
    for s in sessions:
        for comp, data in s["components"].items():
            component_hotspots[comp]["total_signals"] += data["signals"]
            component_hotspots[comp]["total_weighted"] += data.get("weighted", data["signals"])
            component_hotspots[comp]["sessions"] += 1
            component_hotspots[comp]["summaries"].append(data["summary"])

    # --- Skill 级聚合 ---
    skill_agg = defaultdict(lambda: {"calls": 0, "errors": 0, "agents": 0, "dur_s": 0, "retries": 0, "sessions": 0})
    for s in sessions:
        for sk, st in s["skill_stats"].items():
            skill_agg[sk]["calls"] += st["calls"]
            skill_agg[sk]["errors"] += st["errors"]
            skill_agg[sk]["agents"] += st["agents"]
            skill_agg[sk]["dur_s"] += st["dur_s"]
            skill_agg[sk]["retries"] += st["retries"]
            skill_agg[sk]["sessions"] += 1

    # --- 恢复模式趋势 ---
    recovery_totals = Counter()
    for s in sessions:
        for mode, cnt in s["recovery"].items():
            recovery_totals[mode] += cnt

    # --- 执行对齐趋势 ---
    total_alignment = sum(s["alignment_count"] for s in sessions)
    alignment_sessions = sum(1 for s in sessions if s["alignment_count"] > 0)

    # --- 摩擦评分趋势 ---
    friction_scores = [s["friction_score"] for s in sessions if s["friction_score"] > 0]
    avg_friction = sum(friction_scores) / len(friction_scores) if friction_scores else 0
    high_friction = [s for s in sessions if s["friction_score"] >= 0.3]

    # --- Hook 阻拦聚合 ---
    total_hook_blocks = sum(s["hook_blocks"] for s in sessions)

    # --- 工具/Agent 聚合 ---
    tool_agg = defaultdict(lambda: {"calls": 0, "errors": 0, "sessions": 0})
    agent_agg = defaultdict(lambda: {"calls": 0, "sessions": 0})
    for s in sessions:
        for tool, data in s["tools"].items():
            tool_agg[tool]["calls"] += data["calls"]
            tool_agg[tool]["errors"] += data["errors"]
            tool_agg[tool]["sessions"] += 1
        for agent, count in s["agents"].items():
            agent_agg[agent]["calls"] += count
            agent_agg[agent]["sessions"] += 1

    # --- 纠正热点 ---
    correction_hotspots = defaultdict(int)
    for s in sessions:
        if s["correction_count"] > 0:
            for sk in s["skills"]:
                correction_hotspots[sk] += 1
    correction_hotspots = {sk: cnt for sk, cnt in correction_hotspots.items() if cnt >= 3}

    # --- 跨会话异常聚类 ---
    anomaly_clusters = Counter()
    for s in sessions:
        for item in s["anomaly_items"]:
            key = f"{item['component']}: {item['detail'][:60]}"
            anomaly_clusters[key] += 1

    # --- 自检数据收集 ---
    check_data["total_sessions"] = total_sessions
    check_data["total_alignment"] = total_alignment
    check_data["total_hook_blocks"] = total_hook_blocks
    check_data["component_count"] = len(component_hotspots)
    sessions_with_signals = sum(1 for s in sessions if s["components"])
    check_data["sessions_with_signals"] = sessions_with_signals
    non_zero_components = sum(1 for comp, data in component_hotspots.items() if data["total_signals"] > 0)
    check_data["non_zero_components"] = non_zero_components

    # === 输出聚合报告 ===
    lines = []
    lines.append(f"""# Harness 诊断聚合报告

## 概览
- 分析 {total_sessions} 个会话
- 平均摩擦评分: {avg_friction:.2f}（{'低摩擦' if avg_friction < 0.2 else '中摩擦' if avg_friction < 0.4 else '高摩擦'}）
- 高摩擦会话: {len(high_friction)}/{total_sessions}（friction >= 0.3）
- 执行对齐问题: {total_alignment} 次 (涉及 {alignment_sessions} 个会话)
- Hook 总阻拦: {total_hook_blocks} 次（初期: {sum(s['hook_pos_early'] for s in sessions)}, 中期: {sum(s['hook_pos_mid'] for s in sessions)}, 末期: {sum(s['hook_pos_late'] for s in sessions)}）
""")

    hotspot_entries = [(comp, data) for comp, data in component_hotspots.items() if data["sessions"] >= 2 and data["total_weighted"] >= 1.0]
    if hotspot_entries:
        lines.append("""
## 组件故障热点（跨会话共现 ≥2，加权信号 ≥1.0）
| 组件 | 信号总数 | 加权信号 | 涉及会话 | 典型摘要 |
|------|---------|---------|---------|---------|""")
        for comp, data in sorted(hotspot_entries, key=lambda x: x[1]["total_weighted"], reverse=True):
            top_summary = Counter(data["summaries"]).most_common(1)[0][0][:80] if data["summaries"] else "(摘要缺失)"
            lines.append(f"| {comp} | {data['total_signals']} | {data['total_weighted']:.1f} | {data['sessions']} | {top_summary} |")

    if any(s.get("signal_details") for s in sessions):
        lines.append("""
## 信号溯源""")
        for s in sessions:
            if s.get("signal_details"):
                lines.append(f"### 会话 {s['session'][:12]}")
                for sd in s["signal_details"][:5]:
                    lines.append(f"- {sd['component']} — {sd['detail']}")

    if skill_agg:
        lines.append("""
## Skill 级聚合
| Skill | 会话数 | 总调用 | 总错误 | 平均耗时 | 总重试 | 错误率 |
|-------|--------|--------|--------|---------|--------|-------|""")
        for sk, st in sorted(skill_agg.items(), key=lambda x: x[1]["calls"], reverse=True):
            err_rate = f"{st['errors']/st['calls']:.0%}" if st["calls"] > 0 else "-"
            avg_dur = f"{st['dur_s']//st['sessions']}s" if st["sessions"] > 0 else "-"
            lines.append(f"| {sk} | {st['sessions']} | {st['calls']} | {st['errors']} | {avg_dur} | {st['retries']} | {err_rate} |")

    total_recovery = sum(recovery_totals.values())
    if total_recovery > 0:
        lines.append(f"""
## 恢复模式分布
| 模式 | 总次数 | 占比 |
|------|--------|------|""")
        for mode in ["RETRY", "ESCALATE", "WORKAROUND", "IGNORE"]:
            cnt = recovery_totals.get(mode, 0)
            pct = f"{cnt/total_recovery:.0%}"
            lines.append(f"| {mode} | {cnt} | {pct} |")

        if recovery_totals.get("IGNORE", 0) > total_recovery * 0.4:
            lines.append("\n**警告**: IGNORE 占比过高（>40%），harness 缺少错误处理指导")
        if recovery_totals.get("RETRY", 0) > total_recovery * 0.3:
            lines.append("\n**警告**: RETRY 占比过高（>30%），存在无效重试循环，skill 缺少退出条件")

    if correction_hotspots:
        lines.append("""
## 纠正热点（≥3 会话共现）
| Skill | 会话数 |
|-------|--------|""")
        for sk, cnt in sorted(correction_hotspots.items(), key=lambda x: x[1], reverse=True):
            lines.append(f"| {sk} | {cnt} |")

    if high_friction:
        lines.append("""
## 高摩擦会话
| Session | Friction | Skill |
|---------|----------|-------|""")
        for s in sorted(high_friction, key=lambda x: x["friction_score"], reverse=True)[:10]:
            skills_short = ", ".join(s["skills"][:2])
            lines.append(f"| {s['session'][:12]} | {s['friction_score']:.2f} | {skills_short} |")

    if anomaly_clusters:
        lines.append("""
## 异常跨会话频率（≥2 会话共现）
| 异常模式 | 会话数 |
|---------|--------|""")
        for pattern, cnt in anomaly_clusters.most_common(15):
            if cnt >= 2:
                lines.append(f"| {pattern[:100]} | {cnt} |")

    if tool_agg:
        lines.append("""
## 工具使用聚合
| Tool | 总调用 | 总错误 | 错误率 | 出现会话 |
|------|--------|--------|--------|---------|""")
        for tool, data in sorted(tool_agg.items(), key=lambda x: x[1]["calls"], reverse=True):
            err_rate = f"{data['errors']/data['calls']:.1%}" if data["calls"] > 0 else "-"
            lines.append(f"| {tool} | {data['calls']} | {data['errors']} | {err_rate} | {data['sessions']} |")

    if agent_agg:
        lines.append("""
## Agent 派遣聚合
| Agent | 总派遣 | 出现会话 |
|-------|--------|---------|""")
        for agent, data in sorted(agent_agg.items(), key=lambda x: x[1]["calls"], reverse=True):
            lines.append(f"| {agent} | {data['calls']} | {data['sessions']} |")

    # --- 数据质量汇总 ---
    dq_summary = Counter()
    for s in sessions:
        for w in s["dq_warnings"]:
            dq_summary[w] += 1
    if dq_summary:
        lines.append("""
## 数据质量
| 告警 | 涉及会话数 |
|------|-----------|""")
        for w, cnt in dq_summary.most_common():
            lines.append(f"| {w[:120]} | {cnt} |")

    lines.append("""
## 会话列表
| Session | 时长 | 事件 | Friction | Skills | 对齐 | Blocks | 纠正 |
|---------|------|------|----------|--------|------|--------|------|""")
    for s in sessions:
        skills_short = ", ".join(s["skills"][:2])
        if len(s["skills"]) > 2:
            skills_short += f" +{len(s['skills'])-2}"
        lines.append(f"| {s['session'][:12]} | {s['duration_min']}min | {s['events']} | {s['friction_score']:.2f} | {skills_short} | {s['alignment_count']} | {s['hook_blocks']} | {s['correction_count']} |")

    return lines, check_data


def self_check(check_data, report_count):
    """生成解析自检摘要。"""
    lines = []
    lines.append("""
## 解析自检
| 字段 | 预期 | 实际 | 状态 |
|------|------|------|------|""")

    # 报告文件数 vs 解析会话数
    total = check_data.get("total_sessions", 0)
    status = "OK" if total >= report_count else "MISMATCH"
    lines.append(f"| 输入报告文件数 | {report_count} | — | — |")
    lines.append(f"| 解析会话数 | ≥1 | {total} | {'OK' if total >= 1 else 'WARN'} |")
    if total != report_count:
        lines.append(f"| 报告-会话匹配 | {report_count} | {total} | MISMATCH (解析丢失 {report_count - total} 个报告) |")

    # 非零组件信号会话数
    sessions_with_signals = check_data.get("sessions_with_signals", 0)
    non_zero = check_data.get("non_zero_components", 0)
    status = "OK" if sessions_with_signals > 0 or total == 0 else "WARN"
    lines.append(f"| 含组件信号的会话 | >0 | {sessions_with_signals} | {status} |")
    lines.append(f"| 非零信号组件数 | — | {non_zero} | — |")

    # 关键字段零值告警
    total_alignment = check_data.get("total_alignment", 0)
    total_hook_blocks = check_data.get("total_hook_blocks", 0)
    if total_alignment == 0 and total > 0:
        lines.append(f"| 执行对齐总数 | >0 (来自输入) | 0 | WARN (可能解析失败或全部会话无对齐问题) |")
    if total_hook_blocks == 0 and total > 0:
        lines.append(f"| Hook 阻拦总数 | ≥0 | 0 | INFO (若输入确实无阻拦则为正常) |")

    return "\n".join(lines)


def main():
    if len(sys.argv) < 2:
        print("用法: python3 aggregate.py <report_dir>", file=sys.stderr)
        sys.exit(1)

    report_dir = sys.argv[1]
    if not os.path.isdir(report_dir):
        print(f"错误: 目录不存在: {report_dir}", file=sys.stderr)
        sys.exit(1)

    sessions, report_count = parse_reports(report_dir)

    if not sessions:
        print("(无蒸馏报告)")
        sys.exit(0)

    report_lines, check_data = aggregate(sessions)

    # 输出主报告
    print("\n".join(report_lines))

    # 输出自检摘要
    print(self_check(check_data, report_count))


if __name__ == "__main__":
    main()
