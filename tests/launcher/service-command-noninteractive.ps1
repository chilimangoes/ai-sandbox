[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$source = Get-Content (Join-Path $repoRoot "bin/ai-sandbox.ps1") -Raw
$match = [regex]::Match($source, '(?ms)^function Exec-InContainer \{.*?^\}')
if (-not $match.Success) { throw "Exec-InContainer function missing." }
Invoke-Expression $match.Value

function docker {
    $script:dockerArgs = @($args)
    $global:LASTEXITCODE = 0
}
$DefaultT3ContainerPort = 3773
$DefaultAltHttpContainerPort = 8080
$DefaultAppContainerPort = 3000
$meta = [pscustomobject]@{ HostAddress = "127.91.42.17"; Container = "test"; ContainerWorkspacePath = "/workspace/project" }
$arguments = @("t3", "thread", "send", "thread-id", "-")
Exec-InContainer -Meta $meta -CommandArgs $arguments -KeepStdin
if ($script:dockerArgs -notcontains "-i" -or $script:dockerArgs -contains "-it") {
    throw "Piped T3 commands must keep stdin without requesting a terminal."
}
Exec-InContainer -Meta $meta -CommandArgs $arguments -Interactive -KeepStdin
if ($script:dockerArgs -notcontains "-it") { throw "Interactive T3 commands need a terminal." }
if (($script:dockerArgs[-5..-1] -join '|') -ne ($arguments -join '|')) {
    throw "Docker must receive the original T3 arguments."
}

$parserStart = $source.IndexOf('$update = $false')
$parserEnd = $source.IndexOf('Assert-Docker', $parserStart)
foreach ($arguments in @(@("t3", "--help"), @("t3", "auth", "session", "list", "--json"), @("t3", "future-command", "--update"))) {
    $ArgsList = $arguments
    Invoke-Expression $source.Substring($parserStart, $parserEnd - $parserStart)
    if (($positionals -join '|') -ne ($arguments -join '|') -or $update) {
        throw "The host parser must pass arguments after the tool name through unchanged."
    }
}
Write-Host "service-command-noninteractive.ps1 passed"
