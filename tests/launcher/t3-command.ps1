[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$entrypoint = Get-Content (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "docker\entrypoint.sh") -Raw

if ($entrypoint -notmatch 't3 serve --host 0\.0\.0\.0 --port') {
    throw "Expected docker/entrypoint.sh to invoke the installed t3 binary with the serve subcommand."
}

if ($entrypoint -notmatch 'export T3CODE_HOME=/state/data/t3;') {
    throw "Expected docker/entrypoint.sh to persist T3 runtime state under /state/data/t3."
}

if ($entrypoint -notmatch 't3 serve --host 0\.0\.0\.0 --port .* --auto-bootstrap-project-from-cwd') {
    throw "Expected docker/entrypoint.sh to auto-bootstrap the current /workspace as a T3 project on first launch."
}

if ($entrypoint -match 'npx --yes t3') {
    throw "docker/entrypoint.sh still relies on npx for T3 startup."
}

Write-Host "t3-command.ps1 passed"
