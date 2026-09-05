#!/usr/bin/env bash
command -v adrafinil >/dev/null 2>&1 || exit 0
exec adrafinil "$@"
