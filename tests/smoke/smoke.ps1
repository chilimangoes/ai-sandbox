[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
$ImageTag = "ai-sandbox:latest"
$ContainerName = "ai-sandbox-smoke"

docker build -t $ImageTag $RepoRoot
docker run --rm --name $ContainerName $ImageTag /opt/ai-sandbox/image-smoke-check.sh
