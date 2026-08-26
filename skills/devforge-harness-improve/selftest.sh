#!/bin/bash
# DevForge harness 诊断管线最小回归测试
#
# 验证核心管线正确性，防止诊断工具自身 bug 污染下游分析：
#   - P0-1 回归：Skill/Agent intent 不应被误判为 Hook 阻拦
#   - P0-2 回归：aggregate 应能解析 distill 输出的「- 共 N 个对齐问题」列表行
#   - 数据流端到端：fixture → distill → aggregate → self_check 无 ERROR
#
# 使用：bash skills/devforge-harness-improve/selftest.sh
# 触发时机：修改 trace_distill.py / aggregate.py / trace-collector.sh 后

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURE="$SCRIPT_DIR/fixture-events.jsonl"
DISTILL_OUT="$(mktemp -t distill-XXXXXX.md)"
AGGREGATE_DIR="$(mktemp -d -t aggregate-XXXXXX)"
trap 'rm -rf "$DISTILL_OUT" "$AGGREGATE_DIR"' EXIT

fail() {
    echo "❌ FAIL: $1"
    [ -n "${2:-}" ] && echo "   提示: $2"
    exit 1
}

pass() {
    echo "✅ PASS: $1"
}

[ -f "$FIXTURE" ] || fail "fixture 不存在: $FIXTURE"

echo "=== 1. 运行 trace_distill.py 生成蒸馏报告 ==="
python3 "$SCRIPT_DIR/trace_distill.py" "$FIXTURE" > "$DISTILL_OUT"
pass "distill 完成"

echo ""
echo "=== 2. P0-1 回归：Hook 阻拦数应 == 1（仅 Read /etc/passwd 未配对）==="
hook_blocks=$(grep -E '^\|[[:space:]]*Hook 阻拦[[:space:]]*\|' "$DISTILL_OUT" | head -1 | awk -F'|' '{print $3}' | tr -d ' \n')
if [ -z "$hook_blocks" ]; then
    fail "distill 输出中找不到「Hook 阻拦」行" "检查 L1 表格格式是否变化"
fi
if [ "$hook_blocks" != "1" ]; then
    fail "期望 Hook 阻拦 = 1，实际 = $hook_blocks" \
         "若为 3：P0-1 未生效，Skill/Agent intent 被误判为被拦；若为 0：Read /etc/passwd 应被识别为未配对"
fi
pass "Hook 阻拦 = 1（Skill/Agent intent 正确配对，仅未配对的 Read 被识别为阻拦）"

echo ""
echo "=== 3. P0-2 前置：distill 输出应包含「- 共 N 个对齐问题」列表行 ==="
if ! grep -qE '^-[[:space:]]*共[[:space:]]+[0-9]+[[:space:]]+个对齐问题' "$DISTILL_OUT"; then
    fail "distill 输出缺少「- 共 N 个对齐问题」" "检查 L3 输出格式是否变化"
fi
pass "distill 输出包含对齐问题计数行"

echo ""
echo "=== 4. 运行 aggregate.py 验证 L3 解析 ==="
cp "$DISTILL_OUT" "$AGGREGATE_DIR/report.md"
AGGREGATE_OUT=$(python3 "$SCRIPT_DIR/aggregate.py" "$AGGREGATE_DIR")
echo "$AGGREGATE_OUT" | tail -20
pass "aggregate 完成"

echo ""
echo "=== 5. P0-2 回归：aggregate 应解析出 alignment_count > 0 ==="
if ! echo "$AGGREGATE_OUT" | grep -qE '执行对齐问题: [1-9]'; then
    fail "aggregate 解析 alignment_count = 0" \
         "P0-2 未生效：distill 的「- 共 N 个」列表行未被 aggregate 识别"
fi
pass "aggregate 解析出 alignment_count > 0"

echo ""
echo "=== 6. self_check 应无 ERROR 级解析失败 ==="
if echo "$AGGREGATE_OUT" | grep -qE '\|[[:space:]]*ERROR[[:space:]]*\('; then
    fail "self_check 输出 ERROR 级解析失败" "查看上方 aggregate 输出的「解析自检」节"
fi
pass "self_check 无 ERROR"

echo ""
echo "===================="
echo "✅ 全部断言通过"
echo "===================="
