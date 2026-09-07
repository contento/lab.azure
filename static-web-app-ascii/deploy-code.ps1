[CmdletBinding()]
param(
    [ValidatePattern('^[a-z0-9]{2,10}$')] [string] $BaseName = "asciitype",
    [ValidateSet("dev", "test", "prod")] [string] $Environment = "dev",
    [string] $Location = "eastus2",
    [ValidatePattern('^[a-z0-9]{2,4}$')] [string] $LocationCode = "eus2",
    [string] $SubscriptionId
)

$ErrorActionPreference = "Stop"

foreach ($command in "az", "node", "npx") {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
        throw "Required command not found: $command"
    }
}

function Invoke-Az([string[]] $Arguments) {
    & az @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Azure CLI command failed: az $($Arguments -join ' ')" }
}

Write-Host "==> [1/3] Resolving active Azure subscription and Static Web App..." -ForegroundColor Cyan
if ($SubscriptionId) { Invoke-Az @("account", "set", "--subscription", $SubscriptionId) }
Invoke-Az @("account", "show", "--output", "none")
$activeSubscriptionRaw = (& az account show --query id --output tsv)
$activeSubscriptionId = if ($activeSubscriptionRaw) { $activeSubscriptionRaw.ToString().Trim() } else { "" }
if ($LASTEXITCODE -ne 0 -or -not $activeSubscriptionId) { throw "Could not resolve active Azure subscription." }

$uniqueSuffix = ($activeSubscriptionId -replace '-', '').Substring(0, 8).ToLowerInvariant()
$namePrefix = "$BaseName-$Environment-$LocationCode"
$resourceGroupName = "rg-$namePrefix"
$staticWebAppName = "stapp-$namePrefix-$uniqueSuffix"

$tenantRaw = (& az account show --query tenantId --output tsv)
$tenantId = if ($tenantRaw) { $tenantRaw.ToString().Trim() } else { "" }

Write-Host "==> [2/3] Retrieving deployment token for '$staticWebAppName'..." -ForegroundColor Cyan
$deploymentTokenRaw = (& az staticwebapp secrets list --name $staticWebAppName --resource-group $resourceGroupName --query properties.apiKey --output tsv)
$deploymentToken = if ($deploymentTokenRaw) { $deploymentTokenRaw.ToString().Trim() } else { "" }
if (-not $deploymentToken) { throw "Could not retrieve deployment token for '$staticWebAppName' in resource group '$resourceGroupName'." }

Write-Host "==> [3/3] Publishing frontend ('app') and API ('api') via SWA CLI..." -ForegroundColor Cyan
$projectRoot = $PSScriptRoot
$configPath = Join-Path $projectRoot "app/staticwebapp.config.json"
$originalConfig = Get-Content -Raw $configPath

try {
    Set-Content -Path $configPath -Value ($originalConfig.Replace("__TENANT_ID__", $tenantId)) -NoNewline
    Push-Location $projectRoot
    try {
        npx --yes @azure/static-web-apps-cli deploy --app-location app --api-location api --api-language node --api-version 20 --deployment-token $deploymentToken --env production
    } finally {
        Pop-Location
    }
} finally {
    Set-Content -Path $configPath -Value $originalConfig -NoNewline
}

$hostname = (& az staticwebapp show --name $staticWebAppName --resource-group $resourceGroupName --query defaultHostname --output tsv 2>$null)
Write-Host "`n✔ Code deployment complete: https://$hostname" -ForegroundColor Green
