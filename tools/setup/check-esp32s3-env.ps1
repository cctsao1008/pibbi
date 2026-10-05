[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$script:RequiredFailures = 0
$script:Warnings = 0

. (Join-Path $PSScriptRoot 'common.ps1')

$repoRoot = Get-PibbiRepoRoot
$config = Get-Esp32S3ToolConfig
$idfRoot = Join-Path $repoRoot $config.EspIdf.Directory
$idfToolsRoot = Join-Path $repoRoot $config.EspIdfTools.Directory
$watcherRoot = Join-Path $repoRoot $config.WatcherFirmware.Directory

function Write-CheckResult {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('PASS', 'WARN', 'FAIL')][string]$Status,
        [Parameter(Mandatory = $true)][string]$Name,
        [string]$Detail = ''
    )

    if ($Status -eq 'FAIL') { $script:RequiredFailures++ }
    if ($Status -eq 'WARN') { $script:Warnings++ }

    if ([string]::IsNullOrWhiteSpace($Detail)) {
        Write-Host ('[{0}] {1}' -f $Status, $Name)
    }
    else {
        Write-Host ('[{0}] {1}: {2}' -f $Status, $Name, $Detail)
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

Write-Host 'pibbi ESP32-S3 development environment check'
Write-Host ''

$git = Get-Command git -ErrorAction SilentlyContinue
if ($git) {
    $gitVersion = (& $git.Source --version 2>&1 | Select-Object -First 1).ToString()
    Write-CheckResult PASS 'Git' $gitVersion
}
else {
    Write-CheckResult FAIL 'Git' 'git was not found in PATH'
}

$python = Get-PythonLauncher
if ($python) {
    $pythonVersionText = (& $python.Path @($python.PrefixArgs + @('--version')) 2>&1 | Select-Object -First 1).ToString()
    if ($pythonVersionText -match 'Python\s+(\d+)\.(\d+)(?:\.(\d+))?') {
        $detected = [version](('{0}.{1}' -f $Matches[1], $Matches[2]))
        $minimum = [version]$config.Python.MinimumVersion
        if ($detected -ge $minimum) {
            Write-CheckResult PASS 'Python' $pythonVersionText
        }
        else {
            Write-CheckResult FAIL 'Python' "$pythonVersionText; >= $minimum is required"
        }
    }
    else {
        Write-CheckResult FAIL 'Python' "unable to parse version: $pythonVersionText"
    }

    $pipText = (& $python.Path @($python.PrefixArgs + @('-m', 'pip', '--version')) 2>&1 | Select-Object -First 1).ToString()
    if ($LASTEXITCODE -eq 0 -and $pipText -match '^pip\s+') {
        Write-CheckResult PASS 'pip' $pipText
    }
    else {
        Write-CheckResult FAIL 'pip' 'python -m pip is unavailable'
    }
}
else {
    Write-CheckResult FAIL 'Python' 'Python 3 was not found'
    Write-CheckResult FAIL 'pip' 'Python is unavailable'
}

if (-not (Test-Path -LiteralPath $idfRoot -PathType Container)) {
    Write-CheckResult FAIL 'ESP-IDF checkout' "not found: $idfRoot"
}
elseif (-not (Test-Path -LiteralPath (Join-Path $idfRoot '.git'))) {
    Write-CheckResult FAIL 'ESP-IDF checkout' "not a Git checkout: $idfRoot"
}
else {
    $idfHead = (& git -C $idfRoot rev-parse HEAD 2>$null).Trim()
    if ($idfHead -eq $config.EspIdf.Commit) {
        Write-CheckResult PASS 'ESP-IDF pin' "$($config.EspIdf.Version) @ $idfHead"
    }
    else {
        Write-CheckResult FAIL 'ESP-IDF pin' "expected $($config.EspIdf.Commit); detected $idfHead"
    }

    $idfDirty = @(& git -C $idfRoot status --porcelain 2>$null)
    if ($idfDirty.Count -eq 0) {
        Write-CheckResult PASS 'ESP-IDF working tree' 'clean'
    }
    else {
        Write-CheckResult WARN 'ESP-IDF working tree' 'local modifications detected'
    }

    $submodules = @(& git -C $idfRoot submodule status --recursive 2>$null)
    $badSubmodules = @($submodules | Where-Object { $_ -match '^[+-]' })
    if ($LASTEXITCODE -ne 0) {
        Write-CheckResult FAIL 'ESP-IDF submodules' 'git submodule status failed'
    }
    elseif ($badSubmodules.Count -gt 0) {
        Write-CheckResult FAIL 'ESP-IDF submodules' "$($badSubmodules.Count) uninitialized or mismatched submodule(s)"
    }
    else {
        Write-CheckResult PASS 'ESP-IDF submodules' 'initialized at recorded revisions'
    }
}

if (Test-Path -LiteralPath $idfToolsRoot -PathType Container) {
    Write-CheckResult PASS 'IDF_TOOLS_PATH' $idfToolsRoot
}
else {
    Write-CheckResult FAIL 'IDF_TOOLS_PATH' "repository-local tools not found: $idfToolsRoot"
}

if ($python -and (Test-Path -LiteralPath (Join-Path $idfRoot 'tools\idf_tools.py') -PathType Leaf) -and (Test-Path -LiteralPath $idfToolsRoot -PathType Container)) {
    $oldIdfToolsPath = $env:IDF_TOOLS_PATH
    try {
        $env:IDF_TOOLS_PATH = $idfToolsRoot
        $toolOutput = & $python.Path @($python.PrefixArgs + @((Join-Path $idfRoot 'tools\idf_tools.py'), 'check')) 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-CheckResult PASS 'ESP-IDF managed tools' 'idf_tools.py check passed'
        }
        else {
            $detail = (($toolOutput | ForEach-Object { $_.ToString() }) -join ' ').Trim()
            Write-CheckResult FAIL 'ESP-IDF managed tools' $detail
        }
    }
    finally {
        if ($null -eq $oldIdfToolsPath) {
            Remove-Item Env:IDF_TOOLS_PATH -ErrorAction SilentlyContinue
        }
        else {
            $env:IDF_TOOLS_PATH = $oldIdfToolsPath
        }
    }
}

if ($config.EspIdf.Target -eq 'esp32s3') {
    Write-CheckResult PASS 'ESP-IDF target' $config.EspIdf.Target
}
else {
    Write-CheckResult FAIL 'ESP-IDF target' "expected esp32s3; configured $($config.EspIdf.Target)"
}

if (-not (Test-Path -LiteralPath $watcherRoot -PathType Container)) {
    Write-CheckResult FAIL 'SenseCAP Watcher firmware' "not found: $watcherRoot"
}
elseif (-not (Test-Path -LiteralPath (Join-Path $watcherRoot '.git'))) {
    Write-CheckResult FAIL 'SenseCAP Watcher firmware' "not a Git checkout: $watcherRoot"
}
else {
    $watcherHead = (& git -C $watcherRoot rev-parse HEAD 2>$null).Trim()
    $watcherBranch = (& git -C $watcherRoot branch --show-current 2>$null).Trim()
    Write-CheckResult PASS 'SenseCAP Watcher firmware' "HEAD $watcherHead"

    if (-not [string]::IsNullOrWhiteSpace($config.WatcherFirmware.Commit)) {
        if ($watcherHead -eq $config.WatcherFirmware.Commit) {
            Write-CheckResult PASS 'Watcher firmware pin' $watcherHead
        }
        else {
            Write-CheckResult FAIL 'Watcher firmware pin' "expected $($config.WatcherFirmware.Commit); detected $watcherHead"
        }
    }
    elseif ($watcherBranch -eq $config.WatcherFirmware.Track) {
        Write-CheckResult WARN 'Watcher firmware pin' "tracking $watcherBranch until hardware baseline validation"
    }
    else {
        Write-CheckResult WARN 'Watcher firmware pin' "not pinned; branch '$watcherBranch', expected '$($config.WatcherFirmware.Track)'"
    }

    $watcherDirty = @(& git -C $watcherRoot status --porcelain 2>$null)
    if ($watcherDirty.Count -eq 0) {
        Write-CheckResult PASS 'Watcher firmware working tree' 'clean'
    }
    else {
        Write-CheckResult WARN 'Watcher firmware working tree' 'local modifications detected'
    }
}

Write-Host ''
if ($script:RequiredFailures -gt 0) {
    Write-Host ("Environment check failed: {0} required check(s) failed; {1} warning(s)." -f $script:RequiredFailures, $script:Warnings)
    exit 1
}
if ($script:Warnings -gt 0) {
    Write-Host ("Environment check passed with {0} warning(s)." -f $script:Warnings)
}
else {
    Write-Host 'Environment check passed.'
}
exit 0
