[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$workspace = "C:\Users\Test User\Projects\Example Repo"
$fullPath = [System.IO.Path]::GetFullPath($workspace)
$leaf = Split-Path -Leaf $fullPath
$slug = ($leaf.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
if ($slug -ne "example-repo") {
    throw "Unexpected slug: $slug"
}

$containerWorkspacePath = "/workspace/$slug"
if ($containerWorkspacePath -ne "/workspace/example-repo") {
    throw "Expected container workspace path to include the slug."
}

$sha = [System.Security.Cryptography.SHA256]::Create()
try {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($fullPath.ToLowerInvariant())
    $hash = ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString("x2") }) -join ""
} finally {
    $sha.Dispose()
}

if ($hash.Substring(0, 12).Length -ne 12) {
    throw "Expected 12 character hash prefix."
}

$loopbackOctet2 = 64 + ([Convert]::ToInt32($hash.Substring(0, 2), 16) % 64)
$loopbackOctet3 = [Convert]::ToInt32($hash.Substring(2, 2), 16)
$loopbackOctet4 = 1 + ([Convert]::ToInt32($hash.Substring(4, 2), 16) % 254)
$hostAddress = "127.$loopbackOctet2.$loopbackOctet3.$loopbackOctet4"
if ($hostAddress -notmatch '^127\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.\d{1,3}\.([1-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-4])$') {
    throw "Expected workspace hash to derive a host-specific 127.x.y.z T3 loopback address."
}

Write-Host "workspace-meta.ps1 passed"
