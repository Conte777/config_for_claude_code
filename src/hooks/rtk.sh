#!/usr/bin/env bash
command -v rtk >/dev/null 2>&1 || exit 0
exec rtk "$@"
