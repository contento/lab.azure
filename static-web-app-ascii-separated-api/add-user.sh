#!/usr/bin/env bash
set -euo pipefail

for command in az pwsh; do
  if ! command -v "$command" >/dev/null 2>&1; then
    printf 'Required command not found: %s\n' "$command" >&2
    exit 1
  fi
done

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
arguments=()

if (( $# >= 1 )); then arguments+=(-User "$1"); fi
if (( $# >= 2 )); then arguments+=(-Role "$2"); fi
if (( $# >= 3 )); then arguments+=(-BaseName "$3"); fi
if (( $# >= 4 )); then arguments+=(-Environment "$4"); fi
if (( $# >= 5 )); then arguments+=(-LocationCode "$5"); fi
if (( $# == 6 )); then arguments+=(-SubscriptionId "$6"); fi

exec pwsh -NoProfile -File "$project_root/add-user.ps1" "${arguments[@]}"
