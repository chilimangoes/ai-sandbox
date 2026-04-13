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

Write-Host "workspace-meta.ps1 passed"
