[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$psLauncher = Get-Content (Join-Path $repoRoot "bin\ai-sandbox.ps1") -Raw
$bashLauncher = Get-Content (Join-Path $repoRoot "bin\ai-sandbox") -Raw
$entrypoint = Get-Content (Join-Path $repoRoot "docker\entrypoint.sh") -Raw

if ($psLauncher -notmatch '\$DefaultHttpContainerPort = 80') {
    throw "Expected bin/ai-sandbox.ps1 to define DefaultHttpContainerPort."
}

if ($psLauncher -notmatch '\$DefaultHttpHostPort = 58080') {
    throw "Expected bin/ai-sandbox.ps1 to define DefaultHttpHostPort."
}

if ($psLauncher -notmatch '\$DefaultAltHttpContainerPort = 8080') {
    throw "Expected bin/ai-sandbox.ps1 to define DefaultAltHttpContainerPort."
}

if ($psLauncher -notmatch '\$DefaultAltHttpHostPort = 58880') {
    throw "Expected bin/ai-sandbox.ps1 to define DefaultAltHttpHostPort."
}

if ($bashLauncher -notmatch 'DEFAULT_HTTP_CONTAINER_PORT=80') {
    throw "Expected bin/ai-sandbox to define DEFAULT_HTTP_CONTAINER_PORT."
}

if ($bashLauncher -notmatch 'DEFAULT_HTTP_HOST_PORT=58080') {
    throw "Expected bin/ai-sandbox to define DEFAULT_HTTP_HOST_PORT."
}

if ($bashLauncher -notmatch 'DEFAULT_ALT_HTTP_CONTAINER_PORT=8080') {
    throw "Expected bin/ai-sandbox to define DEFAULT_ALT_HTTP_CONTAINER_PORT."
}

if ($bashLauncher -notmatch 'DEFAULT_ALT_HTTP_HOST_PORT=58880') {
    throw "Expected bin/ai-sandbox to define DEFAULT_ALT_HTTP_HOST_PORT."
}

if ($psLauncher -notmatch '-p", "127\.0\.0\.1:\$\{?HttpHostPort\}?:\$\{?DefaultHttpContainerPort\}?"') {
    throw "Expected bin/ai-sandbox.ps1 to publish host port for container port 80."
}

if ($psLauncher -notmatch '-p", "127\.0\.0\.1:\$\{?AltHttpHostPort\}?:\$\{?DefaultAltHttpContainerPort\}?"') {
    throw "Expected bin/ai-sandbox.ps1 to publish host port for container port 8080."
}

if ($bashLauncher -notmatch '-p "127\.0\.0\.1:\$\{attempt_http_host_port\}:\$\{DEFAULT_HTTP_CONTAINER_PORT\}"') {
    throw "Expected bin/ai-sandbox to publish host port for container port 80."
}

if ($bashLauncher -notmatch '-p "127\.0\.0\.1:\$\{attempt_alt_http_host_port\}:\$\{DEFAULT_ALT_HTTP_CONTAINER_PORT\}"') {
    throw "Expected bin/ai-sandbox to publish host port for container port 8080."
}

if ($psLauncher -notmatch 'Get-ExistingHostPort -Name \$Meta\.Container -ContainerPort \$DefaultHttpContainerPort') {
    throw "Expected bin/ai-sandbox.ps1 to resolve the existing host port for container port 80."
}

if ($psLauncher -notmatch 'Get-ExistingHostPort -Name \$Meta\.Container -ContainerPort \$DefaultAltHttpContainerPort') {
    throw "Expected bin/ai-sandbox.ps1 to resolve the existing host port for container port 8080."
}

if ($bashLauncher -notmatch 'existing_host_port "\$CONTAINER_NAME" "\$DEFAULT_HTTP_CONTAINER_PORT"') {
    throw "Expected bin/ai-sandbox to resolve the existing host port for container port 80."
}

if ($bashLauncher -notmatch 'existing_host_port "\$CONTAINER_NAME" "\$DEFAULT_ALT_HTTP_CONTAINER_PORT"') {
    throw "Expected bin/ai-sandbox to resolve the existing host port for container port 8080."
}

if ($psLauncher -notmatch 'AI_SANDBOX_HTTP_URL=http://127\.0\.0\.1:\$') {
    throw "Expected bin/ai-sandbox.ps1 to pass AI_SANDBOX_HTTP_URL into the container."
}

if ($psLauncher -notmatch 'AI_SANDBOX_ALT_HTTP_URL=http://127\.0\.0\.1:\$') {
    throw "Expected bin/ai-sandbox.ps1 to pass AI_SANDBOX_ALT_HTTP_URL into the container."
}

if ($bashLauncher -notmatch 'AI_SANDBOX_HTTP_URL=http://127\.0\.0\.1:\$\{attempt_http_host_port\}') {
    throw "Expected bin/ai-sandbox to pass AI_SANDBOX_HTTP_URL into the container."
}

if ($bashLauncher -notmatch 'AI_SANDBOX_ALT_HTTP_URL=http://127\.0\.0\.1:\$\{attempt_alt_http_host_port\}') {
    throw "Expected bin/ai-sandbox to pass AI_SANDBOX_ALT_HTTP_URL into the container."
}

if ($entrypoint -notmatch 'HOST_HTTP_URL="\$\{AI_SANDBOX_HTTP_URL:-http://127\.0\.0\.1:\$\{AI_SANDBOX_HOST_HTTP_PORT:-\$CONTAINER_HTTP_PORT\}\}"') {
    throw "Expected docker/entrypoint.sh to derive a host-visible URL for container port 80."
}

if ($entrypoint -notmatch 'HOST_ALT_HTTP_URL="\$\{AI_SANDBOX_ALT_HTTP_URL:-http://127\.0\.0\.1:\$\{AI_SANDBOX_HOST_ALT_HTTP_PORT:-\$CONTAINER_ALT_HTTP_PORT\}\}"') {
    throw "Expected docker/entrypoint.sh to derive a host-visible URL for container port 8080."
}

Write-Host "additional-port-mappings.ps1 passed"
