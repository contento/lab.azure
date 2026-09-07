[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$projectRoot = $PSScriptRoot
$apiDirectory = Join-Path $projectRoot "api"
$settingsFile = Join-Path $apiDirectory "local.settings.json"

foreach ($command in "node", "npm", "func") {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
        throw "Required command not found: $command"
    }
}

if (-not (Test-Path (Join-Path $apiDirectory "node_modules"))) {
    & npm --prefix $apiDirectory ci
    if ($LASTEXITCODE -ne 0) { throw "npm ci failed." }
}

if (-not (Test-Path $settingsFile)) {
    Copy-Item (Join-Path $apiDirectory "local.settings.example.json") $settingsFile
    Write-Host "Created $settingsFile from the local development template."
}

$functionsProcess = Start-Process -FilePath "func" -ArgumentList "start", "--port", "7071" -WorkingDirectory $apiDirectory -PassThru
try {
    & npx --yes --package @azure/static-web-apps-cli swa start (Join-Path $projectRoot "app") `
        --api-devserver-url "http://localhost:7071" `
        --swa-config-location (Join-Path $projectRoot "local")
    if ($LASTEXITCODE -ne 0) { throw "Static Web Apps emulator failed to start." }
} finally {
    if (-not $functionsProcess.HasExited) {
        Stop-Process -Id $functionsProcess.Id
    }
}
