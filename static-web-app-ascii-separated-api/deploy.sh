#!/usr/bin/env bash
set -euo pipefail

if (( $# < 1 || $# > 5 )); then
  printf 'Usage: %s <base-name> [environment] [location] [location-code] [subscription-id]\n' "$0" >&2
  exit 1
fi
project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
arguments=(-BaseName "$1")
if (( $# >= 2 )); then arguments+=(-Environment "$2"); fi
if (( $# >= 3 )); then arguments+=(-Location "$3"); fi
if (( $# >= 4 )); then arguments+=(-LocationCode "$4"); fi
if (( $# == 5 )); then arguments+=(-SubscriptionId "$5"); fi
exec pwsh -NoProfile -File "$project_root/deploy.ps1" "${arguments[@]}"
