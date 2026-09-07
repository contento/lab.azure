#!/usr/bin/env bash
set -euo pipefail

for command in az node npx pwsh; do
  if ! command -v "$command" >/dev/null 2>&1; then
    printf 'Required command not found: %s\n' "$command" >&2
    exit 1
  fi
done

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec pwsh -NoProfile -File "$script_dir/deploy-infrastructure.ps1" -ParametersFile "$script_dir/parameters.dev.bicepparam" "$@"
