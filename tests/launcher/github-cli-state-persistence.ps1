[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$image = if ($env:AI_SANDBOX_TEST_IMAGE) { $env:AI_SANDBOX_TEST_IMAGE } else { "ai-sandbox:latest" }
$volume = "ai-sandbox-github-cli-$([guid]::NewGuid().ToString('N'))"

function Invoke-Docker {
    param([string[]]$DockerArgs)
    & docker @DockerArgs
    if ($LASTEXITCODE -ne 0) {
        throw "GitHub CLI persistence check failed (exit $LASTEXITCODE)."
    }
}

$seed = @'
set -euo pipefail
gh --version
test "$GH_CONFIG_DIR" = /state/data/github-cli
test -d "$GH_CONFIG_DIR"
gh config set git_protocol ssh
test -s /state/data/github-cli/config.yml
# A fictional token exercises local credential lookup.
printf 'github.com:\n    oauth_token: persistence-marker\n    user: sandbox-test\n' > "$GH_CONFIG_DIR/hosts.yml"
/opt/ai-sandbox/bootstrap/init-state.sh
test "$(gh auth token --hostname github.com)" = persistence-marker
'@

$verify = @'
set -euo pipefail
test "$(gh config get git_protocol)" = ssh
test "$(gh auth token --hostname github.com)" = persistence-marker
runuser -u sandbox -- gh config get git_protocol | grep -qx ssh
runuser -u sandbox -- gh auth token --hostname github.com | grep -qx persistence-marker
/opt/ai-sandbox/bootstrap/sync-configs.sh --reset
test "$(gh auth token --hostname github.com)" = persistence-marker
'@

Invoke-Docker @("volume", "create", $volume) | Out-Null
try {
    foreach ($script in @($seed, $verify)) {
        $script | & docker run --rm -i -v "${volume}:/state/data" $image bash -c "tr -d '\r' | bash"
        if ($LASTEXITCODE -ne 0) {
            throw "GitHub CLI persistence check failed (exit $LASTEXITCODE)."
        }
    }
}
finally {
    Invoke-Docker @("volume", "rm", $volume) | Out-Null
}

Write-Host "github-cli-state-persistence.ps1 passed"
