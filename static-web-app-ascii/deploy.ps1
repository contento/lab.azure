[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $ResourceGroupName,
    [Parameter(Mandatory)] [string] $StaticWebAppName,
    [Parameter(Mandatory)] [string] $StorageAccountName,
    [string] $Location = "eastus",
    [string] $AdminGroupName = "$StaticWebAppName-Admins",
    [string] $UserGroupName = "$StaticWebAppName-Users"
)

$ErrorActionPreference = "Stop"

foreach ($command in "az", "node", "npx") {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
        throw "Required command not found: $command"
    }
}

& (Join-Path $PSScriptRoot "infra/deploy.ps1") @PSBoundParameters
if ($LASTEXITCODE -ne 0) { throw "Deployment failed." }
