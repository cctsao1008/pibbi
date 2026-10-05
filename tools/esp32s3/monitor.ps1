[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Port,
    [string]$Example = 'helloworld'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot '..\setup\common.ps1')
$repoRoot = Get-PibbiRepoRoot
$config = Get-Esp32S3ToolConfig
$watcherRoot = Join-Path $repoRoot $config.WatcherFirmware.Directory

if (-not (Test-Path -LiteralPath $watcherRoot -PathType Container)) {
    throw 'Watcher firmware checkout is missing. Run bootstrap-esp32s3.ps1 first.'
}

$watcherHead = (& git -C $watcherRoot rev-parse HEAD).Trim()
$shortSha = $watcherHead.Substring(0, 12)
$artifactRoot = Join-Path $repoRoot (Join-Path 'artifacts\esp32s3\build' (Join-Path $shortSha $Example))
$buildRoot = Join-Path $artifactRoot 'build'
$projectRoot = Join-Path $watcherRoot (Join-Path 'examples' $Example)

if (-not (Test-Path -LiteralPath $buildRoot -PathType Container)) {
    throw "Build directory not found: $buildRoot. Run .\tools\esp32s3\build.ps1 -Example $Example first."
}

. (Join-Path $repoRoot 'tools\setup\activate-esp32s3.ps1')

Push-Location $projectRoot
try {
    idf.py -B $buildRoot --port $Port monitor
    if ($LASTEXITCODE -ne 0) {
        throw "idf.py monitor failed with exit code $LASTEXITCODE"
    }
}
finally {
    Pop-Location
}
