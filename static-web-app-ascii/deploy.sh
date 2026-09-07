#!/usr/bin/env bash
set -euo pipefail

if (( $# < 3 || $# > 6 )); then
  printf 'Usage: %s <resource-group> <static-web-app-name> <storage-account-name> [location] [admin-group-name] [user-group-name]\n' "$0" >&2
  exit 1
fi

for command in az node npx pwsh; do
  if ! command -v "$command" >/dev/null 2>&1; then
    printf 'Required command not found: %s\n' "$command" >&2
    exit 1
  fi
done

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
arguments=(
  -ResourceGroupName "$1"
  -StaticWebAppName "$2"
  -StorageAccountName "$3"
)

if (( $# >= 4 )); then arguments+=(-Location "$4"); fi
if (( $# >= 5 )); then arguments+=(-AdminGroupName "$5"); fi
if (( $# >= 6 )); then arguments+=(-UserGroupName "$6"); fi

exec pwsh -NoProfile -File "$project_root/infra/deploy.ps1" "${arguments[@]}"
