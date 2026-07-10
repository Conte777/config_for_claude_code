#!/usr/bin/env bash

inputJson=$(cat)

if [ -z "$inputJson" ]; then
    echo "No input"
    exit 0
fi

# ANSI RGB colors
TealBright='\033[38;2;69;241;194m'
CyanLight='\033[38;2;12;160;216m'
TealDark='\033[38;2;20;165;174m'
Green='\033[38;2;76;200;116m'
Yellow='\033[38;2;255;200;76m'
Red='\033[38;2;204;100;100m'
Reset='\033[0m'

# Render Unicode progress bar: █ for filled, ░ for empty
render_progress_bar() {
    local percent="${1:-0}"
    local width="${2:-10}"
    local filled=$(( percent * width / 100 ))
    local empty=$(( width - filled ))
    local bar=""
    local i=0
    while [ "$i" -lt "$filled" ]; do
        bar="${bar}$(printf '\xe2\x96\x88')"
        i=$(( i + 1 ))
    done
    i=0
    while [ "$i" -lt "$empty" ]; do
        bar="${bar}$(printf '\xe2\x96\x91')"
        i=$(( i + 1 ))
    done
    echo "$bar"
}

# Return ANSI color based on usage percentage
color_for_percent() {
    local percent="${1:-0}"
    if [ "$percent" -lt 40 ] 2>/dev/null; then
        echo "$Green"
    elif [ "$percent" -lt 70 ] 2>/dev/null; then
        echo "$Yellow"
    else
        echo "$Red"
    fi
}

# Format reset timestamp as relative time
format_reset_time() {
    local resetTimestamp="$1"
    if [ "$resetTimestamp" -le 0 ] 2>/dev/null; then return; fi
    local now
    now=$(date +%s)
    local diff=$(( resetTimestamp - now ))
    if [ "$diff" -le 0 ]; then echo "now"; return; fi
    local d=$(( diff / 86400 ))
    local h=$(( (diff % 86400) / 3600 ))
    local m=$(( (diff % 3600) / 60 ))
    if [ "$d" -gt 0 ]; then
        echo "${d}d${h}h"
    elif [ "$h" -gt 0 ]; then
        echo "${h}h${m}m"
    else
        echo "${m}m"
    fi
}

# Parse all fields from stdin JSON via python3
# effortLevel is not provided in the statusline JSON, so it is read from
# settings files (project local → project → user) using workspace.current_dir.
eval "$(echo "$inputJson" | python3 -c "
import sys,json,os
d=json.load(sys.stdin)
cw=d.get('context_window',{}) or {}
rl=d.get('rate_limits',{}) or {}
fh=rl.get('five_hour',{}) or {}
sd=rl.get('seven_day',{}) or {}
m=d.get('model',{}) or {}
ws=d.get('workspace',{}) or {}
print(f'contextPercent={int(cw.get(\"used_percentage\",0) or 0)}')
print(f'contextSize={cw.get(\"context_window_size\",200000)}')
u5=int(fh.get(\"used_percentage\",0) or 0)
r5=int(fh.get(\"resets_at\",0) or 0)
u7=int(sd.get(\"used_percentage\",0) or 0)
r7=int(sd.get(\"resets_at\",0) or 0)
live=1 if (r5>0 or r7>0) else 0
if not live:
    # Fresh session: statusline JSON has no rate limits yet. Fall back to the
    # codexbar cache (primary=5h window, secondary=7d window).
    try:
        from datetime import datetime,timezone
        cj=json.load(open(os.path.expanduser('~/.claude/.codexbar-claude-usage.json')))
        usage=(cj[0] if isinstance(cj,list) else cj).get('usage',{}) or {}
        def _iso(s): return int(datetime.strptime(s,'%Y-%m-%dT%H:%M:%SZ').replace(tzinfo=timezone.utc).timestamp())
        pr=usage.get('primary') or {}
        se=usage.get('secondary') or {}
        if pr.get('resetsAt'):
            u5=int(pr.get('usedPercent',0) or 0); r5=_iso(pr['resetsAt'])
        if se.get('resetsAt'):
            u7=int(se.get('usedPercent',0) or 0); r7=_iso(se['resetsAt'])
    except Exception:
        pass
print(f'usage5h={u5}')
print(f'usage5hResets={r5}')
print(f'usage7d={u7}')
print(f'usage7dResets={r7}')
print(f'liveLimits={live}')
curDir=ws.get('current_dir') or os.getcwd()
home=os.path.expanduser('~')
# Live, session-scoped effort: Claude Code exports it into the statusline
# child's env, so it's immune to other sessions overwriting settings.json.
effort=os.environ.get('CLAUDE_EFFORT') or os.environ.get('CLAUDE_CODE_EFFORT_LEVEL') or ''
if not effort:
    for p in [os.path.join(curDir,'.claude','settings.local.json'), os.path.join(curDir,'.claude','settings.json'), os.path.join(home,'.claude','settings.json')]:
        try:
            with open(p) as fp:
                v=(json.load(fp) or {}).get('effortLevel')
            if v:
                effort=str(v)
                break
        except Exception:
            pass
print(f'effortLevel={effort}')
mid=m.get('id','unknown')
print(f'modelId={mid}')
mdisp=m.get('display_name','')
print(f'modelDisplay={mdisp}')
" 2>/dev/null)" || true

# Fallbacks
contextPercent="${contextPercent:-0}"
contextSize="${contextSize:-200000}"
usage5h="${usage5h:-0}"
usage5hResets="${usage5hResets:-0}"
usage7d="${usage7d:-0}"
usage7dResets="${usage7dResets:-0}"
modelId="${modelId:-unknown}"
effortLevel="${effortLevel:-}"
liveLimits="${liveLimits:-0}"

# For new sessions only (no live rate limits in the JSON yet), keep the codexbar
# Claude usage cache warm via a background, non-blocking refresh (throttled by TTL).
# Once the session has live limits, codexbar is never called.
codexbarCache="$HOME/.claude/.codexbar-claude-usage.json"
codexbarTTL=120
if [ "$liveLimits" = "0" ] && command -v codexbar >/dev/null 2>&1; then
    cacheAge=999999
    if [ -f "$codexbarCache" ]; then
        cacheMtime=$(stat -f %m "$codexbarCache" 2>/dev/null || echo 0)
        cacheAge=$(( $(date +%s) - cacheMtime ))
    fi
    if [ "$cacheAge" -ge "$codexbarTTL" ]; then
        touch "$codexbarCache" 2>/dev/null  # debounce concurrent renders
        nohup env CB_CACHE="$codexbarCache" sh -c \
            'codexbar usage --provider claude --json --no-color > "$CB_CACHE.tmp" 2>/dev/null && mv "$CB_CACHE.tmp" "$CB_CACHE"' \
            >/dev/null 2>&1 &
    fi
fi

# Context window size label: thousands as "Nk", millions as "Nkk" (e.g. 1000000 → 1kk)
contextK=$(( (contextSize + 500) / 1000 ))
if [ "$contextK" -ge 1000 ] 2>/dev/null; then
    contextMillionsWhole=$(( contextK / 1000 ))
    contextMillionsFrac=$(( (contextK % 1000) / 100 ))
    if [ "$contextMillionsFrac" -gt 0 ]; then
        contextLabel="${contextMillionsWhole}.${contextMillionsFrac}kk"
    else
        contextLabel="${contextMillionsWhole}kk"
    fi
else
    contextLabel="${contextK}k"
fi

# Model display name with version extracted from modelId
# e.g. claude-sonnet-4-6 → "Sonnet 4.6", claude-opus-4-6 → "Opus 4.6"
if [ -n "$modelDisplay" ]; then
    modelName="$modelDisplay"
else
    case "$modelId" in
        *sonnet*) modelName="Sonnet" ;;
        *opus*)   modelName="Opus" ;;
        *haiku*)  modelName="Haiku" ;;
        *)        modelName="${modelId%%-*}" ;;
    esac
fi

# Append version from modelId (e.g. claude-opus-4-6 → 4.6, claude-haiku-4-5-20251001 → 4.5)
# Strip trailing suffixes: [1m], -YYYYMMDD
cleanId=$(echo "$modelId" | sed 's/\[.*\]$//' | sed 's/-[0-9]\{8,\}$//')
modelVersion=$(echo "$cleanId" | sed -n 's/.*-\([0-9]\{1,\}\)-\([0-9]\{1,\}\)$/\1.\2/p')
if [ -z "$modelVersion" ]; then
    modelVersion=$(echo "$cleanId" | sed -n 's/.*-\([0-9]\{1,\}\)$/\1/p')
fi
[ -n "$modelVersion" ] && modelName="${modelName} ${modelVersion}"

# Path (show ~ for the home directory, basename otherwise)
if [ "$PWD" = "$HOME" ]; then
    displayPath="~"
else
    displayPath=$(basename "$PWD")
fi

# Git branch
gitBranch=""
if [ -d "$PWD/.git" ] || git -C "$PWD" rev-parse --git-dir >/dev/null 2>&1; then
    branch=$(git -C "$PWD" symbolic-ref --short HEAD 2>/dev/null)
    if [ -z "$branch" ]; then
        branch=$(git -C "$PWD" rev-parse --short HEAD 2>/dev/null)
        [ -n "$branch" ] && branch="detached:$branch"
    fi
    gitBranch="$branch"
fi

# Nerd Font icons (UTF-8 encoded for bash 3.2 compatibility)
userIcon=$(printf '\xee\xae\x99')
folderIcon=$(printf '\xef\x81\xbb')
gitBranchIcon=$(printf '\xee\x9c\xa5')

# Line 1: context + rate limits (5h / 7d); only the bars carry the usage color,
# percentages and sizes stay in the default color. 5h/7d are always shown (even
# on a fresh session before rate-limit data is populated).
contextBar=$(render_progress_bar "$contextPercent" 10)
contextColor=$(color_for_percent "$contextPercent")
line1="Context ${contextColor}${contextBar}${Reset} ${contextPercent}%/${contextLabel}"

bar5h=$(render_progress_bar "$usage5h" 10)
color5h=$(color_for_percent "$usage5h")
resetStr=$(format_reset_time "$usage5hResets")
line1+=" | 5h ${color5h}${bar5h}${Reset} ${usage5h}%"
[ -n "$resetStr" ] && line1+=" (${resetStr})"

bar7d=$(render_progress_bar "$usage7d" 10)
color7d=$(color_for_percent "$usage7d")
resetStr7d=$(format_reset_time "$usage7dResets")
line1+=" | 7d ${color7d}${bar7d}${Reset} ${usage7d}%"
[ -n "$resetStr7d" ] && line1+=" (${resetStr7d})"

# Line 2: model + reasoning effort (same color as model) + project folder + branch
line2="${TealBright}${userIcon} ${modelName}"
[ -n "$effortLevel" ] && line2+=" • ${effortLevel}"
line2+="${Reset} on ${CyanLight}${folderIcon} ${displayPath}${Reset}"
if [ -n "$gitBranch" ]; then
    line2+=" | ${TealDark}${gitBranchIcon}${gitBranch}${Reset}"
fi

printf '%b\n' "$line1"
printf '%b\n' "$line2"
