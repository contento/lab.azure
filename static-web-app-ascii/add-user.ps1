[CmdletBinding()]
param(
    [string] $User,
    [ValidateSet("admin", "user")] [string] $Role = "admin",
    [ValidatePattern('^[a-z0-9]{2,10}$')] [string] $BaseName = "asciitype",
    [ValidateSet("dev", "test", "prod")] [string] $Environment = "dev",
    [ValidatePattern('^[a-z0-9]{2,4}$')] [string] $LocationCode = "eus2",
    [string] $SubscriptionId
)

$ErrorActionPreference = "Stop"

if ($SubscriptionId) { & az account set --subscription $SubscriptionId }

Write-Host "==> [1/2] Resolving target user in Entra ID..." -ForegroundColor Cyan
if (-not $User) {
    $userInfoRaw = (& az ad signed-in-user show --query '{id:id, upn:userPrincipalName}' --output json 2>$null)
    if (-not $userInfoRaw) { throw "Could not resolve active signed-in user from Azure CLI. Please specify -User <email-or-id>." }
    $userInfo = $userInfoRaw | ConvertFrom-Json
    $userId = $userInfo.id
    $userDisplayName = $userInfo.upn
} elseif ($User -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
    $userId = $User
    $userDisplayName = $User
} else {
    $userObjRaw = (& az ad user show --id $User --query '{id:id, upn:userPrincipalName}' --output json 2>$null)
    if (-not $userObjRaw) { throw "Could not find Entra ID user '$User'." }
    $userObj = $userObjRaw | ConvertFrom-Json
    $userId = $userObj.id
    $userDisplayName = $userObj.upn
}
Write-Host "    Target User: $userDisplayName ($userId)" -ForegroundColor Gray

Write-Host "==> [2/2] Assigning role '$Role' via Entra ID security groups..." -ForegroundColor Cyan
$namePrefix = "$BaseName-$Environment-$LocationCode"
$adminGroupName = "grp-$namePrefix-admins"
$userGroupName = "grp-$namePrefix-users"

$adminGroupId = (& az ad group show --group $adminGroupName --query id --output tsv 2>$null)
$userGroupId = (& az ad group show --group $userGroupName --query id --output tsv 2>$null)

if (-not $userGroupId) {
    throw "Security group '$userGroupName' not found. Ensure infrastructure has been deployed first."
}

function Add-Member([string] $GroupId, [string] $GroupName, [string] $MemberId, [string] $MemberName) {
    $isMember = (& az ad group member check --group $GroupId --member-id $MemberId --query value --output tsv 2>$null)
    if ($isMember -eq "true") {
        Write-Host "    User '$MemberName' is already a member of '$GroupName'." -ForegroundColor Gray
    } else {
        & az ad group member add --group $GroupId --member-id $MemberId
        if ($LASTEXITCODE -eq 0) {
            Write-Host "    ✔ Added '$MemberName' to '$GroupName'." -ForegroundColor Green
        } else {
            throw "Failed to add '$MemberName' to '$GroupName'."
        }
    }
}

if ($Role -eq "admin") {
    if (-not $adminGroupId) { throw "Security group '$adminGroupName' not found." }
    Add-Member -GroupId $adminGroupId -GroupName $adminGroupName -MemberId $userId -MemberName $userDisplayName
    Add-Member -GroupId $userGroupId -GroupName $userGroupName -MemberId $userId -MemberName $userDisplayName
} else {
    Add-Member -GroupId $userGroupId -GroupName $userGroupName -MemberId $userId -MemberName $userDisplayName
}

Write-Host "`n✔ Role assignment complete for $userDisplayName." -ForegroundColor Green
Write-Host "  Note: Group claim updates may take a minute and require signing out and in again on the app." -ForegroundColor Yellow
