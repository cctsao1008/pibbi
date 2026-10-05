[CmdletBinding()]
param(
    [ValidateSet('all', 'hx6538', 'esp32s3')]
    [string]$Platform = 'all',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Write-Host 'pibbi development environment bootstrap'
Write-Host "Platform: $Platform"
Write-Host ''

if ($Platform -eq 'all' -or $Platform -eq 'hx6538') {
    Write-Host '===== HX6538 ====='
    & (Join-Path $PSScriptRoot 'bootstrap-hx6538.ps1') -Force:$Force
    if ($LASTEXITCODE -ne 0) {
        throw "HX6538 bootstrap failed with exit code $LASTEXITCODE"
    }
    Write-Host ''
}

if ($Platform -eq 'all' -or $Platform -eq 'esp32s3') {
    Write-Host '===== ESP32-S3 ====='
    & (Join-Path $PSScriptRoot 'bootstrap-esp32s3.ps1') -Force:$Force
    if ($LASTEXITCODE -ne 0) {
        throw "ESP32-S3 bootstrap failed with exit code $LASTEXITCODE"
    }
    Write-Host ''
}

Write-Host 'Requested pibbi environment bootstrap complete.'
