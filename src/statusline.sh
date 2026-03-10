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

# Extract JSON fields via grep/sed
extractJson() {
    echo "$inputJson" | grep -o "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | sed 's/.*:[[:space:]]*"\([^"]*\)"/\1/' | head -1
}

extractJsonNumber() {
    echo "$inputJson" | grep -o "\"$1\"[[:space:]]*:[[:space:]]*[0-9.]*" | sed 's/.*:[[:space:]]*//' | head -1
}

# Model
modelId=$(extractJson "id")
if [ -z "$modelId" ]; then
    modelId="Unknown"
fi

case "$modelId" in
    *sonnet*) modelName="Sonnet" ;;
    *opus*)   modelName="Opus" ;;
    *haiku*)  modelName="Haiku" ;;
    *)        modelName="${modelId%%-*}" ;;
esac

# Path — use $PWD (script runs from project root, immune to cd in session)
currentDir="$PWD"
displayPath=$(basename "$currentDir")

# Git branch
gitBranch=""
if [ -d "$currentDir/.git" ] || git -C "$currentDir" rev-parse --git-dir >/dev/null 2>&1; then
    branch=$(git -C "$currentDir" symbolic-ref --short HEAD 2>/dev/null)
    if [ -z "$branch" ]; then
        branch=$(git -C "$currentDir" rev-parse --short HEAD 2>/dev/null)
        if [ -n "$branch" ]; then
            branch="detached:$branch"
        fi
    fi
    gitBranch="$branch"
fi

# Context window
usedPercentage=$(extractJsonNumber "used_percentage")
maxTokens=$(extractJsonNumber "max_tokens")
usedPercentage="${usedPercentage:-0}"
maxTokens="${maxTokens:-200000}"

# Calculate tokens (integer math)
contextPercent="${usedPercentage%%.*}"
contextPercent="${contextPercent:-0}"
currentTokens=$(( ${maxTokens%%.*} * ${contextPercent} / 100 ))

if [ "$currentTokens" -ge 1000 ]; then
    tokensK=$((currentTokens / 1000))
    tokensRemainder=$(( (currentTokens % 1000) / 100 ))
    if [ "$tokensRemainder" -gt 0 ]; then
        tokensFormatted="${tokensK}.${tokensRemainder}K"
    else
        tokensFormatted="${tokensK}K"
    fi
else
    tokensFormatted="$currentTokens"
fi

# Context color
if [ "$contextPercent" -lt 50 ]; then
    contextColor="$Green"
elif [ "$contextPercent" -lt 80 ]; then
    contextColor="$Yellow"
else
    contextColor="$Red"
fi

# 5-hour usage limit (cached with 60s TTL)
usageCacheFile="/tmp/claude-statusline-usage.json"
usageRemaining=""
cacheTTL=60

fetchUsage() {
    local oauthToken
    oauthToken=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null)
    if [ -z "$oauthToken" ]; then
        return 1
    fi

    # Extract accessToken from the credentials JSON
    local accessToken
    accessToken=$(echo "$oauthToken" | grep -o '"accessToken"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*:[[:space:]]*"\([^"]*\)"/\1/' | head -1)
    if [ -z "$accessToken" ]; then
        return 1
    fi

    local response
    response=$(curl -s --max-time 3 \
        -H "Authorization: Bearer ${accessToken}" \
        "https://api.anthropic.com/api/oauth/usage" 2>/dev/null)
    if [ -z "$response" ]; then
        return 1
    fi

    echo "$response" > "$usageCacheFile"
}

getUsageRemaining() {
    local needFetch=true

    if [ -f "$usageCacheFile" ]; then
        local cacheAge
        if [[ "$OSTYPE" == darwin* ]]; then
            local fileModTime
            fileModTime=$(stat -f "%m" "$usageCacheFile" 2>/dev/null)
            local now
            now=$(date +%s)
            cacheAge=$(( now - fileModTime ))
        else
            cacheAge=$(( $(date +%s) - $(stat -c "%Y" "$usageCacheFile" 2>/dev/null) ))
        fi

        if [ "$cacheAge" -lt "$cacheTTL" ]; then
            needFetch=false
        fi
    fi

    if $needFetch; then
        fetchUsage
    fi

    if [ -f "$usageCacheFile" ]; then
        local utilization
        utilization=$(grep -o '"utilization"[[:space:]]*:[[:space:]]*[0-9.]*' "$usageCacheFile" | head -1 | sed 's/.*:[[:space:]]*//')
        if [ -n "$utilization" ]; then
            # utilization is 0.0-1.0, convert to remaining percentage
            local utilizationInt
            utilizationInt=$(echo "$utilization" | sed 's/0\.\([0-9]*\).*/\1/' | sed 's/^0*//')
            # Use awk for floating point math
            usageRemaining=$(awk "BEGIN { printf \"%d\", (1 - ${utilization}) * 100 }")
        fi
    fi
}

getUsageRemaining

# Usage limit color
usageLimitColor="$Green"
if [ -n "$usageRemaining" ]; then
    if [ "$usageRemaining" -lt 20 ]; then
        usageLimitColor="$Red"
    elif [ "$usageRemaining" -lt 50 ]; then
        usageLimitColor="$Yellow"
    fi
fi

# Nerd Font icons (UTF-8 encoded for bash 3.2 compatibility)
userIcon=$(printf '\xee\xae\x99')
folderIcon=$(printf '\xef\x81\xbb')
gitBranchIcon=$(printf '\xee\x9c\xa5')
contextIcon=$(printf '\xef\x80\xb7')
batteryIcon=$(printf '\xf3\xb0\x84\xa5')

# Build output — line 1: model + project folder
line1="${TealBright}${userIcon} ${modelName}${Reset}"
line1+=" on "
line1+="${CyanLight}${folderIcon} ${displayPath}${Reset}"

# Build output — line 2: branch + context + usage limit
line2=""

if [ -n "$gitBranch" ]; then
    line2+="${TealDark}${gitBranchIcon}${gitBranch}${Reset}"
fi

if [ "$currentTokens" -gt 0 ]; then
    if [ -n "$line2" ]; then
        line2+=" "
    fi
    line2+="${contextColor}${contextIcon} ${tokensFormatted} (${contextPercent}%)${Reset}"
fi

if [ -n "$usageRemaining" ]; then
    if [ -n "$line2" ]; then
        line2+=" "
    fi
    line2+="${usageLimitColor}${batteryIcon} ${usageRemaining}%${Reset}"
fi

printf '%b\n' "$line1"
if [ -n "$line2" ]; then
    printf '%b\n' "$line2"
fi
