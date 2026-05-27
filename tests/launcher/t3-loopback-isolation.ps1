[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$psLauncher = Get-Content (Join-Path $repoRoot "bin\ai-sandbox.ps1") -Raw
$bashLauncher = Get-Content (Join-Path $repoRoot "bin\ai-sandbox") -Raw
$entrypoint = Get-Content (Join-Path $repoRoot "docker\entrypoint.sh") -Raw

foreach ($expected in @(
    'HostAddress',
    '127\.\$loopbackOctet2\.\$loopbackOctet3\.\$loopbackOctet4',
    'HostAddress = \$hostAddress'
)) {
    if ($psLauncher -notmatch $expected) {
        throw "Expected bin/ai-sandbox.ps1 to derive and store a workspace-specific loopback address."
    }
}

if ($psLauncher -match 'function Get-FreePort' -or $psLauncher -match 'Get-FreePort') {
    throw "Expected bin/ai-sandbox.ps1 to use fixed service ports without probing for alternates."
}

if ($psLauncher -match '--t3-port|--codenomad-port|--paseo-port') {
    throw "Expected bin/ai-sandbox.ps1 to remove per-service port override flags."
}

foreach ($expected in @(
    '-p", "\$\(\$Meta\.HostAddress\):\$\{DefaultT3ContainerPort\}:\$\{DefaultT3ContainerPort\}"',
    '-p", "\$\(\$Meta\.HostAddress\):\$\{DefaultCodeNomadContainerPort\}:\$\{DefaultCodeNomadContainerPort\}"',
    '-p", "\$\(\$Meta\.HostAddress\):\$\{DefaultPaseoContainerPort\}:\$\{DefaultPaseoContainerPort\}"',
    '-p", "\$\(\$Meta\.HostAddress\):\$\{DefaultAltHttpContainerPort\}:\$\{DefaultAltHttpContainerPort\}"',
    '-p", "\$\(\$Meta\.HostAddress\):\$\{DefaultAppContainerPort\}:\$\{DefaultAppContainerPort\}"'
)) {
    if ($psLauncher -notmatch $expected) {
        throw "Expected bin/ai-sandbox.ps1 to publish each service on the workspace-specific address with matching host/container ports."
    }
}

if ($psLauncher -notmatch 'AI_SANDBOX_T3_URL=http://\$\(\$Meta\.HostAddress\):\$DefaultT3ContainerPort') {
    throw "Expected bin/ai-sandbox.ps1 to pass the workspace-specific T3 URL into new containers."
}

if ($psLauncher -notmatch 'AI_SANDBOX_T3_URL=http://\$\(\$Meta\.HostAddress\):\$DefaultT3ContainerPort') {
    throw "Expected bin/ai-sandbox.ps1 to pass the workspace-specific T3 URL into docker exec."
}

foreach ($expected in @(
    'loopback_octet_2=\$\(\(64 \+ \(16#\$\{hash:0:2\} % 64\)\)\)',
    'host_address="127\.\$\{loopback_octet_2\}\.\$\{loopback_octet_3\}\.\$\{loopback_octet_4\}"',
    'HOST_ADDRESS="\$\{META\[9\]\}"'
)) {
    if ($bashLauncher -notmatch $expected) {
        throw "Expected bin/ai-sandbox to derive and store a workspace-specific loopback address."
    }
}

if ($bashLauncher -match 'free_port\(' -or $bashLauncher -match 'free_port "') {
    throw "Expected bin/ai-sandbox to use fixed service ports without probing for alternates."
}

if ($bashLauncher -match '--t3-port|--codenomad-port|--paseo-port') {
    throw "Expected bin/ai-sandbox to remove per-service port override flags."
}

foreach ($expected in @(
    '-p "\$\{HOST_ADDRESS\}:\$\{DEFAULT_T3_CONTAINER_PORT\}:\$\{DEFAULT_T3_CONTAINER_PORT\}"',
    '-p "\$\{HOST_ADDRESS\}:\$\{DEFAULT_CODENOMAD_CONTAINER_PORT\}:\$\{DEFAULT_CODENOMAD_CONTAINER_PORT\}"',
    '-p "\$\{HOST_ADDRESS\}:\$\{DEFAULT_PASEO_CONTAINER_PORT\}:\$\{DEFAULT_PASEO_CONTAINER_PORT\}"',
    '-p "\$\{HOST_ADDRESS\}:\$\{DEFAULT_ALT_HTTP_CONTAINER_PORT\}:\$\{DEFAULT_ALT_HTTP_CONTAINER_PORT\}"',
    '-p "\$\{HOST_ADDRESS\}:\$\{DEFAULT_APP_CONTAINER_PORT\}:\$\{DEFAULT_APP_CONTAINER_PORT\}"'
)) {
    if ($bashLauncher -notmatch $expected) {
        throw "Expected bin/ai-sandbox to publish each service on the workspace-specific address with matching host/container ports."
    }
}

if ($bashLauncher -notmatch 'AI_SANDBOX_T3_URL=http://\$\{HOST_ADDRESS\}:\$\{DEFAULT_T3_CONTAINER_PORT\}') {
    throw "Expected bin/ai-sandbox to pass the workspace-specific T3 URL into containers and docker exec."
}

if ($entrypoint -notmatch 'export T3CODE_HOME=/state/data/t3;') {
    throw "Expected docker/entrypoint.sh to persist T3 runtime state via T3CODE_HOME."
}

if ($entrypoint -notmatch 't3 start --no-browser --host 0\.0\.0\.0 --port .* --base-dir /state/data/t3 --auto-bootstrap-project-from-cwd') {
    throw "Expected docker/entrypoint.sh to pass --base-dir /state/data/t3 to T3."
}

if ($entrypoint -match '--state-dir') {
    throw "docker/entrypoint.sh passes --state-dir, but this T3 CLI exposes --base-dir instead."
}

if ($entrypoint -notmatch 'Connection string: \$AI_SANDBOX_T3_URL' -or
    $entrypoint -notmatch 'Pairing URL: \$AI_SANDBOX_T3_URL/pair#token=\$token' -or
    $entrypoint -notmatch 'pairingUrl: \$AI_SANDBOX_T3_URL/pair#token=\$token') {
    throw "Expected docker/entrypoint.sh to keep rewriting T3 output with AI_SANDBOX_T3_URL."
}

Write-Host "t3-loopback-isolation.ps1 passed"
