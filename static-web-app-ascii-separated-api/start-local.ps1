[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$projectRoot = $PSScriptRoot
$apiDirectory = Join-Path $projectRoot "api"
$swaPort = if ($env:SWA_PORT) { $env:SWA_PORT } else { "4280" }

foreach ($command in "node", "npm", "npx") {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) { throw "Required command not found: $command" }
}
if (-not (Test-Path (Join-Path $apiDirectory "node_modules"))) { & npm --prefix $apiDirectory install }
if (-not (Test-Path (Join-Path $apiDirectory ".env"))) { Copy-Item (Join-Path $apiDirectory ".env.example") (Join-Path $apiDirectory ".env") }
Copy-Item (Join-Path $projectRoot "app/config.example.js") (Join-Path $projectRoot "app/config.js")

$env:ALLOWED_ORIGIN = "http://localhost:$swaPort"
$apiProcess = Start-Process -FilePath "npm" -ArgumentList "start" -WorkingDirectory $apiDirectory -PassThru
try {
    & npx --yes --package @azure/static-web-apps-cli swa start (Join-Path $projectRoot "app") --api-devserver-url "http://localhost:7071" --swa-config-location (Join-Path $projectRoot "app") --port $swaPort
} finally {
    if (-not $apiProcess.HasExited) { Stop-Process -Id $apiProcess.Id }
}
