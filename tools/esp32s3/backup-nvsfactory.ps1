[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Port,
    [int]$Baud = 2000000
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot '..\setup\common.ps1')
$repoRoot = Get-PibbiRepoRoot
$config = Get-Esp32S3ToolConfig

. (Join-Path $repoRoot 'tools\setup\activate-esp32s3.ps1')

# These values follow Seeed's factory_firmware installation guide. The upstream
# partition is named nvsfactory and is documented as critical factory data.
$offset = 0x9000
$size = 204800
$runId = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')
$artifactRoot = Join-Path $repoRoot (Join-Path 'artifacts\esp32s3\nvsfactory-backup' $runId)
New-Item -ItemType Directory -Force -Path $artifactRoot | Out-Null
$backupPath = Join-Path $artifactRoot 'nvsfactory.bin'

Write-Host 'Backing up critical Watcher nvsfactory partition.'
Write-Host ('Offset : 0x{0:X}' -f $offset)
Write-Host "Size   : $size bytes"
Write-Host "Port   : $Port"
Write-Host "Baud   : $Baud"
Write-Host ''

& python -m esptool --chip $config.EspIdf.Target --port $Port --baud $Baud --before default_reset --after hard_reset --no-stub read_flash ('0x{0:X}' -f $offset) $size $backupPath
if ($LASTEXITCODE -ne 0) {
    throw "nvsfactory backup failed with exit code $LASTEXITCODE"
}

$actualSize = (Get-Item -LiteralPath $backupPath).Length
if ($actualSize -ne $size) {
    throw "nvsfactory backup size mismatch. Expected $size bytes, got $actualSize"
}

$sha256 = (Get-FileHash -LiteralPath $backupPath -Algorithm SHA256).Hash.ToLowerInvariant()
$manifest = [ordered]@{
    SchemaVersion = 1
    Platform = 'esp32s3'
    Partition = 'nvsfactory'
    Offset = ('0x{0:X}' -f $offset)
    SizeBytes = $size
    Port = $Port
    Baud = $Baud
    Sha256 = $sha256
    BackedUpAtUtc = [DateTime]::UtcNow.ToString('o')
    EspIdfVersion = $config.EspIdf.Version
    EspIdfCommit = $config.EspIdf.Commit
}
$manifestPath = Join-Path $artifactRoot 'backup-manifest.json'
$manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

Write-Host ''
Write-Host 'nvsfactory backup complete.'
Write-Host "Image   : $backupPath"
Write-Host "SHA-256 : $sha256"
Write-Host "Manifest: $manifestPath"
