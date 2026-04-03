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
eval "$(echo "$inputJson" | python3 -c "
import sys,json
d=json.load(sys.stdin)
cw=d.get('context_window',{}) or {}
rl=d.get('rate_limits',{}) or {}
fh=rl.get('five_hour',{}) or {}
sd=rl.get('seven_day',{}) or {}
m=d.get('model',{}) or {}
print(f'contextPercent={int(cw.get(\"used_percentage\",0) or 0)}')
print(f'contextSize={cw.get(\"context_window_size\",200000)}')
print(f'usage5h={int(fh.get(\"used_percentage\",0) or 0)}')
print(f'usage5hResets={int(fh.get(\"resets_at\",0) or 0)}')
print(f'usage7d={int(sd.get(\"used_percentage\",0) or 0)}')
print(f'usage7dResets={int(sd.get(\"resets_at\",0) or 0)}')
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

# Append context window size if 1M+
if [ "$contextSize" -ge 1000000 ] 2>/dev/null; then
    contextM=$(( contextSize / 1000000 ))
    modelName="${modelName} (${contextM}M)"
fi

# Path
displayPath=$(basename "$PWD")

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

# Line 1: model + project folder
line1="${TealBright}${userIcon} ${modelName}${Reset} on ${CyanLight}${folderIcon} ${displayPath}${Reset}"

# Line 2: branch + context progress bar
line2=""
if [ -n "$gitBranch" ]; then
    line2="${TealDark}${gitBranchIcon}${gitBranch}${Reset}"
fi

contextBar=$(render_progress_bar "$contextPercent" 10)
contextColor=$(color_for_percent "$contextPercent")
if [ -n "$line2" ]; then
    line2+=" | "
fi
line2+="Context ${contextColor}${contextBar} ${contextPercent}%${Reset}"

# Line 3: usage 5h + 7d with progress bars
line3=""
if [ "$usage5h" -gt 0 ] 2>/dev/null; then
    bar5h=$(render_progress_bar "$usage5h" 10)
    color5h=$(color_for_percent "$usage5h")
    resetStr=$(format_reset_time "$usage5hResets")
    line3+="5h ${color5h}${bar5h} ${usage5h}%${Reset}"
    [ -n "$resetStr" ] && line3+=" (${resetStr})"
fi
if [ "$usage7d" -gt 0 ] 2>/dev/null; then
    [ -n "$line3" ] && line3+=" | "
    bar7d=$(render_progress_bar "$usage7d" 10)
    color7d=$(color_for_percent "$usage7d")
    line3+="7d ${color7d}${bar7d} ${usage7d}%${Reset}"
    resetStr7d=$(format_reset_time "$usage7dResets")
    [ -n "$resetStr7d" ] && line3+=" (${resetStr7d})"
fi

printf '%b\n' "$line1"
printf '%b\n' "$line2"
if [ -n "$line3" ]; then
    printf '%b\n' "$line3"
fi
