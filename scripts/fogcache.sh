#!/usr/bin/env bash
# Cross-platform shim: run the single source of truth (fogcache.ps1) with pwsh.
# Translates GNU-style "--flag" arguments to PowerShell "-flag" switches.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
args=()
for arg in "$@"; do
  case "$arg" in
    --*) args+=("-${arg#--}") ;;
    *) args+=("$arg") ;;
  esac
done
exec pwsh -NoProfile -File "$DIR/fogcache.ps1" "${args[@]}"
