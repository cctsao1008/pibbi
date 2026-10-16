# OTA1 app updater after initial deployment; does NOT modify otadata.
# Requires user to run on Windows with ESP-IDF v5.2.1 and COM31 free.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidatePattern('^COM[0-9]+$')][string]$Port,
    [Parameter(Mandatory=$true)][string]$BackupDir,
    [switch]$Apply
)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$expectedTableSHA = "535EA803C19353B47BACEA78DE4642692920CD925402233666FF9E7EB9189D73"
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
$fwDir = Join-Path $repo "firmware\watcher\lcd-probe"
$fw = Join-Path $fwDir "build\pibbi_watcher_lcd_probe.bin"
$inspector = Join-Path $PSScriptRoot "inspect-backup-offline.py"
$otaOffset = "0xD10000"
$maxBytes = 0xC00000
if (-not $env:IDF_PATH) { throw "Open ESP-IDF v5.2.1 PowerShell." }
$idfVersion = ((& idf.py --version 2>&1) | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $idfVersion -notmatch '\bv5\.2\.1\b') {
    throw "Expected ESP-IDF v5.2.1; found: $idfVersion"
}
if (-not (Test-Path -LiteralPath $fw)) { throw "App BIN missing; run build-lcd-probe.ps1" }
if (-not (Test-Path -LiteralPath $BackupDir)) { throw "Private baseline backup missing" }
$size = (Get-Item -LiteralPath $fw).Length
if ($size -lt 10000 -or $size -ge $maxBytes) { throw "BIN does not fit OTA1" }

# Refuse an accidentally stale BIN when adding a touch UI source file.
$binTime = (Get-Item -LiteralPath $fw).LastWriteTimeUtc
foreach ($name in @("pibbi_touch.c","pibbi_power_ui.h","lcd_first_frame.c","pibbi_rgb.c")) {
    $sourceFile = Join-Path $fwDir "main\$name"
    if (-not (Test-Path -LiteralPath $sourceFile) -or
        (Get-Item -LiteralPath $sourceFile).LastWriteTimeUtc -gt $binTime) {
        throw "B1b BIN older than $name or source missing; run build-lcd-probe.ps1"
    }
}
Write-Host "PIBBI OTA1 UPDATE: Port=$Port Offset=$otaOffset Bytes=$size"
Write-Host "BIN SHA256: $((Get-FileHash -Algorithm SHA256 -LiteralPath $fw).Hash)"
Write-Host "Only OTA1 app will be written. No OTA0, otadata, NVS or bootloader changes."
if (-not $Apply) {
    Write-Host "DRY_RUN_ONLY: rerun with -Apply for approved OTA1-only write."
    return
}
$backupCheck = @'
import pathlib,runpy,sys
inspect=runpy.run_path(sys.argv[1])["inspect"]
report=inspect(pathlib.Path(sys.argv[2]))
if report["status"]!="OFFLINE_BACKUP_INTEGRITY_PASS":
    sys.exit("PRIVATE_BACKUP_INTEGRITY_FAIL")
print("PRIVATE_BASELINE_BACKUP_PASS")
'@
& python -c $backupCheck $inspector $BackupDir
if ($LASTEXITCODE -ne 0) { throw "Private backup verification failed. NO WRITE." }

$imageInfo = (& python -m esptool --chip esp32s3 image_info --version 2 $fw 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0 -or
    $imageInfo -notmatch "Chip ID:\s+9\s+\(ESP32-S3\)" -or
    $imageInfo -notmatch "Checksum:\s+0x[0-9a-fA-F]+\s+\(valid\)" -or
    $imageInfo -notmatch "Validation hash:\s+[0-9a-fA-F]{64}\s+\(valid\)" -or
    $imageInfo -notmatch "Project name:\s+pibbi_watcher_lcd_probe") {
    throw "B1b BIN image_info failed; NO WRITE."
}
Write-Host "NEW_APP_BIN_IMAGE_INFO_PASS"

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("pibbi-ota1-update-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
    function ReadFlash([string]$addr,[string]$bytes,[string]$out) {
        & python -m esptool --chip esp32s3 --port $Port --baud 115200 read_flash $addr $bytes $out
        if ($LASTEXITCODE -ne 0) { throw "Read failed at $addr. STOP." }
    }
    $pt = Join-Path $tmp "partition.bin"
    $otabefore = Join-Path $tmp "otadata-before.bin"
    $ota0head = Join-Path $tmp "ota0-head.bin"
    $ota1head = Join-Path $tmp "ota1-head.bin"
    $otaafter = Join-Path $tmp "otadata-after.bin"
    ReadFlash "0x8000" "0x1000" $pt
    if ((Get-Item -LiteralPath $pt).Length -ne 4096 -or
        (Get-FileHash -LiteralPath $pt -Algorithm SHA256).Hash -ne $expectedTableSHA) {
        throw "PHYSICAL_PARTITION_LAYOUT_MISMATCH. NO WRITE."
    }
    ReadFlash "0x10D000" "0x2000" $otabefore
    ReadFlash "0x110000" "0x1000" $ota0head
    ReadFlash $otaOffset "0x1000" $ota1head
    $liveCheck = @'
import pathlib,runpy,sys
mod=runpy.run_path(sys.argv[1])
data=pathlib.Path(sys.argv[2]).read_bytes()
ota0=pathlib.Path(sys.argv[3]).read_bytes()
ota1=pathlib.Path(sys.argv[4]).read_bytes()
if len(data)!=8192 or len(ota0)!=4096 or len(ota1)!=4096:
    sys.exit("TRUNCATED_LIVE_FLASH_DATA")
e=[mod["ota_entry"](data,i) for i in (0,1)]
slot,_=mod["candidate_ota"](e)
if slot!="ota_1":
    sys.exit("LIVE_BOOT_SELECTOR_NOT_OTA1: "+slot)
if ota0[0]!=0xE9 or ota1[0]!=0xE9:
    sys.exit("MISSING_OTA0_OR_OTA1_APP_HEADER")
print("LIVE_OTA1_UPDATE_PREFLIGHT_PASS")
'@
    & python -c $liveCheck $inspector $otabefore $ota0head $ota1head
    if ($LASTEXITCODE -ne 0) { throw "OTA1 current slot validation failed; NO WRITE." }

    Write-Host "WRITING ONLY OTA1 APP at 0xD10000"
    & python -m esptool --chip esp32s3 --port $Port --baud 460800 write_flash --flash_mode keep --flash_freq keep --flash_size keep --verify $otaOffset $fw
    if ($LASTEXITCODE -ne 0) { throw "OTA1 write failed; use OTA0 rollback if needed." }
    & python -m esptool --chip esp32s3 --port $Port --baud 460800 verify_flash $otaOffset $fw
    if ($LASTEXITCODE -ne 0) { throw "OTA1 readback verification failed." }
    ReadFlash "0x10D000" "0x2000" $otaafter
    if ((Get-FileHash -LiteralPath $otabefore -Algorithm SHA256).Hash -ne
        (Get-FileHash -LiteralPath $otaafter -Algorithm SHA256).Hash) {
        throw "OTADATA_CHANGED_DURING_UPDATE: inspect before proceeding."
    }
    Write-Host "UPDATE_OTA1_PASS: app verified, OTA metadata unchanged."
    Write-Host "Monitor COM31 at 115200: verify TOUCH_READY and OFF/YES/NO touch operation."
} finally {
    Remove-Item -LiteralPath $tmp -Force -Recurse -ErrorAction SilentlyContinue
}
