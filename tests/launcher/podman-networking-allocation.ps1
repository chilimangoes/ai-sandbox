$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$probeSource = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'podman-networking.ps1') -Raw
$launcherSource = Get-Content -LiteralPath (Join-Path $repoRoot 'bin/ai-sandbox.ps1') -Raw
foreach ($name in @('Get-WorkspaceHash', 'Get-LoopbackAddress', 'Get-BlockPorts')) {
    $definition = [regex]::Match($probeSource, "(?ms)^function $name \{.*?^\}")
    if (-not $definition.Success) { throw "Missing probe function $name." }
    Invoke-Expression $definition.Value
}
$definition = [regex]::Match($launcherSource, '(?ms)^function Get-WorkspaceMeta \{.*?^\}')
Invoke-Expression $definition.Value
$workspace = Join-Path $repoRoot 'network allocation with spaces'
$hash = Get-WorkspaceHash -Path $workspace
$meta = Get-WorkspaceMeta -WorkspacePath $workspace
if ($hash.Substring(0, 12) -cne $meta.Hash -or (Get-LoopbackAddress -Hash $hash) -cne $meta.HostAddress) { throw 'Probe workspace hashing differs from the Windows launcher.' }
if ((Get-WorkspaceHash -Path $workspace.ToUpperInvariant()) -cne $hash) { throw 'Workspace hashing must ignore Windows path case.' }
$seenPorts = New-Object 'System.Collections.Generic.HashSet[int]'
for ($attempt = 0; $attempt -lt 6000; $attempt++) {
    $block = @(Get-BlockPorts -Hash $hash -Attempt $attempt)
    if ($block.Count -ne 5 -or $block[0] -lt 20000 -or $block[4] -gt 49999) { throw 'Port block is outside the documented range.' }
    for ($index = 0; $index -lt 5; $index++) {
        if ($block[$index] -ne $block[0] + $index -or -not $seenPorts.Add($block[$index])) { throw 'Port blocks overlap or are not consecutive.' }
    }
}
if ($seenPorts.Count -ne 30000) { throw 'Port blocks do not cover the complete documented range.' }
if ((@(Get-BlockPorts -Hash $hash -Attempt 6000) -join ',') -cne (@(Get-BlockPorts -Hash $hash -Attempt 0) -join ',')) { throw 'Port block retries do not wrap.' }
if ((@(Get-BlockPorts -Hash ('ffffffff' + '0' * 56) -Attempt 0))[0] -ne 20000 + 5 * ([uint32]::MaxValue % 6000)) { throw 'First eight hex digits must be unsigned.' }

# A removed container's forwarding socket may still occupy its previous block.
# Recreation must advance in the same deterministic order and inspect the result.
$definition = [regex]::Match($probeSource, '(?ms)^function Start-AllocatedProbe \{.*?^\}')
if (-not $definition.Success) { throw 'Missing allocation implementation.' }
Invoke-Expression $definition.Value
$script:allocationExpectedPorts = @(Get-BlockPorts -Hash $hash -Attempt 2)
$script:allocationMappedPorts = @()
function Test-BlockAvailable {
    param([int[]]$HostPorts)
    return $HostPorts[0] -eq $script:allocationExpectedPorts[0]
}
function Start-Probe {
    param([string]$Name, [string]$Address, [int[]]$HostPorts)
    $script:allocationMappedPorts = $HostPorts
    return [pscustomobject]@{ ExitCode = 0; Evidence = 'shim-start' }
}
function Get-Mappings {
    param([string]$Name, [string]$Address, [int[]]$HostPorts, [string]$Phase)
    if (($HostPorts -join ',') -cne ($script:allocationMappedPorts -join ',')) { throw 'Allocation did not inspect its created mapping.' }
    return [pscustomobject]@{ Container = $Name; Address = $Address; HostPort = $HostPorts[0] }
}
function Test-Endpoints {
    param([object[]]$Endpoints, [string]$Phase)
    if ($Endpoints[0].HostPort -ne $script:allocationExpectedPorts[0]) { throw 'Allocation did not verify its inspected endpoint.' }
    return [pscustomobject]@{ Passed = $true }
}
$allocated = Start-AllocatedProbe -NamePrefix 'allocation-shim' -Hash $hash
if (($allocated.Ports -join ',') -cne ($script:allocationExpectedPorts -join ',')) { throw 'Recreation failed to select the next available block.' }
if ($allocated.Attempts.Count -ne 3 -or $allocated.Attempts[0].Result -cne 'windows-bind-unavailable' -or $allocated.Attempts[1].Result -cne 'windows-bind-unavailable' -or $allocated.Attempts[2].Result -cne 'accepted') { throw 'Allocation did not preserve deterministic collision ordering.' }
Write-Host 'podman-networking-allocation.ps1 passed'
