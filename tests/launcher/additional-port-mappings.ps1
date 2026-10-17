[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$psLauncher = Get-Content (Join-Path $repoRoot "bin\ai-sandbox.ps1") -Raw
$bashLauncher = Get-Content (Join-Path $repoRoot "bin\ai-sandbox") -Raw
$entrypoint = Get-Content (Join-Path $repoRoot "docker\entrypoint.sh") -Raw


if ($psLauncher -notmatch '\$DefaultAltHttpContainerPort = 8080') {
    throw "Expected bin/ai-sandbox.ps1 to define DefaultAltHttpContainerPort."
}

if ($psLauncher -notmatch '\$DefaultAppContainerPort = 3000') {
    throw "Expected bin/ai-sandbox.ps1 to define DefaultAppContainerPort."
}

if ($bashLauncher -notmatch 'DEFAULT_ALT_HTTP_CONTAINER_PORT=8080') {
    throw "Expected bin/ai-sandbox to define DEFAULT_ALT_HTTP_CONTAINER_PORT."
}

if ($bashLauncher -notmatch 'DEFAULT_APP_CONTAINER_PORT=3000') {
    throw "Expected bin/ai-sandbox to define DEFAULT_APP_CONTAINER_PORT."
}

if ($psLauncher -match 'Default(Http|AltHttp|App)HostPort') {
    throw "Expected bin/ai-sandbox.ps1 to use matching host/container ports instead of separate web host port defaults."
}

if ($bashLauncher -match 'DEFAULT_(HTTP|ALT_HTTP|APP)_HOST_PORT') {
    throw "Expected bin/ai-sandbox to use matching host/container ports instead of separate web host port defaults."
}

if ($psLauncher -match 'DefaultHttpContainerPort') {
    throw "Expected bin/ai-sandbox.ps1 to omit container port 80 from default publishing."
}

foreach ($service in @('ALT_HTTP', 'APP')) {
    if ($psLauncher -notmatch "Name = '$service'; Port = ") { throw "Expected the $service endpoint definition." }
}
if ($psLauncher -notmatch '\$engineArgs \+= @\(''-p'', "\$\(\$endpoint.HostAddress\):\$\(\$endpoint.HostPort\):\$\(\$endpoint.ContainerPort\)"\)') {
    throw 'Expected separate host and container ports in native publish arguments.'
}

if ($bashLauncher -match 'DEFAULT_HTTP_CONTAINER_PORT') {
    throw "Expected bin/ai-sandbox to omit container port 80 from default publishing."
}

if ($bashLauncher -notmatch '-p "\$\{HOST_ADDRESS\}:\$\{DEFAULT_ALT_HTTP_CONTAINER_PORT\}:\$\{DEFAULT_ALT_HTTP_CONTAINER_PORT\}"') {
    throw "Expected bin/ai-sandbox to publish host port for container port 8080."
}

if ($bashLauncher -notmatch '-p "\$\{HOST_ADDRESS\}:\$\{DEFAULT_APP_CONTAINER_PORT\}:\$\{DEFAULT_APP_CONTAINER_PORT\}"') {
    throw "Expected bin/ai-sandbox to publish host port for container port 3000."
}

if ($psLauncher -match 'AI_SANDBOX_HTTP_URL') {
    throw "Expected bin/ai-sandbox.ps1 not to advertise unpublished host port 80."
}

if ($psLauncher -notmatch 'AI_SANDBOX_\$\(\$service.Name\)_\$\(\$service.Url\)=\$value' -or
    $psLauncher -notmatch 'Get-EndpointEnvironment -Meta \$Meta -Endpoints \$Meta.Endpoints') {
    throw 'Expected host-visible URLs from inspected endpoints at creation and exec.'
}

if ($bashLauncher -match 'AI_SANDBOX_HTTP_URL') {
    throw "Expected bin/ai-sandbox not to advertise unpublished host port 80."
}

if ($bashLauncher -notmatch 'AI_SANDBOX_ALT_HTTP_URL=http://\$\{HOST_ADDRESS\}:\$\{DEFAULT_ALT_HTTP_CONTAINER_PORT\}') {
    throw "Expected bin/ai-sandbox to pass AI_SANDBOX_ALT_HTTP_URL into the container."
}

if ($bashLauncher -notmatch 'AI_SANDBOX_APP_URL=http://\$\{HOST_ADDRESS\}:\$\{DEFAULT_APP_CONTAINER_PORT\}') {
    throw "Expected bin/ai-sandbox to pass AI_SANDBOX_APP_URL into the container."
}

if ($entrypoint -notmatch 'HOST_HTTP_URL="\$\{AI_SANDBOX_HTTP_URL:-\}"') {
    throw "Expected docker/entrypoint.sh to leave the port 80 host URL blank unless explicitly supplied."
}

if ($entrypoint -notmatch 'HOST_ALT_HTTP_URL="\$\{AI_SANDBOX_ALT_HTTP_URL:-http://127\.0\.0\.1:\$\{AI_SANDBOX_HOST_ALT_HTTP_PORT:-\$CONTAINER_ALT_HTTP_PORT\}\}"') {
    throw "Expected docker/entrypoint.sh to derive a host-visible URL for container port 8080."
}

if ($entrypoint -notmatch 'HOST_APP_URL="\$\{AI_SANDBOX_APP_URL:-http://127\.0\.0\.1:\$\{AI_SANDBOX_HOST_APP_PORT:-\$CONTAINER_APP_PORT\}\}"') {
    throw "Expected docker/entrypoint.sh to derive a host-visible URL for container port 3000."
}

Write-Host "additional-port-mappings.ps1 passed"
