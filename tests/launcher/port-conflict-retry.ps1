[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$bashLauncher = Get-Content (Join-Path $repoRoot "bin\ai-sandbox") -Raw
$psLauncher = Get-Content (Join-Path $repoRoot "bin\ai-sandbox.ps1") -Raw

if ($bashLauncher.Contains("port is already allocated' -and -not $FORCE_RECREATE")) {
    throw "Expected bin/ai-sandbox to retry on port conflicts even during --rebuild."
}

if ($psLauncher.Contains("port is already allocated' -and -not $ForceRecreate")) {
    throw "Expected bin/ai-sandbox.ps1 to retry on port conflicts even during --rebuild."
}

if ($psLauncher -notmatch 'ports are not available') {
    throw "Expected bin/ai-sandbox.ps1 to retry on Docker's Windows port conflict message."
}

if ($psLauncher -notmatch 'IPAddress\]::Parse\("127\.0\.0\.1"\)') {
    throw "Expected bin/ai-sandbox.ps1 to probe the same loopback address used by Docker port publishing."
}

if ($psLauncher -notmatch '\$attemptHttpPort = Get-FreePort -StartPort \(\$attemptHttpPort \+ 1\)') {
    throw "Expected bin/ai-sandbox.ps1 to retry container port 80 with the next free host port."
}

if ($psLauncher -notmatch '\$attemptAltHttpPort = Get-FreePort -StartPort \(\$attemptAltHttpPort \+ 1\)') {
    throw "Expected bin/ai-sandbox.ps1 to retry container port 8080 with the next free host port."
}

if ($psLauncher -notmatch '\$attemptAppPort = Get-FreePort -StartPort \(\$attemptAppPort \+ 1\)') {
    throw "Expected bin/ai-sandbox.ps1 to retry container port 3000 with the next free host port."
}

if ($bashLauncher -notmatch 'attempt_http_host_port="\$\(free_port "\$\(\(attempt_http_host_port \+ 1\)\)"\)"') {
    throw "Expected bin/ai-sandbox to retry container port 80 with the next free host port."
}

if ($bashLauncher -notmatch 'attempt_alt_http_host_port="\$\(free_port "\$\(\(attempt_alt_http_host_port \+ 1\)\)"\)"') {
    throw "Expected bin/ai-sandbox to retry container port 8080 with the next free host port."
}

if ($bashLauncher -notmatch 'attempt_app_host_port="\$\(free_port "\$\(\(attempt_app_host_port \+ 1\)\)"\)"') {
    throw "Expected bin/ai-sandbox to retry container port 3000 with the next free host port."
}

Write-Host "port-conflict-retry.ps1 passed"
