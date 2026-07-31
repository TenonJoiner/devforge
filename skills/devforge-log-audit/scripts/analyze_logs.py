#!/usr/bin/env python3
"""Runtime log analysis for devforge-log-audit.

Parses real log files to quantify what static source analysis cannot:
per-level counts, print rate (lines/sec), and the highest-frequency
message templates (the usual flooding sources).

Stdlib only. Best-effort across unknown formats — never assume a schema.

Usage:
    python3 analyze_logs.py --log-dir /var/log/app [--glob '*.log*'] [--top 15] [--json]
    python3 analyze_logs.py --log-dir /var/log/app --levels "Debug|DBG,Informational|INFO,Notice|NOTE,Warning|WARN,Error|ERR,Critical|CRIT,Alert,Emergency|FATAL|PANIC,EMIT" --log-format json
"""
import argparse
import glob
import json
import os
import re
from collections import Counter
from datetime import datetime, timedelta

# ---------------------------------------------------------------------------
# Timestamp extraction (best-effort, format-independent)
# ---------------------------------------------------------------------------
TS_PATTERNS = [
    (re.compile(r"(\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}(?:\.\d+)?)"), "%Y-%m-%d %H:%M:%S"),
    (re.compile(r"(\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2})"), "%Y/%m/%d %H:%M:%S"),
    (re.compile(r"\b(\d{2}:\d{2}:\d{2})\b"), "%H:%M:%S"),
]
EPOCH_RE = re.compile(r"^\[?(\d{10})(?:\.\d+)?\]?")

# ---------------------------------------------------------------------------
# Message normalization (collapse variable data into templates)
# ---------------------------------------------------------------------------
NORM_RULES = [
    (re.compile(r"\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b"), "<UUID>"),
    (re.compile(r"\b\d{1,3}(?:\.\d{1,3}){3}\b"), "<IP>"),
    (re.compile(r"0x[0-9a-fA-F]+"), "<HEX>"),
    (re.compile(r"\b[0-9a-fA-F]{16,}\b"), "<HEX>"),
    (re.compile(r'"[^"]*"'), "<STR>"),
    (re.compile(r"'[^']*'"), "<STR>"),
    (re.compile(r"\b(?=\w*[A-Za-z])(?=\w*\d)\w{6,}\b"), "<ID>"),
    (re.compile(r"\b\d+(?:\.\d+)?\b"), "<N>"),
]
PREFIX_RE = re.compile(
    r"^\W*(?:\d{4}[-/]\d{2}[-/]\d{2}[ T]?)?\d{2}:\d{2}:\d{2}(?:[.,]\d+)?\W*", re.I
)

# ---------------------------------------------------------------------------
# Level detection (driven by externally injected project level definitions)
# ---------------------------------------------------------------------------
DEFAULT_LEVELS = "Debug|DBG,Informational|INFO,Notice|NOTE,Warning|WARN,Error|ERR,Critical|CRIT,Alert,Emergency|FATAL|PANIC,EMIT"


def parse_levels(raw):
    """Parse --levels into canonical names and alias groups.

    ``--levels "Debug|DBG,Informational|INFO,Notice|NOTE,Warning|WARN,Error|ERR,Critical|CRIT,Alert,Emergency|FATAL|PANIC,EMIT"``
    Each comma-separated group is ``CANONICAL|ALIAS1|ALIAS2``; the first token
    is the canonical name used in output.
    """
    groups = []
    all_tokens = []
    for group in raw.split(","):
        tokens = [t.strip() for t in group.split("|") if t.strip()]
        if tokens:
            groups.append(tokens)
            all_tokens.extend(tokens)
    return groups, all_tokens


def build_level_patterns(groups):
    """Build detection patterns from level groups.

    Returns list of (canonical_name, compiled_regex), highest severity first,
    so e.g. Emergency matches before Error on a line containing both.
    """
    patterns = []
    for tokens in reversed(groups):  # highest severity first
        canon = tokens[0]
        alt = "|".join(re.escape(t) for t in tokens)
        pat = re.compile(r"\b(" + alt + r")\b", re.I)
        patterns.append((canon, pat))
    return patterns


def detect_level_text(line, level_patterns):
    head = line[:80]
    for canon, pat in level_patterns:
        if pat.search(head):
            return canon
    return "OTHER"


# ---------------------------------------------------------------------------
# JSON log parsing
# ---------------------------------------------------------------------------
def parse_json_log(line):
    """Try to parse a line as a structured JSON log record.

    Returns ``{level_raw, msg, ts}`` on success, *None* otherwise.
    """
    try:
        obj = json.loads(line)
    except (json.JSONDecodeError, ValueError):
        return None
    if not isinstance(obj, dict):
        return None

    level = None
    for key in ("level", "severity", "lvl", "log_level", "logLevel"):
        if key in obj:
            level = str(obj[key])
            break

    msg = None
    for key in ("msg", "message", "M", "content", "text"):
        if key in obj:
            msg = str(obj[key])
            break
    if msg is None:
        msg = json.dumps(obj, ensure_ascii=False)

    ts = None
    for key in ("ts", "timestamp", "time", "@timestamp", "datetime"):
        if key in obj:
            ts = obj[key]
            break

    return {"level_raw": level, "msg": msg, "ts": ts}


def detect_level_json(level_raw, level_patterns):
    """Match an extracted JSON level string against project level patterns."""
    if not level_raw:
        return "OTHER"
    for canon, pat in level_patterns:
        if pat.search(level_raw):
            return canon
    return "OTHER"


def parse_json_ts(raw):
    """Parse a timestamp value from a JSON field (string / number)."""
    if raw is None:
        return None
    if isinstance(raw, (int, float)):
        try:
            if raw > 1e12:  # milliseconds
                raw = raw / 1000.0
            return datetime.fromtimestamp(raw)
        except (ValueError, OSError):
            return None
    if isinstance(raw, str):
        for regex, fmt in TS_PATTERNS:
            m = regex.search(raw)
            if m:
                try:
                    return datetime.strptime(m.group(1).replace("T", " "), fmt)
                except ValueError:
                    continue
    return None


# ---------------------------------------------------------------------------
# Auto-detection
# ---------------------------------------------------------------------------
def detect_format(files):
    """Peek at the first few files to guess whether logs are JSON or text."""
    json_hits = 0
    checked = 0
    for path in files[:3]:
        try:
            with open(path, "r", errors="replace") as fh:
                for line in fh:
                    line = line.strip()
                    if not line:
                        continue
                    if line.startswith("{") and line.rstrip().endswith("}"):
                        try:
                            json.loads(line)
                            json_hits += 1
                        except (json.JSONDecodeError, ValueError):
                            pass
                    checked += 1
                    if checked >= 5:
                        break
        except Exception:
            continue
    if checked == 0:
        return "text"
    return "json" if json_hits >= checked * 0.8 else "text"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def parse_ts(line):
    m = EPOCH_RE.match(line)
    if m:
        try:
            return datetime.fromtimestamp(int(m.group(1)))
        except (ValueError, OSError):
            pass
    for regex, fmt in TS_PATTERNS:
        m = regex.search(line[:120])
        if not m:
            continue
        raw = m.group(1).replace("T", " ")
        try:
            ts = datetime.strptime(raw, fmt)
            if fmt == "%H:%M:%S":
                ts = ts.replace(year=2000, month=1, day=1)
            return ts
        except ValueError:
            continue
    return None


def templatize_text(line, level_strip_pat):
    msg = PREFIX_RE.sub("", line).strip()
    if level_strip_pat:
        msg = level_strip_pat.sub("", msg, count=1)
    for regex, repl in NORM_RULES:
        msg = regex.sub(repl, msg)
    msg = re.sub(r"\s+", " ", msg).strip(" \t|:-")
    return msg[:200]


def templatize_json(msg):
    for regex, repl in NORM_RULES:
        msg = regex.sub(repl, msg)
    msg = re.sub(r"\s+", " ", msg).strip(" \t|:-")
    return msg[:200]


def build_level_strip_pat(all_tokens):
    if not all_tokens:
        return None
    return re.compile(r"\b(" + "|".join(re.escape(t) for t in all_tokens) + r")\b", re.I)


# ---------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser(description="Quantify runtime logging behavior.")
    ap.add_argument("--log-dir", required=True)
    ap.add_argument("--glob", default="*.log*", help="filename glob (default *.log*)")
    ap.add_argument("--top", type=int, default=15, help="top-N message templates")
    ap.add_argument("--json", action="store_true", help="emit JSON instead of text")
    ap.add_argument(
        "--levels",
        default=DEFAULT_LEVELS,
        help="comma-separated level names, low→high severity. "
        "Use pipe for aliases: Warning|WARN,Error|ERR. "
        "First token in each group is the canonical name used in output.",
    )
    ap.add_argument(
        "--log-format",
        choices=["auto", "text", "json"],
        default="auto",
        help="log format; auto detects from file content (default auto)",
    )
    args = ap.parse_args()

    if not os.path.isdir(args.log_dir):
        raise SystemExit(f"log dir not found: {args.log_dir}")
    files = sorted(
        glob.glob(os.path.join(args.log_dir, "**", args.glob), recursive=True)
    )
    files = [f for f in files if os.path.isfile(f)]
    if not files:
        raise SystemExit(f"no files matching {args.glob!r} under {args.log_dir}")

    level_groups, all_tokens = parse_levels(args.levels)
    level_patterns = build_level_patterns(level_groups)
    level_strip_pat = build_level_strip_pat(all_tokens)
    levels_order = [g[0] for g in level_groups] + ["OTHER"]

    log_format = args.log_format
    if log_format == "auto":
        log_format = detect_format(files)

    level_counts = Counter()
    templates = Counter()
    per_second = Counter()
    total = 0
    ts_count = 0
    ts_min = ts_max = None
    last_ts = None

    for path in files:
        with open(path, "r", errors="replace") as fh:
            for line in fh:
                line = line.rstrip("\n")
                if not line.strip():
                    continue
                total += 1

                if log_format == "json":
                    parsed = parse_json_log(line)
                    if parsed is not None:
                        lvl = detect_level_json(parsed["level_raw"], level_patterns)
                        level_counts[lvl] += 1
                        templates[templatize_json(parsed["msg"])] += 1
                        ts = parse_json_ts(parsed["ts"])
                    else:
                        lvl = detect_level_text(line, level_patterns)
                        level_counts[lvl] += 1
                        templates[templatize_text(line, level_strip_pat)] += 1
                        ts = parse_ts(line)
                else:
                    lvl = detect_level_text(line, level_patterns)
                    level_counts[lvl] += 1
                    templates[templatize_text(line, level_strip_pat)] += 1
                    ts = parse_ts(line)

                if ts:
                    ts_count += 1
                    if ts.year == 2000 and last_ts is not None:
                        ts = ts.replace(year=last_ts.year, month=last_ts.month, day=last_ts.day)
                        if ts < last_ts:
                            ts = ts + timedelta(days=1)
                    per_second[ts.replace(microsecond=0)] += 1
                    ts_min = ts if ts_min is None or ts < ts_min else ts_min
                    ts_max = ts if ts_max is None or ts > ts_max else ts_max
                    last_ts = ts

    span = (ts_max - ts_min).total_seconds() if ts_min and ts_max else 0
    steady = round(total / span, 1) if span > 0 else None
    peak = max(per_second.values()) if per_second else None

    top = []
    for tmpl, cnt in templates.most_common(args.top):
        top.append({
            "template": tmpl or "<empty>",
            "count": cnt,
            "pct": round(100.0 * cnt / total, 1) if total else 0.0,
        })

    result = {
        "files": len(files),
        "total_lines": total,
        "log_format": log_format,
        "levels": levels_order[:-1],  # exclude "OTHER"
        "level_counts": {lv: level_counts.get(lv, 0) for lv in levels_order},
        "rate": {
            "timestamped_lines": ts_count,
            "span_seconds": round(span, 1),
            "steady_lines_per_sec": steady,
            "peak_lines_per_sec": peak,
        },
        "top_templates": top,
    }

    if args.json:
        print(json.dumps(result, indent=2, ensure_ascii=False))
        return

    print(f"files: {result['files']}   total lines: {total}   format: {log_format}")
    print("levels: " + "  ".join(f"{lv}={level_counts.get(lv, 0)}" for lv in levels_order))
    if steady is not None:
        print(f"rate: steady {steady}/s   peak {peak}/s   span {span:.0f}s   (based on {result['rate']['timestamped_lines']} timestamped lines)")
    else:
        print("rate: timestamps not parseable — line counts only")
    print(f"\ntop {len(top)} message templates:")
    for i, t in enumerate(top, 1):
        print(f"  {i:2}. {t['pct']:5.1f}%  x{t['count']:<7} {t['template']}")


if __name__ == "__main__":
    main()
