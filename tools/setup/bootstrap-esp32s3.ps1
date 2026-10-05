[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$UpdateWatcher,
    [string]$GitHubAssetsHost = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'common.ps1')

$repoRoot = Get-PibbiRepoRoot
$config = Get-Esp32S3ToolConfig
$idfRoot = Join-Path $repoRoot $config.EspIdf.Directory
$idfToolsRoot = Join-Path $repoRoot $config.EspIdfTools.Directory
$watcherRoot = Join-Path $repoRoot $config.WatcherFirmware.Directory
$thirdPartyRoot = Join-Path $repoRoot 'third_party'

function Write-Step {
    param([string]$Message)
    Write-Host ''
    Write-Host ('==> {0}' -f $Message)
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

function Get-PythonLauncher {
    try {
        $python = Get-Command python -ErrorAction Stop
        return [pscustomobject]@{ Path = $python.Source; PrefixArgs = @() }
    }
    catch {
        try {
            $py = Get-Command py -ErrorAction Stop
            return [pscustomobject]@{ Path = $py.Source; PrefixArgs = @('-3') }
        }
        catch {
            return $null
        }
    }
}

function Invoke-Python {
    param(
        [Parameter(Mandatory = $true)]$Launcher,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    & $Launcher.Path @($Launcher.PrefixArgs + $Arguments)
    if ($LASTEXITCODE -ne 0) {
        throw "Python command failed ($LASTEXITCODE): $($Arguments -join ' ')"
    }
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw 'Git is required before bootstrap can continue.'
}

$python = Get-PythonLauncher
if (-not $python) {
    throw 'Python 3 is required before bootstrap can continue.'
}

$pythonVersionText = (& $python.Path @($python.PrefixArgs + @('--version')) 2>&1 | Select-Object -First 1).ToString()
if (-not ($pythonVersionText -match 'Python\s+(\d+)\.(\d+)(?:\.(\d+))?')) {
    throw "Unable to determine Python version: $pythonVersionText"
}
$pythonVersion = [version](('{0}.{1}' -f $Matches[1], $Matches[2]))
$minimumPython = [version]$config.Python.MinimumVersion
if ($pythonVersion -lt $minimumPython) {
    throw "ESP-IDF requires Python >= $minimumPython; detected $pythonVersionText"
}

New-Item -ItemType Directory -Force -Path $thirdPartyRoot, (Split-Path -Parent $idfToolsRoot) | Out-Null

Write-Step "Provision ESP-IDF $($config.EspIdf.Version)"
if (-not (Test-Path -LiteralPath $idfRoot -PathType Container)) {
    Invoke-Git -Arguments @(
        'clone', '--recursive', '--branch', $config.EspIdf.Version,
        $config.EspIdf.Url, $idfRoot
    )
}
elseif (-not (Test-Path -LiteralPath (Join-Path $idfRoot '.git'))) {
    throw "ESP-IDF path exists but is not a Git checkout: $idfRoot"
}

$idfDirty = @(& git -C $idfRoot status --porcelain)
$idfHead = (& git -C $idfRoot rev-parse HEAD).Trim()
if ($idfHead -ne $config.EspIdf.Commit) {
    if ($idfDirty.Count -gt 0) {
        throw 'ESP-IDF working tree has local changes. Refusing to change its revision.'
    }
    Invoke-Git -Arguments @('-C', $idfRoot, 'fetch', 'origin', $config.EspIdf.Commit)
    Invoke-Git -Arguments @('-C', $idfRoot, 'checkout', '--detach', $config.EspIdf.Commit)
}

Invoke-Git -Arguments @('-C', $idfRoot, 'submodule', 'update', '--init', '--recursive')
$idfHead = (& git -C $idfRoot rev-parse HEAD).Trim()
if ($idfHead -ne $config.EspIdf.Commit) {
    throw "ESP-IDF pin mismatch after checkout. Expected $($config.EspIdf.Commit), got $idfHead"
}
Write-Host "ESP-IDF HEAD: $idfHead"

Write-Step 'Provision repository-local ESP-IDF tools'
if ($Force -and (Test-Path -LiteralPath $idfToolsRoot)) {
    Write-Host "Removing repository-local ESP-IDF tools: $idfToolsRoot"
    Remove-Item -LiteralPath $idfToolsRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $idfToolsRoot | Out-Null

# ESP-IDF can rewrite GitHub release-asset URLs to an Espressif download host
# through IDF_GITHUB_ASSETS. Prefer an explicit command-line override, then an
# existing caller environment, then pibbi's repository policy.
$effectiveGitHubAssetsHost = $GitHubAssetsHost
if ([string]::IsNullOrWhiteSpace($effectiveGitHubAssetsHost)) {
    if (-not [string]::IsNullOrWhiteSpace($env:IDF_GITHUB_ASSETS)) {
        $effectiveGitHubAssetsHost = $env:IDF_GITHUB_ASSETS
    }
    elseif ($config.EspIdfTools.ContainsKey('GitHubAssetsHost')) {
        $effectiveGitHubAssetsHost = $config.EspIdfTools.GitHubAssetsHost
    }
}

$oldIdfToolsPath = $env:IDF_TOOLS_PATH
$oldGitHubAssets = $env:IDF_GITHUB_ASSETS
try {
    $env:IDF_TOOLS_PATH = $idfToolsRoot
    if (-not [string]::IsNullOrWhiteSpace($effectiveGitHubAssetsHost)) {
        $env:IDF_GITHUB_ASSETS = $effectiveGitHubAssetsHost
        Write-Host "ESP-IDF asset host: https://$effectiveGitHubAssetsHost"
    }

    $idfToolsPy = Join-Path $idfRoot 'tools\idf_tools.py'
    Invoke-Python -Launcher $python -Arguments @($idfToolsPy, 'install', "--targets=$($config.EspIdf.Target)")
    Invoke-Python -Launcher $python -Arguments @($idfToolsPy, 'install-python-env')
}
finally {
    if ($null -eq $oldIdfToolsPath) {
        Remove-Item Env:IDF_TOOLS_PATH -ErrorAction SilentlyContinue
    }
    else {
        $env:IDF_TOOLS_PATH = $oldIdfToolsPath
    }

    if ($null -eq $oldGitHubAssets) {
        Remove-Item Env:IDF_GITHUB_ASSETS -ErrorAction SilentlyContinue
    }
    else {
        $env:IDF_GITHUB_ASSETS = $oldGitHubAssets
    }
}

Write-Step 'Provision SenseCAP Watcher firmware source'
if (-not (Test-Path -LiteralPath $watcherRoot -PathType Container)) {
    Invoke-Git -Arguments @(
        'clone', '--recursive', '--branch', $config.WatcherFirmware.Track,
        $config.WatcherFirmware.Url, $watcherRoot
    )
}
elseif (-not (Test-Path -LiteralPath (Join-Path $watcherRoot '.git'))) {
    throw "Watcher firmware path exists but is not a Git checkout: $watcherRoot"
}

$watcherDirty = @(& git -C $watcherRoot status --porcelain)
if ($watcherDirty.Count -gt 0 -and ($UpdateWatcher -or -not [string]::IsNullOrWhiteSpace($config.WatcherFirmware.Commit))) {
    throw 'Watcher firmware working tree has local changes. Refusing to change its revision.'
}

if (-not [string]::IsNullOrWhiteSpace($config.WatcherFirmware.Commit)) {
    Invoke-Git -Arguments @('-C', $watcherRoot, 'fetch', 'origin', $config.WatcherFirmware.Commit)
    Invoke-Git -Arguments @('-C', $watcherRoot, 'checkout', '--detach', $config.WatcherFirmware.Commit)
}
elseif ($UpdateWatcher) {
    Invoke-Git -Arguments @('-C', $watcherRoot, 'fetch', 'origin', $config.WatcherFirmware.Track)
    Invoke-Git -Arguments @('-C', $watcherRoot, 'checkout', $config.WatcherFirmware.Track)
    Invoke-Git -Arguments @('-C', $watcherRoot, 'merge', '--ff-only', "origin/$($config.WatcherFirmware.Track)")
}

Invoke-Git -Arguments @('-C', $watcherRoot, 'submodule', 'update', '--init', '--recursive')
$watcherHead = (& git -C $watcherRoot rev-parse HEAD).Trim()
Write-Host "Watcher firmware HEAD: $watcherHead"
if ([string]::IsNullOrWhiteSpace($config.WatcherFirmware.Commit)) {
    Write-Warning 'Watcher firmware is intentionally not pinned yet. Pin the exact commit after build/flash/smoke validation.'
}

Write-Step 'Validate complete ESP32-S3 environment'
& (Join-Path $PSScriptRoot 'check-esp32s3-env.ps1')
if ($LASTEXITCODE -ne 0) {
    throw "ESP32-S3 environment validation failed with exit code $LASTEXITCODE"
}

Write-Host ''
Write-Host 'Bootstrap complete.'
Write-Host 'For an interactive shell using pibbi-local ESP-IDF tools, dot-source:'
Write-Host '  . .\tools\setup\activate-esp32s3.ps1'
