[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$projectRoot = $PSScriptRoot
$apiDirectory = Join-Path $projectRoot "api"
$swaPort = if ($env:SWA_PORT) { $env:SWA_PORT } else { "4281" }
$apiPort = if ($env:API_PORT) { $env:API_PORT } else { "7072" }

foreach ($command in "node", "npm", "npx") {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) { throw "Required command not found: $command" }
}
if (-not (Test-Path (Join-Path $apiDirectory "node_modules"))) { & npm --prefix $apiDirectory install }
if (-not (Test-Path (Join-Path $apiDirectory ".env"))) { Copy-Item (Join-Path $apiDirectory ".env.example") (Join-Path $apiDirectory ".env") }
[System.IO.File]::WriteAllText((Join-Path $projectRoot "app/config.js"), "window.TYPECAST_API_BASE_URL = `"http://127.0.0.1:$apiPort`";`n")

$env:PORT = $apiPort
$env:ALLOWED_ORIGIN = "http://localhost:$swaPort"
$apiProcess = Start-Process -FilePath "npm" -ArgumentList "start" -WorkingDirectory $apiDirectory -PassThru
try {
    & npx --yes --package @azure/static-web-apps-cli swa start (Join-Path $projectRoot "app") --api-devserver-url "http://127.0.0.1:$apiPort" --swa-config-location (Join-Path $projectRoot "app") --port $swaPort
} finally {
    if (-not $apiProcess.HasExited) { Stop-Process -Id $apiProcess.Id }
}
