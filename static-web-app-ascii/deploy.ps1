[CmdletBinding()]
param(
    [ValidatePattern('^[a-z0-9]{2,10}$')] [string] $BaseName = "typecast",
    [ValidateSet("dev", "test", "prod")] [string] $Environment = "dev",
    [string] $Location = "eastus2",
    [ValidatePattern('^[a-z0-9]{2,4}$')] [string] $LocationCode = "eus2",
    [string] $SubscriptionId,
    [string] $ParametersFile = (Join-Path $PSScriptRoot "infra/parameters.dev.bicepparam")
)

$ErrorActionPreference = "Stop"

foreach ($command in "az", "node", "npx") {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
        throw "Required command not found: $command"
    }
}

& (Join-Path $PSScriptRoot "infra/deploy.ps1") @PSBoundParameters
if ($LASTEXITCODE -ne 0) { throw "Deployment failed." }
