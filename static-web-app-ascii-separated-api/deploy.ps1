[CmdletBinding()]
param(
    [Parameter(Mandatory)] [ValidatePattern('^[a-z0-9]{2,10}$')] [string] $BaseName,
    [ValidateSet("dev", "test", "prod")] [string] $Environment = "dev",
    [string] $Location = "eastus",
    [ValidatePattern('^[a-z0-9]{2,4}$')] [string] $LocationCode = "eus",
    [string] $SubscriptionId
)

$ErrorActionPreference = "Stop"
$projectRoot = $PSScriptRoot
foreach ($command in "az", "node", "npx") { if (-not (Get-Command $command -ErrorAction SilentlyContinue)) { throw "Required command not found: $command" } }

function Invoke-Az([string[]] $Arguments) { & az @Arguments; if ($LASTEXITCODE -ne 0) { throw "Azure CLI command failed: az $($Arguments -join ' ')" } }

if ($SubscriptionId) { Invoke-Az @("account", "set", "--subscription", $SubscriptionId) }
Invoke-Az @("account", "show", "--output", "none")
$subscriptionId = (& az account show --query id --output tsv).Trim()
if ($LASTEXITCODE -ne 0 -or -not $subscriptionId) { throw "Could not resolve the active Azure subscription." }

$uniqueSuffix = ($subscriptionId -replace '-', '').Substring(0, 8).ToLowerInvariant()
$namePrefix = "$BaseName-$Environment-$LocationCode"
$resourceGroupName = "rg-$namePrefix"
$staticWebAppName = "stapp-$namePrefix-$uniqueSuffix"
$containerAppsEnvironmentName = "cae-$namePrefix"
$apiName = "ca-$namePrefix-api"
$containerRegistryName = "acr$BaseName$Environment$uniqueSuffix"

Invoke-Az @("group", "create", "--name", $resourceGroupName, "--location", $Location, "--output", "none")
Invoke-Az @("acr", "create", "--resource-group", $resourceGroupName, "--name", $containerRegistryName, "--sku", "Basic", "--admin-enabled", "true", "--output", "none")
$registryServer = (& az acr show --resource-group $resourceGroupName --name $containerRegistryName --query loginServer --output tsv).Trim()
$registryCredentials = (& az acr credential show --resource-group $resourceGroupName --name $containerRegistryName --query '{username:username,password:passwords[0].value}' --output json | ConvertFrom-Json)
if ($LASTEXITCODE -ne 0) { throw "Could not retrieve Container Registry credentials." }
Invoke-Az @("acr", "build", "--registry", $containerRegistryName, "--image", "$apiName`:latest", (Join-Path $projectRoot "api"))

$placeholderOrigin = "https://placeholder.invalid"
$deployment = (& az deployment group create --resource-group $resourceGroupName --template-file (Join-Path $projectRoot "infra/main.bicep") --parameters namePrefix=$namePrefix uniqueSuffix=$uniqueSuffix apiImage="$registryServer/$apiName`:latest" registryServer=$registryServer registryUsername=$registryCredentials.username registryPassword=$registryCredentials.password allowedOrigin=$placeholderOrigin --query properties.outputs --output json | ConvertFrom-Json)
if ($LASTEXITCODE -ne 0) { throw "Infrastructure deployment failed." }

$webOrigin = $deployment.endpoints.value.web
$deployment = (& az deployment group create --resource-group $resourceGroupName --template-file (Join-Path $projectRoot "infra/main.bicep") --parameters namePrefix=$namePrefix uniqueSuffix=$uniqueSuffix apiImage="$registryServer/$apiName`:latest" registryServer=$registryServer registryUsername=$registryCredentials.username registryPassword=$registryCredentials.password allowedOrigin=$webOrigin --query properties.outputs --output json | ConvertFrom-Json)
if ($LASTEXITCODE -ne 0) { throw "Infrastructure update failed." }

$apiOrigin = $deployment.endpoints.value.api
Set-Content -Path (Join-Path $projectRoot "app/config.js") -Value "window.TYPECAST_API_BASE_URL = `"$apiOrigin`";" -NoNewline
try {
    $token = (& az staticwebapp secrets list --name $staticWebAppName --resource-group $resourceGroupName --query properties.apiKey --output tsv).Trim()
    Push-Location $projectRoot
    try { npx --yes @azure/static-web-apps-cli deploy --app-location app --deployment-token $token } finally { Pop-Location }
} finally { Remove-Item (Join-Path $projectRoot "app/config.js") -ErrorAction SilentlyContinue }
Write-Host "Deployment complete: $webOrigin"
Write-Host "Resource group: $resourceGroupName"
