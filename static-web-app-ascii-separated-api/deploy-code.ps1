[CmdletBinding()]
param(
    [ValidatePattern('^[a-z0-9]{2,10}$')] [string] $BaseName = "asciitype",
    [ValidateSet("dev", "test", "prod")] [string] $Environment = "dev",
    [string] $Location = "eastus2",
    [ValidatePattern('^[a-z0-9]{2,4}$')] [string] $LocationCode = "eus2",
    [string] $SubscriptionId
)

$ErrorActionPreference = "Stop"
$projectRoot = $PSScriptRoot

foreach ($command in "az", "node", "npx") {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
        throw "Required command not found: $command"
    }
}

function Invoke-Az([string[]] $Arguments) {
    & az @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Azure CLI command failed: az $($Arguments -join ' ')" }
}

Write-Host "==> [1/3] Resolving active Azure subscription and target resources..." -ForegroundColor Cyan
if ($SubscriptionId) { Invoke-Az @("account", "set", "--subscription", $SubscriptionId) }
Invoke-Az @("account", "show", "--output", "none")
$activeSubscriptionRaw = (& az account show --query id --output tsv)
$activeSubscriptionId = if ($activeSubscriptionRaw) { $activeSubscriptionRaw.ToString().Trim() } else { "" }
if ($LASTEXITCODE -ne 0 -or -not $activeSubscriptionId) { throw "Could not resolve active Azure subscription." }

$uniqueSuffix = ($activeSubscriptionId -replace '-', '').Substring(0, 8).ToLowerInvariant()
$namePrefix = "$BaseName-$Environment-$LocationCode"
$compactName = "$BaseName$Environment"
$resourceGroupName = "rg-$namePrefix"
$staticWebAppName = "stapp-$namePrefix-$uniqueSuffix"
$apiName = "ca-$namePrefix-api"
$containerRegistryName = "acr$compactName$uniqueSuffix"

Write-Host "==> [2/3] Building and updating API container image..." -ForegroundColor Cyan
Invoke-Az @("acr", "build", "--registry", $containerRegistryName, "--image", "$apiName`:latest", (Join-Path $projectRoot "api"))

$registryServerRaw = (& az acr show --resource-group $resourceGroupName --name $containerRegistryName --query loginServer --output tsv)
$registryServer = if ($registryServerRaw) { $registryServerRaw.ToString().Trim() } else { "" }

Invoke-Az @("containerapp", "update", "--name", $apiName, "--resource-group", $resourceGroupName, "--image", "$registryServer/$apiName`:latest")

$fqdnRaw = (& az containerapp show --name $apiName --resource-group $resourceGroupName --query properties.configuration.ingress.fqdn --output tsv)
$fqdn = if ($fqdnRaw) { $fqdnRaw.ToString().Trim() } else { "" }
if (-not $fqdn) { throw "Could not resolve FQDN for Container App '$apiName'." }
$apiOrigin = "https://$fqdn"

Write-Host "==> [3/3] Generating config and deploying frontend via SWA CLI..." -ForegroundColor Cyan
Set-Content -Path (Join-Path $projectRoot "app/config.js") -Value "window.TYPECAST_API_BASE_URL = `"$apiOrigin`";" -NoNewline

try {
    $tokenRaw = (& az staticwebapp secrets list --name $staticWebAppName --resource-group $resourceGroupName --query properties.apiKey --output tsv)
    $token = if ($tokenRaw) { $tokenRaw.ToString().Trim() } else { "" }
    if (-not $token) { throw "Could not retrieve deployment token for Static Web App '$staticWebAppName'." }

    Push-Location $projectRoot
    try {
        npx --yes @azure/static-web-apps-cli deploy --app-location app --deployment-token $token --env production
    } finally {
        Pop-Location
    }
} finally {
    Remove-Item (Join-Path $projectRoot "app/config.js") -ErrorAction SilentlyContinue
}

$webHostnameRaw = (& az staticwebapp show --name $staticWebAppName --resource-group $resourceGroupName --query defaultHostname --output tsv)
$webHostname = if ($webHostnameRaw) { $webHostnameRaw.ToString().Trim() } else { "" }

Write-Host "`n✔ Code deployment complete:" -ForegroundColor Green
Write-Host "  Web App: https://$webHostname" -ForegroundColor Green
Write-Host "  API Origin: $apiOrigin" -ForegroundColor Green
