[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Port
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot '..\setup\common.ps1')
$repoRoot = Get-PibbiRepoRoot
$config = Get-Esp32S3ToolConfig

. (Join-Path $repoRoot 'tools\setup\activate-esp32s3.ps1')

function Invoke-Esptool {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    & python -m esptool --chip $config.EspIdf.Target --port $Port @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "esptool command failed ($LASTEXITCODE): $($Arguments -join ' ')"
    }
}

Write-Host 'pibbi ESP32-S3 device inspection (read-only)'
Write-Host "Port: $Port"
Write-Host ''

Write-Host '==> chip_id'
Invoke-Esptool -Arguments @('chip_id')
Write-Host ''

Write-Host '==> flash_id'
Invoke-Esptool -Arguments @('flash_id')
Write-Host ''

Write-Host '==> get_security_info'
Invoke-Esptool -Arguments @('get_security_info')
