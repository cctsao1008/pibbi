# B2c: read-only full ESP32-S3 flash backup (NOT Himax).
# The image contains unique device credentials and identities: NEVER upload.
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][ValidatePattern('^COM[0-9]+$')][string]$Port,
  [Parameter(Mandatory=$true)][string]$OutputDir
)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$expectedPartitionSHA = "535EA803C19353B47BACEA78DE4642692920CD925402233666FF9E7EB9189D73"
if (-not $env:IDF_PATH) { throw "Activate ESP-IDF v5.2.1 first." }
$v = ((& idf.py --version 2>&1) | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $v -notmatch '\bv5\.2\.1\b') { throw "ESP-IDF v5.2.1 required, found: $v" }
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\..")).TrimEnd('\','/')
$destRoot = [IO.Path]::GetFullPath($OutputDir).TrimEnd('\','/')
if ($destRoot.Equals($repoRoot,[StringComparison]::OrdinalIgnoreCase) -or $destRoot.StartsWith($repoRoot + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) {
  throw "Refusing backup inside pibbi repo. Choose an encrypted local folder outside Git and cloud sync."
}
$dir = Join-Path $destRoot ("watcher-private-" + (Get-Date -Format "yyyyMMdd-HHmmss-fff"))
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$part = Join-Path $dir "partition-table.bin"
$whole = Join-Path $dir "esp32s3-full-32MiB-PRIVATE.bin"
$nvs = Join-Path $dir "nvsfactory-PRIVATE.bin"
$ota = Join-Path $dir "otadata-PRIVATE.bin"
$manifestPath = Join-Path $dir "manifest-PRIVATE.json"
Write-Host "B2c READ ONLY: $Port to $dir"
Write-Host "This may reset Watcher and may take several minutes. Power and USB must be stable."
Write-Host "Warning: this full 32 MiB raw backup includes factory secrets; DO NOT SHARE OR SYNC."
Write-Host "Only flash read commands; no erase, write or efuse modifications."

function ReadFlash([string]$offset, [string]$size, [string]$path) {
  & python -m esptool --chip esp32s3 --port $Port --baud 460800 read_flash $offset $size $path
  if ($LASTEXITCODE -ne 0) { throw "Read failed at offset $offset. STOP." }
}
ReadFlash "0x8000" "0x1000" $part
if ((Get-Item -LiteralPath $part).Length -ne 4096) { throw "Partition read length mismatch. STOP." }
$partSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $part).Hash
if ($partSha -ne $expectedPartitionSHA) { throw "Device partition SHA mismatch. STOP; this is not the verified layout." }

ReadFlash "0x0" "0x2000000" $whole
if ((Get-Item -LiteralPath $whole).Length -ne 33554432) { throw "Incomplete 32 MiB Flash image. STOP." }
ReadFlash "0x9000" "0x32000" $nvs
ReadFlash "0x10D000" "0x2000" $ota
if ((Get-Item -LiteralPath $nvs).Length -ne 204800 -or (Get-Item -LiteralPath $ota).Length -ne 8192) {
  throw "Independent NVS or OTA read length mismatch. STOP."
}
$verifyCode = @'
import sys
big, *parts = sys.argv[1:]
with open(big, "rb") as main:
    for offset, path in ((0x8000, parts[0]), (0x9000, parts[1]), (0x10D000, parts[2])):
        with open(path, "rb") as f:
            expected = f.read()
        main.seek(offset)
        if main.read(len(expected)) != expected:
            sys.exit("VERIFY FAILED at offset 0x%X" % offset)
print("INDEPENDENT_REGION_COMPARE_PASS (partition, nvsfactory, otadata)")
'@
& python -c $verifyCode $whole $part $nvs $ota
if ($LASTEXITCODE -ne 0) { throw "Full image differs from independent partition read. STOP." }
$fullSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $whole).Hash
$manifest = [ordered]@{
  status = "READ_ONLY_BACKUP_PASS"
  captured_local = (Get-Date).ToString("o")
  full_flash_filename = (Split-Path $whole -Leaf)
  bytes = 33554432
  full_flash_sha256 = $fullSha
  partition_sha256 = $partSha
  nvsfactory_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $nvs).Hash
  otadata_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $ota).Hash
  independent_region_match = "PASS"
  notes = "ESP32-S3 backup only, NOT HX6538. Factory credentials inside: keep private. No restore tested; no flash approved."
}
$manifest | ConvertTo-Json -Depth 4 | Set-Content -Encoding UTF8 -LiteralPath $manifestPath
Write-Host "READ_ONLY_BACKUP_PASS"
Write-Host "Full Flash: 33554432 bytes"
Write-Host "Full Flash SHA256: $fullSha"
Write-Host "Partition/NVS/OTA cross-check: PASS"
Write-Host "Private local manifest: $manifestPath"
Write-Host "This is a backup integrity check, not proof of successful restore or permission to flash."
