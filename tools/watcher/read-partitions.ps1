# Watcher B2a: read-only flash partition-table inspection.
# NO write_flash, erase, efuse burn, bootloader update, or app flash.
# This enters the ESP32-S3 serial download protocol and may reset the MCU.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidatePattern('^COM[0-9]+$')]
    [string]$Port
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
if (-not $env:IDF_PATH) {
    throw "Activate ESP-IDF v5.2.1 PowerShell first."
}
$partTool = Join-Path $env:IDF_PATH "components\partition_table\gen_esp32part.py"
if (-not (Test-Path -LiteralPath $partTool)) {
    throw "ESP-IDF partition parser unavailable: $partTool"
}
if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
    throw "Python executable not present in activated ESP-IDF environment."
}
$IdfVersion = ((& idf.py --version 2>&1) | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $IdfVersion -notmatch '\bv5\.2\.1\b') {
    throw "ESP-IDF v5.2.1 required; observed: $IdfVersion"
}
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$runDir = Join-Path $repoRoot "artifacts\pibbi\watcher-b2-readonly\$stamp"
New-Item -ItemType Directory -Force -Path $runDir | Out-Null
$binPath = Join-Path $runDir "esp32s3-partition-table.bin"
$reportPath = Join-Path $runDir "esp32s3-partition-table.txt"

Write-Host "DEVICE READ-ONLY PREFLIGHT: $Port"
Write-Host "Connects to ESP32-S3 serial download port. May temporarily reset Watcher."
Write-Host "Reads ONLY 4096 bytes at 0x8000; no other flash/NVS data."
Write-Host "NEVER flash, erase or burn efuses. Ensure port is ESP32-S3, not HX6538."

$esptoolArgs = @("--chip", "esp32s3", "--port", $Port, "--baud", "115200",
                 "read_flash", "0x8000", "0x1000", $binPath)
& python -m esptool @esptoolArgs
if ($LASTEXITCODE -ne 0) {
    throw "Partition read failed. Do not proceed to flashing or backup assumptions."
}
if ((Get-Item -LiteralPath $binPath).Length -ne 4096) {
    throw "Partition read unexpectedly differs from 4096 bytes."
}

$output = & python $partTool $binPath 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host ($output | Out-String)
    throw "Partition table decode failed. STOP: flash layout or security may differ."
}
$display = $output | Out-String
$display | Set-Content -LiteralPath $reportPath -Encoding UTF8
$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $binPath).Hash
Write-Host "READ_ONLY_PARTITION_PASS"
Write-Host "Physical offset 0x8000, length 0x1000"
Write-Host "Partition SHA256: $hash"
Write-Host "Partition metadata:"
Write-Host $display
Write-Host "Local output: $runDir"
Write-Host "No bootloader, app or factory credential contents intentionally read."
