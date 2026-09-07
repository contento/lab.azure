#!/usr/bin/env bash
set -euo pipefail

if (( $# < 5 || $# > 6 )); then
  printf 'Usage: %s <resource-group> <static-web-app-name> <container-apps-environment-name> <api-name> <container-registry-name> [location]\n' "$0" >&2
  exit 1
fi
project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
arguments=(-ResourceGroupName "$1" -StaticWebAppName "$2" -ContainerAppsEnvironmentName "$3" -ApiName "$4" -ContainerRegistryName "$5")
if (( $# == 6 )); then arguments+=(-Location "$6"); fi
exec pwsh -NoProfile -File "$project_root/deploy.ps1" "${arguments[@]}"
