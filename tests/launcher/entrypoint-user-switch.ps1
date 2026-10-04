[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$entrypoint = Get-Content (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "docker\entrypoint.sh") -Raw

if ($entrypoint -notmatch 'run_as_root\(\)') {
    throw "Expected docker/entrypoint.sh to support root-dispatched commands."
}

if ($entrypoint -notmatch 'run_as_sandbox\(\)') {
    throw "Expected docker/entrypoint.sh to support sandbox-dispatched commands."
}

if ($entrypoint -notmatch 'runuser\s+-u\s+sandbox\s+--') {
    throw "Expected docker/entrypoint.sh to drop root privileges for sandbox-dispatched commands."
}

if ($entrypoint -notmatch 'export HOME=/home/sandbox') {
    throw "Expected root-dispatched commands to keep using the persisted sandbox home directory."
}

if ($entrypoint -notmatch '(?ms)if \[\[ "\$\(id -u\)" == "0" && "\$\{AI_SANDBOX_INITIALIZED:-\}" != "1" \]\]; then\s+ensure_runtime_user\s+/opt/ai-sandbox/bootstrap/init-state\.sh\s+chown -R sandbox:sandbox /state /home/sandbox') {
    throw "Expected root-only container initialization before command dispatch."
}

if ($entrypoint -notmatch '(?ms)claude\).*?run_argv_as_sandbox /opt/ai-sandbox/claude-wrapper\.sh "\$@"') {
    throw "Expected Claude to run as the mapped sandbox user."
}

if ($entrypoint -notmatch 'git config --system --add safe\.directory ''\*''') {
    throw "Expected docker/entrypoint.sh to trust bind-mounted workspace repositories inside the sandbox."
}

Write-Host "entrypoint-user-switch.ps1 passed"
