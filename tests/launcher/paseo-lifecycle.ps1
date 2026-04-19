[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$entrypoint = Get-Content (Join-Path $repoRoot "docker\entrypoint.sh") -Raw

if ($entrypoint -notmatch 'cleanup_paseo_daemon') {
    throw "Expected docker/entrypoint.sh to define cleanup_paseo_daemon."
}

if ($entrypoint -notmatch 'paseo daemon stop --home /state/data/paseo --force') {
    throw "Expected cleanup to force-stop the Paseo daemon."
}

if ($entrypoint -notmatch 'rm -f /state/data/paseo/paseo\.pid') {
    throw "Expected cleanup to remove stale Paseo PID files."
}

if ($entrypoint -notmatch 'trap cleanup_paseo_daemon INT TERM EXIT') {
    throw "Expected run_paseo to trap INT, TERM, and EXIT for cleanup."
}

if ($entrypoint -notmatch 'paseo_pid=\\\$!') {
    throw "Expected run_paseo to launch Paseo as a background child so signal traps can run."
}

if ($entrypoint -notmatch 'wait .*paseo_pid') {
    throw "Expected run_paseo to wait on the background Paseo child."
}

if ($entrypoint -notmatch 'cleanup_paseo_daemon; export PASEO_HOME=/state/data/paseo') {
    throw "Expected run_paseo to clean up stale Paseo state before starting."
}

Write-Host "paseo-lifecycle.ps1 passed"
