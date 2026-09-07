[CmdletBinding()]
param(
    [Parameter(Mandatory)] [ValidatePattern('^[a-z0-9]{2,10}$')] [string] $BaseName,
    [ValidateSet("dev", "test", "prod")] [string] $Environment = "dev",
    [string] $Location = "eastus",
    [ValidatePattern('^[a-z0-9]{2,4}$')] [string] $LocationCode = "eus",
    [string] $SubscriptionId
)

$ErrorActionPreference = "Stop"

foreach ($command in "az", "node", "npx") {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
        throw "Required command not found: $command"
    }
}

& (Join-Path $PSScriptRoot "infra/deploy.ps1") @PSBoundParameters
if ($LASTEXITCODE -ne 0) { throw "Deployment failed." }
