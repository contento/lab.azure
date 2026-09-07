#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
api_directory="$project_root/api"
settings_file="$api_directory/local.settings.json"

for command in node npm func; do
  if ! command -v "$command" >/dev/null 2>&1; then
    printf 'Required command not found: %s\n' "$command" >&2
    exit 1
  fi
done

if [[ ! -d "$api_directory/node_modules" ]]; then
  npm --prefix "$api_directory" ci
fi

if [[ ! -f "$settings_file" ]]; then
  cp "$api_directory/local.settings.example.json" "$settings_file"
  printf 'Created %s from the local development template.\n' "$settings_file"
fi

(
  cd "$api_directory"
  exec func start --port 7071
) &
functions_process_id=$!
trap 'kill "$functions_process_id" 2>/dev/null || true' EXIT

exec npx --yes --package @azure/static-web-apps-cli swa start "$project_root/app" \
  --api-devserver-url "http://localhost:7071" \
  --swa-config-location "$project_root/local"
