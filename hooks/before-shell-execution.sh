#!/bin/bash
# PreToolUse Hook: Dangerous command guard
# 危险命令拦截（阻塞）与警告（不阻塞）

set -e

HOOK_JSON=$(cat)

python3 -c "
import json, sys, shlex

data = json.loads(sys.argv[1])
tool_name = data.get('tool_name', '')
tool_input = data.get('tool_input', {}) or {}
command = tool_input.get('command', '')

if tool_name != 'Bash' or not command:
    sys.exit(0)

try:
    parts = shlex.split(command)
except ValueError:
    sys.exit(0)

if not parts:
    sys.exit(0)

action = 'OK'
msg = ''

# === 阻塞级 ===

# git push --force
if len(parts) >= 2 and parts[0] == 'git' and parts[1] == 'push':
    if '--force' in parts or '-f' in parts:
        action = 'BLOCK'
        msg = 'git push --force 被禁止，如需覆盖远程历史请手动执行'

# git commit --no-verify（含组合短选项如 -amn）
elif len(parts) >= 2 and parts[0] == 'git' and parts[1] == 'commit':
    has_n = False
    for p in parts:
        if p == '--no-verify':
            has_n = True
            break
        # 短选项组合如 -amn 中含 n
        if len(p) > 1 and p[0] == '-' and p[1] != '-' and 'n' in p:
            has_n = True
            break
    if has_n:
        action = 'BLOCK'
        msg = 'git commit --no-verify 被禁止，请移除后重试'

# rm -rf 危险目录（含组合短选项如 -rf）
elif parts[0] == 'rm':
    has_r = False
    for p in parts:
        if p in ('-r', '-R', '--recursive'):
            has_r = True
            break
        if len(p) > 1 and p[0] == '-' and p[1] != '-' and ('r' in p or 'R' in p):
            has_r = True
            break
    if has_r:
        dangerous = {'/', '/bin', '/boot', '/dev', '/etc', '/home', '/lib', '/lib64',
                     '/opt', '/root', '/sbin', '/sys', '/usr', '/var'}
        for p in parts:
            for d in dangerous:
                if p == d or p.startswith(d + '/'):
                    action = 'BLOCK'
                    msg = f'rm 递归删除危险目录被拦截: {p}'
                    break
            if action == 'BLOCK':
                break

# === 警告级 ===

# dd 写块设备
elif parts[0] == 'dd':
    for p in parts:
        if p.startswith('of=/dev/'):
            action = 'WARN'
            msg = f'dd 将直接写入块设备 {p}，确认目标正确'

# mkfs 格式化
elif parts[0].startswith('mkfs.'):
    action = 'WARN'
    msg = f'{parts[0]} 将格式化文件系统，此操作不可逆'

# git clean -x / -X（含组合短选项如 -fdx）
elif len(parts) >= 2 and parts[0] == 'git' and parts[1] == 'clean':
    has_x = False
    for p in parts:
        if p == '-x' or p == '-X':
            has_x = True
            break
        if len(p) > 1 and p[0] == '-' and p[1] != '-' and ('x' in p or 'X' in p):
            has_x = True
            break
    if has_x:
        action = 'WARN'
        msg = 'git clean -x/-X 将删除忽略文件（含本地配置），请确认'

if action == 'BLOCK':
    print(f'[DevForge]  {msg}', file=sys.stderr)
    sys.exit(1)
elif action == 'WARN':
    print(f'[DevForge]  {msg}', file=sys.stderr)

sys.exit(0)
" "$HOOK_JSON"
