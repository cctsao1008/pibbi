# B1a build-only entrypoint. No flashing, erase, COM access, or SDK mutation.
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ProjectDir = [System.IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot "..\..\firmware\watcher\minimal")
)
if (-not (Test-Path -LiteralPath (Join-Path $ProjectDir "main\main.c"))) {
    throw "Minimal Watcher project missing: $ProjectDir"
}
if (-not $env:IDF_PATH) {
    throw "ESP-IDF is not activated. Launch the ESP-IDF v5.2.1 PowerShell environment first."
}
if (-not (Get-Command idf.py -ErrorAction SilentlyContinue)) {
    throw "idf.py not found in PATH; activate ESP-IDF v5.2.1 first."
}
$IdfVersion = ((& idf.py --version 2>&1) | Out-String).Trim()
if ($LASTEXITCODE -ne 0) {
    throw "idf.py --version failed."
}
if ($IdfVersion -notmatch '\bv5\.2\.1\b') {
    throw "Build requires ESP-IDF v5.2.1, detected '$IdfVersion'. Do not silently mix SDK versions."
}
Write-Host "[pibbi B1a] ESP-IDF: $IdfVersion"
Write-Host "[pibbi B1a] Project: $ProjectDir"
Write-Host "[pibbi B1a] BUILD ONLY: no flash, erase, monitor, COM, bootloader replacement."

Push-Location $ProjectDir
try {
    & idf.py build
    if ($LASTEXITCODE -ne 0) {
        throw "idf.py build failed with exit code $LASTEXITCODE."
    }
    $ElfPath = Join-Path $ProjectDir "build\pibbi_watcher_minimal.elf"
    $BinPath = Join-Path $ProjectDir "build\pibbi_watcher_minimal.bin"
    if (-not (Test-Path -LiteralPath $ElfPath)) {
        throw "idf.py returned success but ELF was not found: $ElfPath"
    }
    $ElfHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $ElfPath).Hash
    Write-Host "BUILD_PASS (not hardware-validated)"
    Write-Host "ELF: $ElfPath"
    Write-Host "ELF SHA256: $ElfHash"
    if (Test-Path -LiteralPath $BinPath) {
        Write-Host "Application BIN: $BinPath (DO NOT FLASH)"
    }
} finally {
    Pop-Location
}
