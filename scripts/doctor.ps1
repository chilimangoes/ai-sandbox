[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

try {
    $dockerVersion = docker version --format '{{.Server.Version}}' 2>$null
    if (-not $dockerVersion) {
        $dockerVersion = "daemon unavailable"
    }
} catch {
    $dockerVersion = "daemon unavailable"
}

Write-Host ("docker: " + $dockerVersion)
Write-Host ("pwsh: " + $PSVersionTable.PSVersion.ToString())
