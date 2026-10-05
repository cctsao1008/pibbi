Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($MyInvocation.InvocationName -ne '.') {
    Write-Warning 'This script must be dot-sourced so the environment remains in the current PowerShell session.'
    Write-Host 'Use:'
    Write-Host '  . .\tools\setup\activate-hx6538.ps1'
    return
}

. (Join-Path $PSScriptRoot 'common.ps1')

$repoRoot = Get-PibbiRepoRoot
$config = Get-Hx6538ToolConfig
$toolsRoot = Join-Path $repoRoot '.tools'

$armBin = Join-Path $toolsRoot (Join-Path $config.ArmGnuToolchain.Directory 'bin')
$buildToolsBin = Join-Path $toolsRoot (Join-Path $config.WindowsBuildTools.Directory 'bin')
$sdkPath = Join-Path $repoRoot $config.SscmaWe2.Directory

$missing = @()
foreach ($path in @($armBin, $buildToolsBin, $sdkPath)) {
    if (-not (Test-Path -LiteralPath $path)) {
        $missing += $path
    }
}

if ($missing.Count -gt 0) {
    throw ("HX6538 environment is not bootstrapped. Missing:`n  " + ($missing -join "`n  ") + "`nRun .\tools\setup\bootstrap-hx6538.ps1 first.")
}

# Remove duplicate project-local entries before prepending them again.
$currentPath = @($env:PATH -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$normalizedArm = [IO.Path]::GetFullPath($armBin).TrimEnd('\')
$normalizedBuild = [IO.Path]::GetFullPath($buildToolsBin).TrimEnd('\')

$currentPath = $currentPath | Where-Object {
    $candidate = $_.TrimEnd('\')
    ($candidate -ne $normalizedArm) -and ($candidate -ne $normalizedBuild)
}

$env:PATH = (@($normalizedArm, $normalizedBuild) + $currentPath) -join ';'
$env:SSCMA_WE2_ROOT = (Resolve-Path -LiteralPath $sdkPath).Path
$env:PIBBI_ROOT = $repoRoot

Write-Host 'pibbi HX6538 environment activated for this PowerShell session.'
Write-Host "PIBBI_ROOT       = $env:PIBBI_ROOT"
Write-Host "SSCMA_WE2_ROOT   = $env:SSCMA_WE2_ROOT"
Write-Host "Arm GNU bin      = $normalizedArm"
Write-Host "GNU Make bin     = $normalizedBuild"
Write-Host ''
Write-Host 'Run .\tools\setup\check-env.ps1 to verify the active environment.'
