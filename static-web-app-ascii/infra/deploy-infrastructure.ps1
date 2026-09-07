[CmdletBinding()]
param(
    [ValidatePattern('^[a-z0-9]{2,10}$')] [string] $BaseName = "typecast",
    [ValidateSet("dev", "test", "prod")] [string] $Environment = "dev",
    [string] $Location = "eastus2",
    [ValidatePattern('^[a-z0-9]{2,4}$')] [string] $LocationCode = "eus2",
    [string] $SubscriptionId,
    [string] $ParametersFile = (Join-Path $PSScriptRoot "parameters.dev.bicepparam")
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $projectRoot "app/staticwebapp.config.json"
$originalConfig = Get-Content -Raw $configPath

if (-not (Test-Path -Path $ParametersFile -PathType Leaf)) {
    throw "Bicep parameters file not found: $ParametersFile"
}

function Invoke-Az([string[]] $Arguments) {
    & az @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Azure CLI command failed: az $($Arguments -join ' ')" }
}

function Get-OrCreateGroup([string] $DisplayName) {
    $groupId = (& az ad group show --group $DisplayName --query id --output tsv 2>$null)
    if ($LASTEXITCODE -ne 0 -or -not $groupId) {
        Write-Host "    Creating Entra group '$DisplayName'..." -ForegroundColor Gray
        $mailNickname = ($DisplayName.ToLowerInvariant() -replace '[^a-z0-9]', '')
        $groupId = (& az ad group create --display-name $DisplayName --mail-nickname $mailNickname --query id --output tsv)
        if ($LASTEXITCODE -ne 0) { throw "Could not create Entra group '$DisplayName'." }
    } else {
        Write-Host "    Found existing Entra group '$DisplayName'." -ForegroundColor Gray
    }
    return $groupId.Trim()
}

Write-Host "==> [1/7] Resolving active Azure subscription..." -ForegroundColor Cyan
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
$storageAccountName = "st$compactName$uniqueSuffix"
$adminGroupName = "grp-$namePrefix-admins"
$userGroupName = "grp-$namePrefix-users"

Write-Host "==> [2/7] Ensuring resource group '$resourceGroupName' in '$Location'..." -ForegroundColor Cyan
Invoke-Az @("group", "create", "--name", $resourceGroupName, "--location", $Location, "--output", "none")

Write-Host "==> [3/7] Deploying Bicep infrastructure template..." -ForegroundColor Cyan
$deploymentJson = (& az deployment group create --resource-group $resourceGroupName --template-file (Join-Path $PSScriptRoot "main.bicep") --parameters $ParametersFile baseName=$BaseName environment=$Environment location=$Location locationCode=$LocationCode subscriptionId=$activeSubscriptionId --query properties.outputs --output json)
if ($LASTEXITCODE -ne 0 -or -not $deploymentJson) { throw "Infrastructure deployment failed." }
$deployment = $deploymentJson | ConvertFrom-Json

$tenantRaw = (& az account show --query tenantId --output tsv)
$tenantId = if ($tenantRaw) { $tenantRaw.ToString().Trim() } else { "" }
$hostname = if ($deployment -and $deployment.staticWebAppHostname) { $deployment.staticWebAppHostname.value } else { $null }
if (-not $hostname) { throw "Could not retrieve staticWebAppHostname from Bicep deployment outputs." }
Write-Host "    Static Web App Hostname: https://$hostname" -ForegroundColor Gray

Write-Host "==> [4/7] Ensuring Entra ID security groups..." -ForegroundColor Cyan
$adminGroupId = Get-OrCreateGroup $adminGroupName
$userGroupId = Get-OrCreateGroup $userGroupName

Write-Host "==> [5/7] Configuring Entra app registration '$staticWebAppName-auth'..." -ForegroundColor Cyan
$appDisplayName = "$staticWebAppName-auth"
$appIdRaw = (& az ad app list --display-name $appDisplayName --query '[0].appId' --output tsv 2>$null)
$appId = if ($appIdRaw) { $appIdRaw.ToString().Trim() } else { "" }

if (-not $appId) {
    Write-Host "    Creating app registration '$appDisplayName'..." -ForegroundColor Gray
    $appIdRaw = (& az ad app create --display-name $appDisplayName --sign-in-audience AzureADMyOrg --web-redirect-uris "https://$hostname/.auth/login/aad/callback" --query appId --output tsv)
    $appId = if ($appIdRaw) { $appIdRaw.ToString().Trim() } else { "" }
} else {
    Write-Host "    Updating existing app registration '$appDisplayName'..." -ForegroundColor Gray
    Invoke-Az @("ad", "app", "update", "--id", $appId, "--web-redirect-uris", "https://$hostname/.auth/login/aad/callback")
    $existingKeyIds = (& az ad app credential list --id $appId --query "[].keyId" --output tsv 2>$null)
    if ($existingKeyIds) {
        foreach ($keyId in $existingKeyIds) {
            if ($keyId) { Invoke-Az @("ad", "app", "credential", "delete", "--id", $appId, "--key-id", $keyId) }
        }
    }
}
Invoke-Az @("ad", "app", "update", "--id", $appId, "--set", "groupMembershipClaims=SecurityGroup")
$clientSecretRaw = (& az ad app credential reset --id $appId --append --display-name "static-web-app" --query password --output tsv)
$clientSecret = if ($clientSecretRaw) { $clientSecretRaw.ToString().Trim() } else { "" }

Write-Host "==> [6/7] Setting Static Web App application settings..." -ForegroundColor Cyan
Invoke-Az @("staticwebapp", "appsettings", "set", "--name", $staticWebAppName, "--resource-group", $resourceGroupName, "--setting-names", "AZURE_CLIENT_ID=$appId", "AZURE_CLIENT_SECRET=$clientSecret", "ADMIN_GROUP_ID=$adminGroupId", "USER_GROUP_ID=$userGroupId", "STORAGE_ACCOUNT_NAME=$storageAccountName", "SESSIONS_CONTAINER_NAME=sessions", "--output", "none")

Write-Host "==> [7/7] Publishing frontend and API..." -ForegroundColor Cyan
& (Join-Path $projectRoot "deploy-app.ps1") -BaseName $BaseName -Environment $Environment -Location $Location -LocationCode $LocationCode -SubscriptionId $activeSubscriptionId

Write-Host "`n✔ Infrastructure deployment complete: https://$hostname" -ForegroundColor Green
Write-Host "  Resource group: $resourceGroupName" -ForegroundColor Green
Write-Host "  Add people to '$adminGroupName' or '$userGroupName' through your Entra tenant's approved membership process." -ForegroundColor Green
