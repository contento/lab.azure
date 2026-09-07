[CmdletBinding()]
param(
    [ValidatePattern('^[a-z0-9]{2,10}$')] [string] $BaseName = "asciitype",
    [ValidateSet("dev", "test", "prod")] [string] $Environment = "dev",
    [string] $Location = "eastus2",
    [ValidatePattern('^[a-z0-9]{2,4}$')] [string] $LocationCode = "eus2",
    [string] $SubscriptionId,
    [string] $ParametersFile = (Join-Path $PSScriptRoot "parameters.dev.bicepparam")
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot

if (-not (Test-Path -Path $ParametersFile -PathType Leaf)) {
    throw "Bicep parameters file not found: $ParametersFile"
}

foreach ($command in "az", "node", "npx") {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
        throw "Required command not found: $command"
    }
}

function Invoke-Az([string[]] $Arguments) {
    & az @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Azure CLI command failed: az $($Arguments -join ' ')" }
}

Write-Host "==> [1/5] Resolving active Azure subscription..." -ForegroundColor Cyan
if ($SubscriptionId) { Invoke-Az @("account", "set", "--subscription", $SubscriptionId) }
Invoke-Az @("account", "show", "--output", "none")
$activeSubscriptionRaw = (& az account show --query id --output tsv)
$activeSubscriptionId = if ($activeSubscriptionRaw) { $activeSubscriptionRaw.ToString().Trim() } else { "" }
if ($LASTEXITCODE -ne 0 -or -not $activeSubscriptionId) { throw "Could not resolve the active Azure subscription." }
Write-Host "    Active Subscription: $activeSubscriptionId" -ForegroundColor Gray

$uniqueSuffix = ($activeSubscriptionId -replace '-', '').Substring(0, 8).ToLowerInvariant()
$namePrefix = "$BaseName-$Environment-$LocationCode"
$compactName = "$BaseName$Environment"
$resourceGroupName = "rg-$namePrefix"
$staticWebAppName = "stapp-$namePrefix-$uniqueSuffix"
$apiName = "ca-$namePrefix-api"
$containerRegistryName = "acr$compactName$uniqueSuffix"

Write-Host "==> [2/5] Ensuring resource group '$resourceGroupName' in '$Location'..." -ForegroundColor Cyan
Invoke-Az @("group", "create", "--name", $resourceGroupName, "--location", $Location, "--output", "none")

Write-Host "==> [3/5] Ensuring Azure Container Registry '$containerRegistryName' and building initial API image..." -ForegroundColor Cyan
Invoke-Az @("acr", "create", "--resource-group", $resourceGroupName, "--name", $containerRegistryName, "--sku", "Basic", "--admin-enabled", "true", "--output", "none")
$registryServerRaw = (& az acr show --resource-group $resourceGroupName --name $containerRegistryName --query loginServer --output tsv)
$registryServer = if ($registryServerRaw) { $registryServerRaw.ToString().Trim() } else { "" }

$registryCredsJson = (& az acr credential show --resource-group $resourceGroupName --name $containerRegistryName --query '{username:username,password:passwords[0].value}' --output json)
if ($LASTEXITCODE -ne 0 -or -not $registryCredsJson) { throw "Could not retrieve Container Registry credentials." }
$registryCredentials = $registryCredsJson | ConvertFrom-Json

Invoke-Az @("acr", "build", "--registry", $containerRegistryName, "--image", "$apiName`:latest", (Join-Path $projectRoot "api"))

Write-Host "==> [4/5] Deploying Bicep infrastructure template..." -ForegroundColor Cyan
$placeholderOrigin = "https://placeholder.invalid"
$deploymentJson = (& az deployment group create --resource-group $resourceGroupName --template-file (Join-Path $PSScriptRoot "main.bicep") --parameters $ParametersFile baseName=$BaseName environment=$Environment location=$Location locationCode=$LocationCode subscriptionId=$activeSubscriptionId apiImage="$registryServer/$apiName`:latest" registryServer=$registryServer registryUsername=$registryCredentials.username registryPassword=$registryCredentials.password allowedOrigin=$placeholderOrigin --query properties.outputs --output json)
if ($LASTEXITCODE -ne 0 -or -not $deploymentJson) { throw "Infrastructure deployment failed." }
$deployment = $deploymentJson | ConvertFrom-Json

$webOrigin = if ($deployment -and $deployment.endpoints -and $deployment.endpoints.value) { $deployment.endpoints.value.web } else { $null }
if (-not $webOrigin) { throw "Could not retrieve web endpoint from Bicep outputs." }

$deploymentJson = (& az deployment group create --resource-group $resourceGroupName --template-file (Join-Path $PSScriptRoot "main.bicep") --parameters $ParametersFile baseName=$BaseName environment=$Environment location=$Location locationCode=$LocationCode subscriptionId=$activeSubscriptionId apiImage="$registryServer/$apiName`:latest" registryServer=$registryServer registryUsername=$registryCredentials.username registryPassword=$registryCredentials.password allowedOrigin=$webOrigin --query properties.outputs --output json)
if ($LASTEXITCODE -ne 0 -or -not $deploymentJson) { throw "Infrastructure update failed." }
$deployment = $deploymentJson | ConvertFrom-Json

$apiOrigin = if ($deployment -and $deployment.endpoints -and $deployment.endpoints.value) { $deployment.endpoints.value.api } else { $null }

Write-Host "==> [5/5] Deploying application code via deploy-code.ps1..." -ForegroundColor Cyan
& (Join-Path $projectRoot "deploy-code.ps1") -BaseName $BaseName -Environment $Environment -Location $Location -LocationCode $LocationCode -SubscriptionId $activeSubscriptionId

Write-Host "`n✔ Infrastructure deployment complete:" -ForegroundColor Green
Write-Host "  Web App: $webOrigin" -ForegroundColor Green
Write-Host "  API App: $apiOrigin" -ForegroundColor Green
Write-Host "  Resource Group: $resourceGroupName" -ForegroundColor Green
