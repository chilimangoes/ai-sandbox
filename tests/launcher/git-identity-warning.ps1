[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$entrypoint = Get-Content (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "docker\entrypoint.sh") -Raw

if ($entrypoint -notmatch 'warn_missing_git_identity\(\)') {
    throw "Expected docker/entrypoint.sh to define the Git identity warning helper."
}

if ($entrypoint -notmatch 'git -C "\$WORKSPACE_PATH" rev-parse --is-inside-work-tree') {
    throw "Expected the Git identity warning to check the mapped workspace."
}

if ($entrypoint -notmatch 'git -C "\$WORKSPACE_PATH" config --get user\.name' -or
    $entrypoint -notmatch 'git -C "\$WORKSPACE_PATH" config --get user\.email') {
    throw "Expected the Git identity warning to read user.name and user.email."
}

if ($entrypoint -notmatch [regex]::Escape('The current git config has no user.name and user.email values. You can run the following commands to configure them. (Ommit the --global flags if you want to store the values in the workspace folder)')) {
    throw "Expected the Git identity warning to include the requested guidance."
}

if ($entrypoint -notmatch "\\033\[33m") {
    throw "Expected the Git identity warning to use amber terminal text."
}

if ($entrypoint -notmatch '(?s)shell\).*?print_banner\s+warn_missing_git_identity\s+run_as_root') {
    throw "Expected the Git identity warning to print after the shell banner."
}

Write-Host "git-identity-warning.ps1 passed"
