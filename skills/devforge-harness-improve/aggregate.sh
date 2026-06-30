#!/bin/bash
# aggregate.sh — 跨会话聚合（组件级诊断）
# 读取多份五层 per-session 诊断报告 → 生成跨开发者热点分析
# 用法: aggregate.sh <report_dir> > overview.md

set -e

if ! command -v python3 &>/dev/null; then
    echo "错误: 需要 python3，但未找到" >&2
    exit 1
fi

REPORT_DIR="${1:-.}"

python3 -c '
import sys, os, re
from collections import defaultdict, Counter

report_dir = sys.argv[1]

# === 读取所有报告 ===
reports = []
for fname in sorted(os.listdir(report_dir)):
    if not fname.endswith(".md"):
        continue
    fpath = os.path.join(report_dir, fname)
    with open(fpath) as f:
        reports.append({"file": fname, "content": f.read()})

if not reports:
    print("(无蒸馏报告)")
    sys.exit(0)

# === 解析器 ===
# 表格行正则
kv_row_re = re.compile(r"^\|\s*(.+?)\s*\|\s*(.+?)\s*\|")
skill_row_re = re.compile(r"^\|\s*(\S+)\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|\s*(\d+)s\s*\|\s*(\d+)\s*\|\s*(\S+)\s*\|")
recovery_row_re = re.compile(r"^\|\s*(\w+)\s*\|\s*(\d+)\s*\|")
component_row_re = re.compile(r"^\|\s*(\S+)\s*\|\s*(\d+)\s*\|\s*(.+?)\s*\|")
tool_row_re = re.compile(r"^\|\s*(\S+)\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|")
agent_row_re = re.compile(r"^\|\s*(\S+)\s*\|\s*(\d+)\s*\|")
anomaly_item_re = re.compile(r"^-\s*\[(\S+)\]\s+(.+)")

sessions = []
for r in reports:
    content = r["content"]
    lines = content.split("\n")

    s = {
        "session": "unknown",
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
    }

    current_section = None
    in_l1_table = False

    for line in lines:
        ls = line.strip()

        # 基本信息
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

        # Section 跟踪
        if ls.startswith("### L1:"):
            current_section = "L1"
            in_l1_table = False
            continue
        elif ls.startswith("### L2:"):
            current_section = "L2"
            in_l1_table = False
            continue
        elif ls.startswith("### L3:"):
            current_section = "L3"
            in_l1_table = False
            continue
        elif ls.startswith("### L4:"):
            current_section = "L4"
            in_l1_table = False
            continue
        elif ls.startswith("### L5:"):
            current_section = "L5"
            in_l1_table = False
            continue
        elif ls.startswith("### 工具使用"):
            current_section = "tools"
            in_l1_table = False
            continue
        elif ls.startswith("### Agent"):
            current_section = "agents"
            in_l1_table = False
            continue
        elif ls.startswith("### 异常"):
            current_section = "anomalies"
            in_l1_table = False
            continue
        elif ls.startswith("### 用户纠正"):
            current_section = "corrections"
            in_l1_table = False
            continue
        elif ls.startswith("### "):
            current_section = None
            in_l1_table = False
            continue

        # Table separator or empty → skip
        if ls.startswith("|---") or ls.startswith("| --") or not ls.startswith("|"):
            continue

        # L1: KV 表
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

        # L2: Skill 下钻
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

        # L3: 执行对齐
        elif current_section == "L3":
            if ls.startswith("|- 共"):
                m = re.search(r"共\s*(\d+)\s*个", ls)
                if m:
                    s["alignment_count"] = int(m.group(1))

        # L4: 恢复分类
        elif current_section == "L4":
            m = recovery_row_re.match(ls)
            if m:
                key = m.group(1).strip()
                try:
                    s["recovery"][key] = int(m.group(2))
                except ValueError:
                    pass

        # L5: 组件归因
        elif current_section == "L5":
            m = component_row_re.match(ls)
            if m:
                s["components"][m.group(1).strip()] = {
                    "signals": int(m.group(2)),
                    "summary": m.group(3).strip(),
                }

        # 工具使用
        elif current_section == "tools":
            m = tool_row_re.match(ls)
            if m:
                s["tools"][m.group(1)] = {"calls": int(m.group(2)), "errors": int(m.group(3))}

        # Agent 派遣
        elif current_section == "agents":
            m = agent_row_re.match(ls)
            if m:
                s["agents"][m.group(1)] = int(m.group(2))

        # 异常
        elif current_section == "anomalies":
            m = anomaly_item_re.match(ls)
            if m:
                s["anomaly_count"] += 1
                s["anomaly_items"].append({
                    "component": m.group(1).strip(),
                    "detail": m.group(2).strip(),
                })

        # 纠正
        elif current_section == "corrections":
            m = re.search(r"检测到\s+(\d+)\s+次", ls)
            if m:
                s["correction_count"] = int(m.group(1))

    sessions.append(s)

if not sessions:
    print("(无可解析的会话)")
    sys.exit(0)

# === 跨会话聚合 ===
total_sessions = len(sessions)

# --- 组件故障热点 ---
component_hotspots = defaultdict(lambda: {"total_signals": 0, "sessions": 0, "summaries": []})
for s in sessions:
    for comp, data in s["components"].items():
        component_hotspots[comp]["total_signals"] += data["signals"]
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

# --- 纠正热点（≥3 会话）---
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

# === 输出聚合报告 ===
print(f"""# Harness 诊断聚合报告

## 概览
- 分析 {total_sessions} 个会话
- 平均摩擦评分: {avg_friction:.2f}（{'低摩擦' if avg_friction < 0.2 else '中摩擦' if avg_friction < 0.4 else '高摩擦'}）
- 高摩擦会话: {len(high_friction)}/{total_sessions}（friction >= 0.3）
- 执行对齐问题: {total_alignment} 次 (涉及 {alignment_sessions} 个会话)
- Hook 总阻拦: {total_hook_blocks} 次

## 组件故障热点（跨会话共现 ≥2）
| 组件 | 信号总数 | 涉及会话 | 典型摘要 |
|------|---------|---------|---------|""")
for comp, data in sorted(component_hotspots.items(), key=lambda x: x[1]["sessions"], reverse=True):
    if data["sessions"] >= 2:
        top_summary = Counter(data["summaries"]).most_common(1)[0][0][:80] if data["summaries"] else "-"
        print(f"| {comp} | {data['total_signals']} | {data['sessions']} | {top_summary} |")

if skill_agg:
    print("""
## Skill 级聚合
| Skill | 会话数 | 总调用 | 总错误 | 平均耗时 | 总重试 | 错误率 |
|-------|--------|--------|--------|---------|--------|-------|""")
    for sk, st in sorted(skill_agg.items(), key=lambda x: x[1]["calls"], reverse=True):
        err_rate = f"{st['errors']/st['calls']:.0%}" if st["calls"] > 0 else "-"
        avg_dur = f"{st['dur_s']//st['sessions']}s" if st["sessions"] > 0 else "-"
        print(f"| {sk} | {st['sessions']} | {st['calls']} | {st['errors']} | {avg_dur} | {st['retries']} | {err_rate} |")

print(f"""
## 恢复模式分布
| 模式 | 总次数 | 占比 |
|------|--------|------|""")
total_recovery = sum(recovery_totals.values()) or 1
for mode in ["RETRY", "ESCALATE", "WORKAROUND", "IGNORE"]:
    cnt = recovery_totals.get(mode, 0)
    pct = f"{cnt/total_recovery:.0%}"
    print(f"| {mode} | {cnt} | {pct} |")

if recovery_totals.get("IGNORE", 0) > total_recovery * 0.4:
    print("\n**警告**: IGNORE 占比过高（>40%），harness 缺少错误处理指导")

if recovery_totals.get("RETRY", 0) > total_recovery * 0.3:
    print("\n**警告**: RETRY 占比过高（>30%），存在无效重试循环，skill 缺少退出条件")

if correction_hotspots:
    print("""
## 纠正热点（≥3 会话共现）
| Skill | 会话数 |
|-------|--------|""")
    for sk, cnt in sorted(correction_hotspots.items(), key=lambda x: x[1], reverse=True):
        print(f"| {sk} | {cnt} |")

if high_friction:
    print("""
## 高摩擦会话
| Session | Friction | Skill |
|---------|----------|-------|""")
    for s in sorted(high_friction, key=lambda x: x["friction_score"], reverse=True)[:10]:
        skills_short = ", ".join(s["skills"][:2])
        print(f"| {s['session'][:12]} | {s['friction_score']:.2f} | {skills_short} |")

if anomaly_clusters:
    print("""
## 异常跨会话频率（≥2 会话共现）
| 异常模式 | 会话数 |
|---------|--------|""")
    for pattern, cnt in anomaly_clusters.most_common(15):
        if cnt >= 2:
            print(f"| {pattern[:100]} | {cnt} |")

# 工具/Agent 聚合
if tool_agg:
    print("""
## 工具使用聚合
| Tool | 总调用 | 总错误 | 错误率 | 出现会话 |
|------|--------|--------|--------|---------|""")
    for tool, data in sorted(tool_agg.items(), key=lambda x: x[1]["calls"], reverse=True):
        err_rate = f"{data['errors']/data['calls']:.1%}" if data["calls"] > 0 else "-"
        print(f"| {tool} | {data['calls']} | {data['errors']} | {err_rate} | {data['sessions']} |")

if agent_agg:
    print("""
## Agent 派遣聚合
| Agent | 总派遣 | 出现会话 |
|-------|--------|---------|""")
    for agent, data in sorted(agent_agg.items(), key=lambda x: x[1]["calls"], reverse=True):
        print(f"| {agent} | {data['calls']} | {data['sessions']} |")

print("""
## 会话列表
| Session | 时长 | 事件 | Friction | Skills | 对齐 | Blocks | 纠正 |
|---------|------|------|----------|--------|------|--------|------|""")
for s in sessions:
    skills_short = ", ".join(s["skills"][:2])
    if len(s["skills"]) > 2:
        skills_short += f" +{len(s['skills'])-2}"
    print(f"| {s['session'][:12]} | {s['duration_min']}min | {s['events']} | {s['friction_score']:.2f} | {skills_short} | {s['alignment_count']} | {s['hook_blocks']} | {s['correction_count']} |")
' "$REPORT_DIR"
