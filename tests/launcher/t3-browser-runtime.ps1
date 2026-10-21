[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$profilePath = Join-Path $repoRoot "docker/browser-seccomp.json"
$script = @'
set -euo pipefail
mapfile -t packages < <(python3 - <<'PY'
from pathlib import Path
source = Path('/repo/Dockerfile').read_text()
block = source.split('apt-get install -y --no-install-recommends', 1)[1].split('&&', 1)[0]
print('\n'.join(block.replace('\\', '').split()))
PY
)
apt-get update -qq
apt-get install -y -qq --no-install-recommends "${packages[@]}"
# Use the same Chrome release as T3 0.1.1.
curl -fsSL --max-time 90 https://storage.googleapis.com/chrome-for-testing-public/154.0.8037.92/linux64/chrome-headless-shell-linux64.zip -o /tmp/chrome.zip
unzip -q /tmp/chrome.zip -d /tmp/browser
runuser -u sandbox -- bash /repo/tests/launcher/t3-browser-runtime.sh /tmp/browser/chrome-headless-shell-linux64/chrome-headless-shell
'@

$script | & docker run --rm -i --security-opt "seccomp=$profilePath" `
    --mount "type=bind,source=$repoRoot,target=/repo,readonly" `
    --entrypoint bash ai-sandbox:latest -c "tr -d '\r' | bash"
if ($LASTEXITCODE -ne 0) { throw "T3 browser runtime check failed (exit $LASTEXITCODE)." }

Write-Host "t3-browser-runtime.ps1 passed"
