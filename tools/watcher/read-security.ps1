# Watcher B2b: read-only ESP32-S3 ROM security status.
# NO efuse write, flash write/erase, flash content backup or firmware change.
# The ROM downloader connection may reset the unit; capture factory boot timing first when feasible.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidatePattern('^COM[0-9]+$')]
    [string]$Port
)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not $env:IDF_PATH) {
    throw "Activate the same ESP-IDF v5.2.1 PowerShell environment used for builds."
}
if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
    throw "Python missing from active ESP-IDF environment."
}
$ver = ((& idf.py --version 2>&1) | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $ver -notmatch '\bv5\.2\.1\b') {
    throw "Expected ESP-IDF v5.2.1, got: $ver"
}
Write-Host "WATCHER B2b READ-ONLY SECURITY CHECK: $Port"
Write-Host "ROM no-stub get_security_info only. Device may reset."
Write-Host "No flash reads, writes/erases, efuse burn or keys requested."
Write-Host "Redact any MAC / unique identifiers before sharing output."

# esp32s3 GET_SECURITY_INFO is a ROM read-only request.
# --no-stub: do not load RAM flasher. No secret key block reads.
& python -m esptool --chip esp32s3 --port $Port --baud 115200 --no-stub get_security_info
if ($LASTEXITCODE -ne 0) {
    throw "B2b security query failed; STOP. Do not flash or burn eFuses."
}
Write-Host "READ_ONLY_SECURITY_QUERY_PASS (inspect flags, not flashing approval)"
