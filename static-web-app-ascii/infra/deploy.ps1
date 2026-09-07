[CmdletBinding()]
param(
    [Parameter(Mandatory)] [ValidatePattern('^[a-z0-9]{2,10}$')] [string] $BaseName,
    [ValidateSet("dev", "test", "prod")] [string] $Environment = "dev",
    [string] $Location = "eastus",
    [ValidatePattern('^[a-z0-9]{2,4}$')] [string] $LocationCode = "eus",
    [string] $SubscriptionId
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $projectRoot "app/staticwebapp.config.json"
$originalConfig = Get-Content -Raw $configPath

function Invoke-Az([string[]] $Arguments) {
    & az @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Azure CLI command failed: az $($Arguments -join ' ')" }
}

function Get-OrCreateGroup([string] $DisplayName) {
    $groupId = (& az ad group show --group $DisplayName --query id --output tsv 2>$null)
    if ($LASTEXITCODE -ne 0 -or -not $groupId) {
        $mailNickname = ($DisplayName.ToLowerInvariant() -replace '[^a-z0-9]', '')
        $groupId = (& az ad group create --display-name $DisplayName --mail-nickname $mailNickname --query id --output tsv)
        if ($LASTEXITCODE -ne 0) { throw "Could not create Entra group '$DisplayName'." }
    }
    return $groupId.Trim()
}

if ($SubscriptionId) { Invoke-Az @("account", "set", "--subscription", $SubscriptionId) }
Invoke-Az @("account", "show", "--output", "none")
$activeSubscriptionId = (& az account show --query id --output tsv).Trim()
if ($LASTEXITCODE -ne 0 -or -not $activeSubscriptionId) { throw "Could not resolve the active Azure subscription." }

$uniqueSuffix = ($activeSubscriptionId -replace '-', '').Substring(0, 8).ToLowerInvariant()
$namePrefix = "$BaseName-$Environment-$LocationCode"
$compactName = "$BaseName$Environment"
$resourceGroupName = "rg-$namePrefix"
$staticWebAppName = "stapp-$namePrefix-$uniqueSuffix"
$storageAccountName = "st$compactName$uniqueSuffix"
$adminGroupName = "grp-$namePrefix-admins"
$userGroupName = "grp-$namePrefix-users"

Invoke-Az @("group", "create", "--name", $resourceGroupName, "--location", $Location, "--output", "none")

$deployment = (& az deployment group create --resource-group $resourceGroupName --template-file (Join-Path $PSScriptRoot "main.bicep") --parameters namePrefix=$namePrefix compactName=$compactName uniqueSuffix=$uniqueSuffix --query properties.outputs --output json | ConvertFrom-Json)
if ($LASTEXITCODE -ne 0) { throw "Infrastructure deployment failed." }

$tenantId = (& az account show --query tenantId --output tsv).Trim()
$hostname = $deployment.staticWebAppHostname.value
$adminGroupId = Get-OrCreateGroup $AdminGroupName
$userGroupId = Get-OrCreateGroup $UserGroupName
$appDisplayName = "$StaticWebAppName-auth"
$appId = (& az ad app list --display-name $appDisplayName --query '[0].appId' --output tsv).Trim()
if (-not $appId) {
    $appId = (& az ad app create --display-name $appDisplayName --sign-in-audience AzureADMyOrg --web-redirect-uris "https://$hostname/.auth/login/aad/callback" --query appId --output tsv).Trim()
} else {
    Invoke-Az @("ad", "app", "update", "--id", $appId, "--web-redirect-uris", "https://$hostname/.auth/login/aad/callback")
    $existingKeyIds = (& az ad app credential list --id $appId --query "[].keyId" --output tsv)
    foreach ($keyId in $existingKeyIds) {
        if ($keyId) { Invoke-Az @("ad", "app", "credential", "delete", "--id", $appId, "--key-id", $keyId) }
    }
}
Invoke-Az @("ad", "app", "update", "--id", $appId, "--set", "groupMembershipClaims=SecurityGroup")
$clientSecret = (& az ad app credential reset --id $appId --append --display-name "static-web-app" --query password --output tsv).Trim()

Invoke-Az @("staticwebapp", "appsettings", "set", "--name", $staticWebAppName, "--resource-group", $resourceGroupName, "--setting-names", "AZURE_CLIENT_ID=$appId", "AZURE_CLIENT_SECRET=$clientSecret", "ADMIN_GROUP_ID=$adminGroupId", "USER_GROUP_ID=$userGroupId", "STORAGE_ACCOUNT_NAME=$storageAccountName", "SESSIONS_CONTAINER_NAME=sessions", "--output", "none")

try {
    Set-Content -Path $configPath -Value ($originalConfig.Replace("__TENANT_ID__", $tenantId)) -NoNewline
    $deploymentToken = (& az staticwebapp secrets list --name $staticWebAppName --resource-group $resourceGroupName --query properties.apiKey --output tsv).Trim()
    Push-Location $projectRoot
    try {
        npx --yes @azure/static-web-apps-cli deploy --app-location app --api-location api --deployment-token $deploymentToken
    } finally {
        Pop-Location
    }
} finally {
    Set-Content -Path $configPath -Value $originalConfig -NoNewline
}

Write-Host "Deployment complete: https://$hostname"
Write-Host "Resource group: $resourceGroupName"
Write-Host "Add people to '$adminGroupName' or '$userGroupName' through your Entra tenant's approved membership process."
