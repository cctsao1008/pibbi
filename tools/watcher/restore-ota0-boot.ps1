# Recovery: change OTA selection back to prior user-built OTA0 firmware.
# Only otadata changes (via official ESP-IDF otatool). No OTA0 app reflash.
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][ValidatePattern('^COM[0-9]+$')][string]$Port,
  [switch]$Apply
)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$expectedTableSHA = "535EA803C19353B47BACEA78DE4642692920CD925402233666FF9E7EB9189D73"
if (-not $env:IDF_PATH) { throw "Activate ESP-IDF v5.2.1 PowerShell" }
$idfVer = ((& idf.py --version 2>&1) | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $idfVer -notmatch '\bv5\.2\.1\b') { throw "Wrong IDF version: $idfVer" }
$otaTool = Join-Path $env:IDF_PATH "components\app_update\otatool.py"
if (-not (Test-Path -LiteralPath $otaTool)) { throw "ESP-IDF otatool.py missing" }
$inspector = Join-Path $PSScriptRoot "inspect-backup-offline.py"
Write-Host "WATCHER ROLLBACK: boot OTA0 (0x110000) using otadata only."
if (-not $Apply) {
  Write-Host "DRY_RUN_ONLY: re-run with -Apply to switch OTA boot metadata."
  return
}
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("pibbi-rollback-" + [guid]::NewGuid().ToString("N"))
New-Item -Path $tmp -ItemType Directory | Out-Null
try {
  function ReadFlash([string]$addr,[string]$count,[string]$out) {
    & python -m esptool --chip esp32s3 --port $Port --baud 115200 read_flash $addr $count $out
    if ($LASTEXITCODE -ne 0) { throw "Read failed at $addr" }
  }
  $pt = Join-Path $tmp "pt.bin"
  $ota0Head = Join-Path $tmp "ota0-first-sector.bin"
  $after = Join-Path $tmp "ota-after.bin"
  ReadFlash "0x8000" "0x1000" $pt
  if ((Get-Item -LiteralPath $pt).Length -ne 4096 -or (Get-FileHash -Algorithm SHA256 -LiteralPath $pt).Hash -ne $expectedTableSHA) {
    throw "Actual partition layout mismatch, refuse OTA switch"
  }
  ReadFlash "0x110000" "0x1000" $ota0Head
  $headerCode = @'
import sys
f=open(sys.argv[1],"rb").read()
if len(f)!=4096 or f[0]!=0xe9:sys.exit("OTA0_IMG_HEADER_MISSING")
print("OTA0_HEADER_PRESENT")
'@
  & python -c $headerCode $ota0Head
  if ($LASTEXITCODE -ne 0) { throw "OTA0 no longer has a valid magic/header; refuse switch" }

  Write-Host "WRITE: otadata switch to OTA0. OTA0 image and all other partitions untouched."
  & python $otaTool --port $Port --baud 115200 switch_ota_partition --slot 0
  if ($LASTEXITCODE -ne 0) { throw "OTA0 switch failed; inspect device status." }
  ReadFlash "0x10D000" "0x2000" $after
  $verify = @'
import runpy,sys
m=runpy.run_path(sys.argv[1])
d=open(sys.argv[2],"rb").read()
if len(d)!=8192:sys.exit("OTADATA_TRUNCATED")
e=[m["ota_entry"](d,i) for i in (0,1)]
slot,_=m["candidate_ota"](e)
if slot!="ota_0":sys.exit("OTA0_ROLLBACK_VERIFY_FAILED: "+slot)
print("OTA0_BOOT_SELECTION_PASS")
'@
  & python -c $verify $inspector $after
  if ($LASTEXITCODE -ne 0) { throw "OTA0 selection verify failed" }
  Write-Host "ROLLBACK_OTA0_PASS. Reboot and confirm Bootloader selects 0x110000."
} finally {
  Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
