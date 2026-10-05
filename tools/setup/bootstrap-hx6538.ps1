[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$UpdateSdk
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'common.ps1')

$repoRoot = Get-PibbiRepoRoot
$config = Get-Hx6538ToolConfig
$toolsRoot = Join-Path $repoRoot '.tools'
$downloadRoot = Join-Path $toolsRoot 'downloads'
$thirdPartyRoot = Join-Path $repoRoot 'third_party'

function Write-Step {
    param([string]$Message)
    Write-Host ''
    Write-Host ('==> {0}' -f $Message)
}

function Get-FileSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Assert-Sha256 {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Expected
    )

    $actual = Get-FileSha256 -Path $Path
    if ($actual -ne $Expected.ToLowerInvariant()) {
        throw "SHA-256 mismatch for '$Path'. Expected $Expected, got $actual"
    }
}

function Get-Download {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    if ((Test-Path -LiteralPath $Destination -PathType Leaf) -and -not $Force) {
        Write-Host "Using cached download: $Destination"
        return
    }

    $parent = Split-Path -Parent $Destination
    New-Item -ItemType Directory -Force -Path $parent | Out-Null

    Write-Host "Downloading: $Uri"
    Invoke-WebRequest -Uri $Uri -OutFile $Destination
}

function Invoke-Git {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [string]$WorkingDirectory = $repoRoot
    )

    Push-Location $WorkingDirectory
    try {
        & git @Arguments
        if ($LASTEXITCODE -ne 0) {
            throw "git command failed ($LASTEXITCODE): git $($Arguments -join ' ')"
        }
    }
    finally {
        Pop-Location
    }
}

New-Item -ItemType Directory -Force -Path $toolsRoot, $downloadRoot, $thirdPartyRoot | Out-Null

if (-not (Get-Command 'git' -ErrorAction SilentlyContinue)) {
    throw 'Git is required before bootstrap can continue.'
}

if ($PSVersionTable.PSEdition -eq 'Desktop') {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
}

Write-Step 'Provision Arm GNU Toolchain for HX6538'
$armRoot = Join-Path $toolsRoot $config.ArmGnuToolchain.Directory
$armGcc = Join-Path $armRoot 'bin\arm-none-eabi-gcc.exe'

if (-not (Test-Path -LiteralPath $armGcc -PathType Leaf)) {
    $armArchive = Join-Path $downloadRoot $config.ArmGnuToolchain.Archive
    Get-Download -Uri $config.ArmGnuToolchain.Url -Destination $armArchive
    Assert-Sha256 -Path $armArchive -Expected $config.ArmGnuToolchain.Sha256

    if (Test-Path -LiteralPath $armRoot) {
        if (-not $Force) {
            throw "Incomplete Arm toolchain directory already exists: $armRoot. Re-run with -Force to replace it."
        }
        Remove-Item -LiteralPath $armRoot -Recurse -Force
    }

    Expand-Archive -LiteralPath $armArchive -DestinationPath $toolsRoot -Force
}
else {
    Write-Host "Already present: $armRoot"
}

if (-not (Test-Path -LiteralPath $armGcc -PathType Leaf)) {
    throw "Arm toolchain extraction did not produce expected executable: $armGcc"
}

$armVersion = (& $armGcc --version 2>&1 | Select-Object -First 1).ToString()
if (-not ($armVersion -match [regex]::Escape($config.ArmGnuToolchain.Version))) {
    throw "Unexpected project-local Arm toolchain version: $armVersion"
}
Write-Host "Verified: $armVersion"

Write-Step 'Provision GNU Make via xPack Windows Build Tools'
$buildToolsRoot = Join-Path $toolsRoot $config.WindowsBuildTools.Directory
$makeExe = Join-Path $buildToolsRoot 'bin\make.exe'

if (-not (Test-Path -LiteralPath $makeExe -PathType Leaf)) {
    $buildArchive = Join-Path $downloadRoot $config.WindowsBuildTools.Archive
    $buildShaFile = "$buildArchive.sha"

    Get-Download -Uri $config.WindowsBuildTools.Url -Destination $buildArchive
    Get-Download -Uri $config.WindowsBuildTools.ShaUrl -Destination $buildShaFile

    $shaText = Get-Content -LiteralPath $buildShaFile -Raw
    $shaMatch = [regex]::Match($shaText, '(?i)\b[0-9a-f]{64}\b')
    if (-not $shaMatch.Success) {
        throw "Could not find a SHA-256 checksum in $buildShaFile"
    }
    Assert-Sha256 -Path $buildArchive -Expected $shaMatch.Value

    if (Test-Path -LiteralPath $buildToolsRoot) {
        if (-not $Force) {
            throw "Incomplete xPack directory already exists: $buildToolsRoot. Re-run with -Force to replace it."
        }
        Remove-Item -LiteralPath $buildToolsRoot -Recurse -Force
    }

    Expand-Archive -LiteralPath $buildArchive -DestinationPath $toolsRoot -Force
}
else {
    Write-Host "Already present: $buildToolsRoot"
}

if (-not (Test-Path -LiteralPath $makeExe -PathType Leaf)) {
    throw "xPack extraction did not produce expected executable: $makeExe"
}

$makeVersion = (& $makeExe --version 2>&1 | Select-Object -First 1).ToString()
if (-not ($makeVersion -match '^GNU Make\s+')) {
    throw "Unexpected make implementation: $makeVersion"
}
Write-Host "Verified: $makeVersion"

Write-Step 'Provision Seeed/Himax HX6538 SDK'
$sdkPath = Join-Path $repoRoot $config.SscmaWe2.Directory
$sdkParent = Split-Path -Parent $sdkPath
New-Item -ItemType Directory -Force -Path $sdkParent | Out-Null

if (-not (Test-Path -LiteralPath $sdkPath -PathType Container)) {
    Invoke-Git -Arguments @(
        'clone',
        '--recursive',
        '--branch', $config.SscmaWe2.Track,
        $config.SscmaWe2.Url,
        $sdkPath
    )
}
elseif (-not (Test-Path -LiteralPath (Join-Path $sdkPath '.git'))) {
    throw "SDK path exists but is not a Git checkout: $sdkPath"
}
else {
    Write-Host "Already present: $sdkPath"
}

$sdkDirty = (& git -C $sdkPath status --porcelain)
if ($sdkDirty -and ($UpdateSdk -or -not [string]::IsNullOrWhiteSpace($config.SscmaWe2.Commit))) {
    throw 'SDK working tree has local changes. Refusing to change its revision.'
}

if (-not [string]::IsNullOrWhiteSpace($config.SscmaWe2.Commit)) {
    Invoke-Git -Arguments @('-C', $sdkPath, 'fetch', 'origin', $config.SscmaWe2.Commit)
    Invoke-Git -Arguments @('-C', $sdkPath, 'checkout', '--detach', $config.SscmaWe2.Commit)
}
elseif ($UpdateSdk) {
    Invoke-Git -Arguments @('-C', $sdkPath, 'fetch', 'origin', $config.SscmaWe2.Track)
    Invoke-Git -Arguments @('-C', $sdkPath, 'checkout', $config.SscmaWe2.Track)
    Invoke-Git -Arguments @('-C', $sdkPath, 'merge', '--ff-only', "origin/$($config.SscmaWe2.Track)")
}

Invoke-Git -Arguments @('-C', $sdkPath, 'submodule', 'update', '--init', '--recursive')

$sdkHead = (& git -C $sdkPath rev-parse HEAD).Trim()
Write-Host "SDK HEAD: $sdkHead"
if ([string]::IsNullOrWhiteSpace($config.SscmaWe2.Commit)) {
    Write-Warning 'The SDK is intentionally not pinned yet. Pin this exact commit after the first clean build and Watcher smoke test pass.'
}

Write-Step 'Validate complete HX6538 environment'
& (Join-Path $PSScriptRoot 'check-hx6538-env.ps1')
if ($LASTEXITCODE -ne 0) {
    throw "HX6538 environment validation failed with exit code $LASTEXITCODE"
}

Write-Host ''
Write-Host 'Bootstrap complete.'
Write-Host 'For an interactive shell using the pibbi-local tools, dot-source:'
Write-Host '  . .\tools\setup\activate-hx6538.ps1'
