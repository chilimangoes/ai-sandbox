[CmdletBinding(PositionalBinding = $false)]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ArgsList
)

$ErrorActionPreference = "Stop"

function Write-Usage {
    @"
Usage: ai-sandbox --add-folder <path> [--as <name>] [--global|--local] [--read-only|--read-write] [--yes]
"@
}

function Test-ContainerFolderName {
    param([string]$Name)
    return -not [string]::IsNullOrWhiteSpace($Name) -and
        $Name.Trim() -eq $Name -and
        $Name -notmatch '[\\/:\*\?"<>\|]'
}

function Split-SupplementalFolderLine {
    param([string]$Line)

    $trimmed = $Line.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith("#")) {
        return $null
    }

    $mode = "ro"
    $withoutMode = $trimmed
    $modeSeparator = $trimmed.LastIndexOf('|')
    if ($modeSeparator -ge 0) {
        $candidateMode = $trimmed.Substring($modeSeparator + 1)
        if ($candidateMode -eq "ro" -or $candidateMode -eq "rw") {
            $mode = $candidateMode
            $withoutMode = $trimmed.Substring(0, $modeSeparator)
        }
    }

    $nameSeparator = $withoutMode.LastIndexOf('|')
    if ($nameSeparator -lt 0) {
        throw "Invalid supplemental folder line: $Line"
    }

    [pscustomobject]@{
        HostPath = $withoutMode.Substring(0, $nameSeparator)
        Name = $withoutMode.Substring($nameSeparator + 1)
        Mode = $mode
    }
}

function Read-Choice {
    param(
        [string]$Prompt,
        [string]$Default
    )

    $suffix = if ($Default -eq "y") { "[Y/n]" } else { "[y/N]" }
    $answer = Read-Host "$Prompt $suffix"
    if ([string]::IsNullOrWhiteSpace($answer)) {
        return $Default
    }
    return $answer.Trim().Substring(0, 1).ToLowerInvariant()
}

$folderPath = $null
$containerName = $null
$scope = $null
$mode = $null
$yes = $false

for ($i = 0; $i -lt $ArgsList.Count; $i++) {
    switch ($ArgsList[$i]) {
        "--help" {
            Write-Usage
            exit 0
        }
        "--path" {
            $i++
            if ($i -ge $ArgsList.Count) { throw "Missing value for --path." }
            $folderPath = $ArgsList[$i]
        }
        "--as" {
            $i++
            if ($i -ge $ArgsList.Count) { throw "Missing value for --as." }
            $containerName = $ArgsList[$i]
        }
        "--global" {
            $scope = "global"
        }
        "--local" {
            $scope = "local"
        }
        "--read-only" {
            $mode = "ro"
        }
        "--read-write" {
            $mode = "rw"
        }
        "--yes" {
            $yes = $true
        }
        default {
            if ($ArgsList[$i].StartsWith("--")) {
                throw "Unknown option for --add-folder: $($ArgsList[$i])"
            }
            if ($folderPath) {
                throw "Unexpected argument for --add-folder: $($ArgsList[$i])"
            }
            $folderPath = $ArgsList[$i]
        }
    }
}

if (-not $folderPath) {
    throw "Missing folder path for --add-folder."
}

$resolvedFolderPath = [System.IO.Path]::GetFullPath($folderPath)
if (-not (Test-Path -LiteralPath $resolvedFolderPath -PathType Container)) {
    throw "Supplemental folder does not exist or is not a directory: $resolvedFolderPath"
}

if (-not $containerName) {
    $defaultName = Split-Path -Leaf $resolvedFolderPath
    $answer = Read-Host "Container folder name under /supplemental [$defaultName]"
    $containerName = if ([string]::IsNullOrWhiteSpace($answer)) { $defaultName } else { $answer.Trim() }
}

if (-not (Test-ContainerFolderName -Name $containerName)) {
    throw "Invalid container folder name '$containerName'. It must be one path segment and cannot contain / \ : * ? `" < > |."
}

if (-not $scope) {
    $answer = Read-Host "Scope: local or global [local]"
    $scope = if ([string]::IsNullOrWhiteSpace($answer)) { "local" } else { $answer.Trim().ToLowerInvariant() }
}
if ($scope -ne "local" -and $scope -ne "global") {
    throw "Scope must be local or global."
}

if (-not $mode) {
    $readOnly = Read-Choice -Prompt "Mount read-only?" -Default "y"
    $mode = if ($readOnly -eq "n") { "rw" } else { "ro" }
}

$workspacePath = (Get-Location).Path
$configPath = if ($scope -eq "global") {
    Join-Path $HOME ".ai-sandbox\supplemental-folders.config"
} else {
    Join-Path $workspacePath ".ai-sandbox\supplemental-folders.config"
}

$configDir = Split-Path -Parent $configPath
if (-not (Test-Path -LiteralPath $configDir -PathType Container)) {
    New-Item -ItemType Directory -Path $configDir | Out-Null
}

$newLine = "$resolvedFolderPath|$containerName|$mode"
$lines = if (Test-Path -LiteralPath $configPath) { @(Get-Content -LiteralPath $configPath) } else { @() }
$outputLines = New-Object System.Collections.Generic.List[string]
$replaced = $false

foreach ($line in $lines) {
    $entry = Split-SupplementalFolderLine -Line $line
    if ($entry -and $entry.Name -eq $containerName) {
        if (-not $replaced) {
            if (-not $yes) {
                Write-Host "/supplemental/$containerName is already configured in $scope config:"
                Write-Host ""
                Write-Host "  $($entry.HostPath) -> /supplemental/$($entry.Name)"
                Write-Host ""
                Write-Host "Replace it with this mapping?"
                Write-Host ""
                Write-Host "  $resolvedFolderPath -> /supplemental/$containerName"
                Write-Host ""
                $replace = Read-Choice -Prompt "Replace existing entry?" -Default "y"
                if ($replace -eq "n") {
                    Write-Host "No changes made."
                    exit 0
                }
            }
            $outputLines.Add($newLine)
            $replaced = $true
        }
    } else {
        $outputLines.Add($line)
    }
}

if (-not $replaced) {
    $outputLines.Add($newLine)
}

Set-Content -LiteralPath $configPath -Encoding ASCII -Value $outputLines
Write-Host "Added supplemental folder mapping:"
Write-Host "  $resolvedFolderPath -> /supplemental/$containerName ($mode, $scope)"
Write-Host "Config: $configPath"

if (-not $yes) {
    $rebuild = Read-Choice -Prompt "Newly added folders require rebuilding the sandbox container. Do you want to rebuild the container for the current workspace now?" -Default "y"
    if ($rebuild -eq "n") {
        Write-Host "Run ai-sandbox --rebuild from this workspace when you want the new mapping mounted."
        exit 0
    }
}

$launcher = Join-Path (Split-Path -Parent $PSScriptRoot) "bin\ai-sandbox.ps1"
& $launcher --rebuild
exit $LASTEXITCODE
