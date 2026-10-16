# B1b: source/build only. No ESP32/Himax flash/erase/COM-port action.
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ProjectDir = [System.IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot "..\..\firmware\watcher\lcd-probe"))
if (-not (Test-Path -LiteralPath (Join-Path $ProjectDir "main\lcd_first_frame.c"))) {
    throw "LCD-probe project missing: $ProjectDir"
}
if (-not $env:IDF_PATH) {
    throw "ESP-IDF is not active. Open the ESP-IDF v5.2.1 PowerShell environment."
}
if (-not (Get-Command idf.py -ErrorAction SilentlyContinue)) {
    throw "idf.py not found; activate ESP-IDF v5.2.1."
}
$IdfVersion = ((& idf.py --version 2>&1) | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $IdfVersion -notmatch '\bv5\.2\.1\b') {
    throw "ESP-IDF v5.2.1 required; detected: $IdfVersion."
}
Write-Host "[pibbi B1b] $IdfVersion"
Write-Host "[pibbi B1b] Standalone QSPI SPD2010 first-frame + GPIO40 breathing RGB project."
Write-Host "[pibbi B1b] This script only invokes idf.py build. NO FLASH/ERASE/MONITOR."
Write-Host "[pibbi B1b] Component Manager may fetch pinned espressif/esp_lcd_spd2010 v1.0.1."

Push-Location $ProjectDir
try {
    & idf.py build
    if ($LASTEXITCODE -ne 0) {
        throw "B1b idf.py build failed with exit code $LASTEXITCODE."
    }
    $elf = Join-Path $ProjectDir "build\pibbi_watcher_lcd_probe.elf"
    $bin = Join-Path $ProjectDir "build\pibbi_watcher_lcd_probe.bin"
    if (-not (Test-Path -LiteralPath $elf)) {
        throw "Build reported success but expected ELF absent: $elf."
    }
    Write-Host "BUILD_PASS_B1B (NOT HARDWARE VERIFIED)"
    Write-Host "ELF: $elf"
    Write-Host "ELF SHA256: $((Get-FileHash -Algorithm SHA256 -LiteralPath $elf).Hash)"
    if (Test-Path -LiteralPath $bin) {
        Write-Host "Application BIN: $bin (use guarded deploy-minimal-ota1.ps1; NEVER generic idf.py flash/app-flash)"
    }
} finally {
    Pop-Location
}
