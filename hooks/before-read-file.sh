#!/bin/bash
# PreToolUse Hook: Warn before reading sensitive files
# 读取敏感文件前输出警告（不阻塞）

set -e

HOOK_JSON=$(cat)

python3 -c "
import json, sys, re

data = json.loads(sys.argv[1])
tool_name = data.get('tool_name', '')
tool_input = data.get('tool_input', {}) or {}
file_path = tool_input.get('file_path', '') or tool_input.get('path', '')

if tool_name != 'Read' or not file_path:
    sys.exit(0)

sensitive_patterns = [
    (r'\.(env|pem|key|crt|p12|keystore|jks)$', '凭证/密钥文件'),
    (r'/(credentials|id_rsa|id_ed25519|id_ecdsa|id_dsa)$', 'SSH/凭证文件'),
    (r'/(core|core\.[0-9]+)$', '核心转储文件（可能含敏感内存数据）'),
    (r'\.aws/credentials$', 'AWS 凭证文件'),
    (r'/\.ssh/', 'SSH 目录'),
]

for pattern, desc in sensitive_patterns:
    if re.search(pattern, file_path):
        print(f'[DevForge] 正在读取敏感文件：{file_path}', file=sys.stderr)
        print(f'[DevForge]    类型：{desc}，注意内容不要泄露到输出', file=sys.stderr)
        break

sys.exit(0)
" "$HOOK_JSON"
