Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($MyInvocation.InvocationName -ne '.') {
    Write-Warning 'This script must be dot-sourced so the environment remains in the current PowerShell session.'
    Write-Host 'Use:'
    Write-Host '  . .\tools\setup\activate-esp32s3.ps1'
    return
}

. (Join-Path $PSScriptRoot 'common.ps1')

$repoRoot = Get-PibbiRepoRoot
$config = Get-Esp32S3ToolConfig
$idfRoot = Join-Path $repoRoot $config.EspIdf.Directory
$idfToolsRoot = Join-Path $repoRoot $config.EspIdfTools.Directory
$watcherRoot = Join-Path $repoRoot $config.WatcherFirmware.Directory

$missing = @()
foreach ($path in @($idfRoot, $idfToolsRoot, $watcherRoot)) {
    if (-not (Test-Path -LiteralPath $path -PathType Container)) {
        $missing += $path
    }
}
if ($missing.Count -gt 0) {
    throw ("ESP32-S3 environment is not bootstrapped. Missing:`n  " + ($missing -join "`n  ") + "`nRun .\tools\setup\bootstrap-esp32s3.ps1 first.")
}

$env:PIBBI_ROOT = $repoRoot
$env:IDF_PATH = (Resolve-Path -LiteralPath $idfRoot).Path
$env:IDF_TOOLS_PATH = (Resolve-Path -LiteralPath $idfToolsRoot).Path
$env:PIBBI_ESP32_TARGET = $config.EspIdf.Target
$env:PIBBI_WATCHER_ROOT = (Resolve-Path -LiteralPath $watcherRoot).Path

$exportScript = Join-Path $env:IDF_PATH 'export.ps1'
if (-not (Test-Path -LiteralPath $exportScript -PathType Leaf)) {
    throw "ESP-IDF export script not found: $exportScript"
}

# ESP-IDF may emit informational stderr while selecting managed tools, for
# example when a newer unsupported system CMake is present. Windows PowerShell
# 5.1 promotes native stderr to ErrorRecord; with ErrorActionPreference=Stop
# that benign message would abort activation. Let the official export script
# make the tool-selection decision, then restore pibbi's strict error policy.
$savedErrorActionPreference = $ErrorActionPreference
try {
    $ErrorActionPreference = 'Continue'
    . $exportScript
}
finally {
    $ErrorActionPreference = $savedErrorActionPreference
}

Write-Host ''
Write-Host 'pibbi ESP32-S3 environment activated for this PowerShell session.'
Write-Host "PIBBI_ROOT          = $env:PIBBI_ROOT"
Write-Host "IDF_PATH            = $env:IDF_PATH"
Write-Host "IDF_TOOLS_PATH      = $env:IDF_TOOLS_PATH"
Write-Host "PIBBI_ESP32_TARGET  = $env:PIBBI_ESP32_TARGET"
Write-Host "PIBBI_WATCHER_ROOT  = $env:PIBBI_WATCHER_ROOT"
Write-Host ''
Write-Host 'Run .\tools\setup\check-esp32s3-env.ps1 to verify the active environment.'
