[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$image = if ($env:AI_SANDBOX_TEST_IMAGE) { $env:AI_SANDBOX_TEST_IMAGE } else { "ai-sandbox:latest" }
$volume = "ai-sandbox-cursor-auth-$([guid]::NewGuid().ToString('N'))"

docker volume create $volume | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "Failed to create temporary Cursor auth volume."
}

try {
    docker run --rm -v "${volume}:/state" $image cursor --version | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to bootstrap Cursor state."
    }

    docker run --rm -v "${volume}:/state" --entrypoint bash $image -lc `
        "printf '%s' credential-marker > /state/auth/cursor/auth.json"
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to seed the Cursor credential marker."
    }

    docker run --rm -v "${volume}:/state" $image bash -lc `
        "test -L /home/sandbox/.config/cursor && grep -qx credential-marker /home/sandbox/.config/cursor/auth.json"
    if ($LASTEXITCODE -ne 0) {
        throw "Cursor credentials did not survive container recreation."
    }
}
finally {
    docker volume rm $volume | Out-Null
}

Write-Host "cursor-auth-persistence.ps1 passed"
