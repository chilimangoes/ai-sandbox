[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$powerShellLauncher = Get-Content (Join-Path $repoRoot "bin\ai-sandbox.ps1") -Raw
$bashLauncher = Get-Content (Join-Path $repoRoot "bin\ai-sandbox") -Raw

if ($powerShellLauncher -notmatch '\$nonInteractiveCommands\s*=\s*@\("t3",\s*"codenomad",\s*"paseo"\)') {
    throw "Expected PowerShell launcher to classify t3, codenomad, and paseo as non-interactive service commands."
}

if ($powerShellLauncher -notmatch 'Exec-InContainer -Meta \$meta -CommandArgs \$invokeCommand -Interactive:\(\$command -notin \$nonInteractiveCommands\)') {
    throw "Expected PowerShell launcher to avoid docker exec -it for service commands."
}

if ($bashLauncher -notmatch 't3\|codenomad\|paseo\)') {
    throw "Expected Bash launcher to route t3, codenomad, and paseo through a non-interactive docker exec path."
}

if ($bashLauncher -notmatch 'exec_in_container false "\$COMMAND"') {
    throw "Expected Bash launcher to avoid docker exec -it for service commands."
}

Write-Host "service-command-noninteractive.ps1 passed"
