#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
api_directory="$project_root/api"
swa_port="${SWA_PORT:-4280}"

for command in node npm npx; do
  command -v "$command" >/dev/null 2>&1 || { printf 'Required command not found: %s\n' "$command" >&2; exit 1; }
done

[[ -d "$api_directory/node_modules" ]] || npm --prefix "$api_directory" install
[[ -f "$api_directory/.env" ]] || cp "$api_directory/.env.example" "$api_directory/.env"
cp "$project_root/app/config.example.js" "$project_root/app/config.js"

(
  cd "$api_directory"
  set -a
  source .env
  set +a
  export ALLOWED_ORIGIN="http://localhost:$swa_port"
  exec npm start
) &
api_process_id=$!
trap 'kill "$api_process_id" 2>/dev/null || true' EXIT

exec npx --yes --package @azure/static-web-apps-cli swa start "$project_root/app" --api-devserver-url "http://localhost:7071" --swa-config-location "$project_root/app" --port "$swa_port"
