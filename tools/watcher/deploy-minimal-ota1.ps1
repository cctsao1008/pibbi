# Explicit OTA1-only deployment of pibbi Watcher minimal LCD firmware.
# Writes App to OTA1 at 0xD10000, then switches only the OTA metadata.
# No changes to OTA0, Bootloader, Partition Table, NVS, model, storage or Himax.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidatePattern('^COM[0-9]+$')][string]$Port,
    [Parameter(Mandatory=$true)][string]$BackupDir,
    [switch]$Apply
)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$expectedTableSHA = "535EA803C19353B47BACEA78DE4642692920CD925402233666FF9E7EB9189D73"
$ota1Offset = "0xD10000"
$ota1Capacity = 0xC00000
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
$fw = Join-Path $repo "firmware\watcher\lcd-probe\build\pibbi_watcher_lcd_probe.bin"
$inspector = Join-Path $repo "tools\watcher\inspect-backup-offline.py"
$occupancy = Join-Path $repo "tools\watcher\inspect-ota1-occupancy-offline.py"
if (-not $env:IDF_PATH) { throw "ESP-IDF v5.2.1 PowerShell required." }
$idfVer = ((& idf.py --version 2>&1) | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $idfVer -notmatch '\bv5\.2\.1\b') { throw "Unexpected IDF version: $idfVer" }
$otaTool = Join-Path $env:IDF_PATH "components\app_update\otatool.py"
if (-not (Test-Path -LiteralPath $otaTool)) { throw "Official ESP-IDF otatool.py not found" }
if (-not (Test-Path -LiteralPath $fw)) { throw "B1b BIN missing, first run build-lcd-probe.ps1" }
if (-not (Test-Path -LiteralPath $BackupDir)) { throw "Missing private B2c backup folder" }
$size = (Get-Item -LiteralPath $fw).Length
if ($size -lt 10000 -or $size -gt $ota1Capacity) { throw "Invalid app size for 12MiB OTA1" }
Write-Host "PIBBI minimal OTA1 only; Port=$Port; physical offset=$ota1Offset"
Write-Host "App size=$size; BIN SHA256=$((Get-FileHash -LiteralPath $fw -Algorithm SHA256).Hash)"
Write-Host "OTA0 original user-built firmware remains untouched."
if (-not $Apply) {
    Write-Host "DRY_RUN_ONLY: rerun with -Apply for the authorized OTA1 and otadata writes."
    return
}

$privateCheck = @'
import pathlib,runpy,sys
verify=runpy.run_path(sys.argv[1])["inspect"]
scan=runpy.run_path(sys.argv[2])["scan_region"]
root=pathlib.Path(sys.argv[3])
report=verify(root)
if report["status"]!="OFFLINE_BACKUP_INTEGRITY_PASS" or report["inferred_boot_candidate"]!="ota_0":
    sys.exit("PRIVATE_BACKUP_CHECK_FAIL")
with (root/"esp32s3-full-32MiB-PRIVATE.bin").open("rb") as f:
    result=scan(f,0xD10000,0xC00000)
if not result["fully_erased_all_ff"]:
    sys.exit("PRIVATE_BACKUP_OTA1_NONEMPTY")
print("PRIVATE_BACKUP_AND_OTA1_SNAPSHOT_PASS")
'@
& python -c $privateCheck $inspector $occupancy $BackupDir
if ($LASTEXITCODE -ne 0) { throw "Private backup or OTA1 snapshot check failed. No device writes." }

$imageInfo = (& python -m esptool --chip esp32s3 image_info --version 2 $fw 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0 -or $imageInfo -notmatch "Chip ID:\s+9\s+\(ESP32-S3\)" -or $imageInfo -notmatch "Checksum:\s+0x[0-9a-fA-F]+\s+\(valid\)" -or $imageInfo -notmatch "Validation hash:\s+[0-9a-fA-F]{64}\s+\(valid\)") {
    throw "B1b BIN image-info validation failed, no device writes."
}
Write-Host "LOCAL_BIN_IMAGE_VALIDATED"

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("pibbi-ota1-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
    function ReadFlash([string]$offset,[string]$count,[string]$dest) {
        & python -m esptool --chip esp32s3 --port $Port --baud 115200 read_flash $offset $count $dest
        if ($LASTEXITCODE -ne 0) { throw "Read failed at $offset. STOP." }
    }
    $pt = Join-Path $tmp "part.bin"
    $otabefore = Join-Path $tmp "ota-before.bin"
    $ota1Head = Join-Path $tmp "ota1-head.bin"
    $otaafter = Join-Path $tmp "ota-after.bin"
    ReadFlash "0x8000" "0x1000" $pt
    if ((Get-Item -LiteralPath $pt).Length -ne 4096 -or (Get-FileHash -LiteralPath $pt -Algorithm SHA256).Hash -ne $expectedTableSHA) {
        throw "Physical device partition SHA changed. No writes."
    }
    ReadFlash "0x10D000" "0x2000" $otabefore
    ReadFlash $ota1Offset "0x1000" $ota1Head

    $checkBefore = @'
import runpy,sys
m=runpy.run_path(sys.argv[1])
d=open(sys.argv[2],"rb").read()
h=open(sys.argv[3],"rb").read()
if len(d)!=8192 or len(h)!=4096 or any(x!=255 for x in h):
    sys.exit("LIVE_OTA1_NOT_EMPTY_OR_TRUNCATED")
e=[m["ota_entry"](d,i) for i in (0,1)]
slot,_=m["candidate_ota"](e)
if slot!="ota_0" or e[1]["bootloader_selectable"]:
    sys.exit("LIVE_OTADATA_UNEXPECTED")
print("LIVE_PREFLIGHT_OTA0_SELECTED_OTA1_EMPTY_PASS")
'@
    & python -c $checkBefore $inspector $otabefore $ota1Head
    if ($LASTEXITCODE -ne 0) { throw "Live OTA preflight failed; no writes." }

    Write-Host "WRITE_1: ota_1 0xD10000 only (app BIN)"
    & python -m esptool --chip esp32s3 --port $Port --baud 460800 write_flash --flash_mode keep --flash_freq keep --flash_size keep --verify $ota1Offset $fw
    if ($LASTEXITCODE -ne 0) { throw "OTA1 app write failed. OTA0 remains selected." }
    & python -m esptool --chip esp32s3 --port $Port --baud 460800 verify_flash $ota1Offset $fw
    if ($LASTEXITCODE -ne 0) { throw "OTA1 verify failed; OTA boot selection NOT changed." }
    Write-Host "OTA1_APP_WRITE_VERIFY_PASS"

    Write-Host "WRITE_2: official ESP-IDF switch_ota_partition --slot 1 (otadata only)"
    & python $otaTool --port $Port --baud 115200 switch_ota_partition --slot 1
    if ($LASTEXITCODE -ne 0) { throw "OTA selection switch failed; inspect before retry." }

    ReadFlash "0x10D000" "0x2000" $otaafter
    $checkAfter = @'
import runpy,sys
m=runpy.run_path(sys.argv[1])
d=open(sys.argv[2],"rb").read()
if len(d)!=8192:sys.exit("OTADATA_TRUNCATED")
e=[m["ota_entry"](d,i) for i in (0,1)]
slot,_=m["candidate_ota"](e)
if slot!="ota_1":sys.exit("OTA1_SELECTION_VERIFY_FAILED: "+slot)
print("OTA_BOOT_SELECTION_OTA1_PASS")
'@
    & python -c $checkAfter $inspector $otaafter
    if ($LASTEXITCODE -ne 0) { throw "OTA selection verification failed. Do not flash again." }
    Write-Host "DEPLOY_OTA1_PASS: restart Watcher and capture BOOT_MARK, UI_READY, or UI_FAIL."
    Write-Host "Fallback: restore-ota0-boot.ps1 -Port $Port -Apply"
} finally {
    Remove-Item -LiteralPath $tmp -Force -Recurse -ErrorAction SilentlyContinue
}
