#!/usr/bin/env python3
"""Multi-line status line: header + ctx/5h/7d gradient bars."""
import json, sys, time, subprocess, os

if sys.platform == 'win32':
    sys.stdout.reconfigure(encoding='utf-8')

data = json.load(sys.stdin)

R = '\033[0m'
DIM = '\033[2m'
C_MODEL = '\033[38;2;97;175;239m'    # blue
C_EFFORT = '\033[38;2;198;120;221m'  # purple
C_REPO = '\033[38;2;152;195;121m'    # green
C_BRANCH = '\033[38;2;229;192;123m'  # yellow

def gradient(pct):
    if pct < 50:
        r = int(pct * 5.1)
        return f'\033[38;2;{r};200;80m'
    g = int(200 - (pct - 50) * 4)
    return f'\033[38;2;255;{max(g,0)};60m'

def bar(pct, width=26):
    pct = min(max(pct, 0), 100)
    full = round(pct * width / 100)
    return '█' * full + '░' * (width - full)

def fmt_num(n):
    if n >= 1_000_000:
        s = f'{n / 1_000_000:.1f}'.rstrip('0').rstrip('.')
        return f'{s}M'
    if n >= 1000:
        s = f'{n / 1000:.1f}'.rstrip('0').rstrip('.')
        return f'{s}k'
    return str(n)

def rem_time(resets_at, with_days):
    rem = max(int(resets_at - time.time()), 0)
    days = rem // 86400
    mins = (rem % 3600) // 60
    if with_days and days > 0:
        return f'{days}d {(rem % 86400) // 3600}h {mins:02d}m'
    return f'{rem // 3600}h {mins:02d}m'

def bar_row(label, pct, trailing=''):
    line = f'{label:<3}: {gradient(pct)}{bar(pct)}{R} {round(pct):>3}%'
    return f'{line} {trailing}' if trailing else line

# --- header ---
cw = data.get('context_window') or {}
size = cw.get('context_window_size')

name = data.get('model', {}).get('display_name', 'Claude')
model = f'{C_MODEL}{name}{R}'
effort = (data.get('effort') or {}).get('level')
if effort:
    model += f'{C_EFFORT}[{effort}]{R}'

used = (cw.get('total_input_tokens') or 0) + (cw.get('total_output_tokens') or 0)
token_seg = f'{fmt_num(used)}/{fmt_num(size)}' if size else fmt_num(used)

ws = data.get('workspace') or {}
cwd = ws.get('current_dir') or data.get('cwd') or '.'
repo = (ws.get('repo') or {}).get('name')
if not repo:
    repo = os.path.basename((ws.get('project_dir') or cwd).rstrip('/')) or cwd
try:
    branch = subprocess.run(
        ['git', '-C', cwd, 'branch', '--show-current'],
        capture_output=True, text=True, timeout=1,
    ).stdout.strip()
except Exception:
    branch = ''
repo_seg = f'{C_REPO}{repo}{R}'
if branch:
    repo_seg += f'({C_BRANCH}{branch}{R})'

sep = f' {DIM}│{R} '
lines = [sep.join([model, token_seg, repo_seg])]

# --- bars ---
ctx_pct = cw.get('used_percentage')
lines.append(bar_row('ctx', ctx_pct if ctx_pct is not None else 0))

rl = data.get('rate_limits') or {}
five = rl.get('five_hour') or {}
if five.get('used_percentage') is not None:
    t = rem_time(five['resets_at'], False) if five.get('resets_at') else ''
    lines.append(bar_row('5h', five['used_percentage'], t))

seven = rl.get('seven_day') or {}
if seven.get('used_percentage') is not None:
    t = rem_time(seven['resets_at'], True) if seven.get('resets_at') else ''
    lines.append(bar_row('7d', seven['used_percentage'], t))

print('\n'.join(lines), end='')
