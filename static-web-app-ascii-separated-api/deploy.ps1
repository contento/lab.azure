[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $ResourceGroupName,
    [Parameter(Mandatory)] [string] $StaticWebAppName,
    [Parameter(Mandatory)] [string] $ContainerAppsEnvironmentName,
    [Parameter(Mandatory)] [string] $ApiName,
    [Parameter(Mandatory)] [string] $ContainerRegistryName,
    [string] $Location = "eastus"
)

$ErrorActionPreference = "Stop"
$projectRoot = $PSScriptRoot
foreach ($command in "az", "node", "npx") { if (-not (Get-Command $command -ErrorAction SilentlyContinue)) { throw "Required command not found: $command" } }

function Invoke-Az([string[]] $Arguments) { & az @Arguments; if ($LASTEXITCODE -ne 0) { throw "Azure CLI command failed: az $($Arguments -join ' ')" } }

Invoke-Az @("account", "show", "--output", "none")
Invoke-Az @("group", "create", "--name", $ResourceGroupName, "--location", $Location, "--output", "none")
Invoke-Az @("acr", "create", "--resource-group", $ResourceGroupName, "--name", $ContainerRegistryName, "--sku", "Basic", "--admin-enabled", "true", "--output", "none")
$registryServer = (& az acr show --resource-group $ResourceGroupName --name $ContainerRegistryName --query loginServer --output tsv).Trim()
$registryCredentials = (& az acr credential show --resource-group $ResourceGroupName --name $ContainerRegistryName --query '{username:username,password:passwords[0].value}' --output json | ConvertFrom-Json)
if ($LASTEXITCODE -ne 0) { throw "Could not retrieve Container Registry credentials." }
Invoke-Az @("acr", "build", "--registry", $ContainerRegistryName, "--image", "$ApiName`:latest", (Join-Path $projectRoot "api"))

$placeholderOrigin = "https://placeholder.invalid"
$deployment = (& az deployment group create --resource-group $ResourceGroupName --template-file (Join-Path $projectRoot "infra/main.bicep") --parameters staticWebAppName=$StaticWebAppName containerAppsEnvironmentName=$ContainerAppsEnvironmentName apiName=$ApiName apiImage="$registryServer/$ApiName`:latest" registryServer=$registryServer registryUsername=$registryCredentials.username registryPassword=$registryCredentials.password allowedOrigin=$placeholderOrigin --query properties.outputs --output json | ConvertFrom-Json)
if ($LASTEXITCODE -ne 0) { throw "Infrastructure deployment failed." }

$webOrigin = $deployment.endpoints.value.web
$deployment = (& az deployment group create --resource-group $ResourceGroupName --template-file (Join-Path $projectRoot "infra/main.bicep") --parameters staticWebAppName=$StaticWebAppName containerAppsEnvironmentName=$ContainerAppsEnvironmentName apiName=$ApiName apiImage="$registryServer/$ApiName`:latest" registryServer=$registryServer registryUsername=$registryCredentials.username registryPassword=$registryCredentials.password allowedOrigin=$webOrigin --query properties.outputs --output json | ConvertFrom-Json)
if ($LASTEXITCODE -ne 0) { throw "Infrastructure update failed." }

$apiOrigin = $deployment.endpoints.value.api
Set-Content -Path (Join-Path $projectRoot "app/config.js") -Value "window.TYPECAST_API_BASE_URL = `"$apiOrigin`";" -NoNewline
try {
    $token = (& az staticwebapp secrets list --name $StaticWebAppName --resource-group $ResourceGroupName --query properties.apiKey --output tsv).Trim()
    Push-Location $projectRoot
    try { npx --yes @azure/static-web-apps-cli deploy --app-location app --deployment-token $token } finally { Pop-Location }
} finally { Remove-Item (Join-Path $projectRoot "app/config.js") -ErrorAction SilentlyContinue }
Write-Host "Deployment complete: $webOrigin"
