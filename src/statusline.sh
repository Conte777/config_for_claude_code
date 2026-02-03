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

# Path
currentDir=$(extractJson "current_dir")
if [ -z "$currentDir" ]; then
    currentDir="$(pwd)"
fi
displayPath="${currentDir/#$HOME/~}"

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

# Nerd Font icons (UTF-8 encoded for bash 3.2 compatibility)
userIcon=$(printf '\xee\xae\x99')
folderIcon=$(printf '\xef\x81\xbb')
gitBranchIcon=$(printf '\xee\x9c\xa5')
contextIcon=$(printf '\xef\x80\xb7')

# Build output
output="${TealBright}${userIcon} ${modelName}${Reset}"
output+=" on "
output+="${CyanLight}${folderIcon} ${displayPath}${Reset}"

if [ -n "$gitBranch" ]; then
    output+=" ${TealDark}${gitBranchIcon}${gitBranch}${Reset}"
fi

if [ "$currentTokens" -gt 0 ]; then
    output+=" ${contextColor}${contextIcon} ${tokensFormatted} (${contextPercent}%)${Reset}"
fi

printf '%b\n' "$output"
