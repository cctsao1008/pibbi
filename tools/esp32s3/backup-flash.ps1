[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Port,
    [UInt64]$SizeBytes = 0,
    [int]$Baud = 2000000
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot '..\setup\common.ps1')
$repoRoot = Get-PibbiRepoRoot
$config = Get-Esp32S3ToolConfig

. (Join-Path $repoRoot 'tools\setup\activate-esp32s3.ps1')

$flashIdOutput = & python -m esptool --chip $config.EspIdf.Target --port $Port flash_id 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "Unable to query flash ID on $Port"
}
$flashIdText = (($flashIdOutput | ForEach-Object { $_.ToString() }) -join "`n").Trim()
Write-Host $flashIdText

if ($SizeBytes -eq 0) {
    $match = [regex]::Match($flashIdText, '(?im)Detected flash size:\s*(\d+)\s*(KB|MB)')
    if (-not $match.Success) {
        throw 'Could not determine flash size automatically. Re-run with -SizeBytes <bytes>.'
    }

    $value = [UInt64]$match.Groups[1].Value
    switch ($match.Groups[2].Value.ToUpperInvariant()) {
        'KB' { $SizeBytes = $value * 1KB }
        'MB' { $SizeBytes = $value * 1MB }
        default { throw "Unsupported flash size unit: $($match.Groups[2].Value)" }
    }
}

$runId = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')
$artifactRoot = Join-Path $repoRoot (Join-Path 'artifacts\esp32s3\factory-backup' $runId)
New-Item -ItemType Directory -Force -Path $artifactRoot | Out-Null
$flashPath = Join-Path $artifactRoot 'flash.bin'
$sizeHex = ('0x{0:X}' -f $SizeBytes)

Write-Host ''
Write-Host "Reading full flash: 0x0 .. $sizeHex"
Write-Host "Baud: $Baud"
& python -m esptool --chip $config.EspIdf.Target --port $Port --baud $Baud read_flash 0x0 $sizeHex $flashPath
if ($LASTEXITCODE -ne 0) {
    throw "Flash backup failed with exit code $LASTEXITCODE"
}

$actualSize = (Get-Item -LiteralPath $flashPath).Length
if ([UInt64]$actualSize -ne $SizeBytes) {
    throw "Backup size mismatch. Expected $SizeBytes bytes, got $actualSize"
}

$sha256 = (Get-FileHash -LiteralPath $flashPath -Algorithm SHA256).Hash.ToLowerInvariant()
$manifest = [ordered]@{
    SchemaVersion = 1
    Platform = 'esp32s3'
    Port = $Port
    Baud = $Baud
    SizeBytes = $SizeBytes
    Sha256 = $sha256
    BackedUpAtUtc = [DateTime]::UtcNow.ToString('o')
    EspIdfVersion = $config.EspIdf.Version
    EspIdfCommit = $config.EspIdf.Commit
    FlashIdOutput = $flashIdText
}
$manifestPath = Join-Path $artifactRoot 'backup-manifest.json'
$manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

Write-Host ''
Write-Host 'Flash backup complete.'
Write-Host "Image   : $flashPath"
Write-Host "Size    : $actualSize bytes"
Write-Host "SHA-256 : $sha256"
Write-Host "Manifest: $manifestPath"
