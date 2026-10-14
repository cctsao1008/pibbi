[CmdletBinding()]
param(
    [string]$Example = 'pibbi',
    [switch]$Clean
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot '..\setup\common.ps1')

$repoRoot = Get-PibbiRepoRoot
$config = Get-Esp32S3ToolConfig
$watcherRoot = Join-Path $repoRoot $config.WatcherFirmware.Directory
# Build pibbi-owned firmware without editing upstream sources.
$projectRoot = if ($Example -eq 'pibbi') {
    Join-Path $repoRoot 'firmware\esp32s3'
}
else {
    Join-Path $watcherRoot (Join-Path 'examples' $Example)
}

if (-not (Test-Path -LiteralPath $projectRoot -PathType Container)) {
    throw "Watcher example not found: $projectRoot"
}
if (-not (Test-Path -LiteralPath (Join-Path $projectRoot 'CMakeLists.txt') -PathType Leaf)) {
    throw "Not an ESP-IDF project: $projectRoot"
}

# Activate only inside this PowerShell process. Callers do not need to prepare an ESP-IDF shell.
. (Join-Path $repoRoot 'tools\setup\activate-esp32s3.ps1')

$watcherHead = (& git -C $watcherRoot rev-parse HEAD).Trim()
$idfHead = (& git -C $env:IDF_PATH rev-parse HEAD).Trim()
if ($idfHead -ne $config.EspIdf.Commit) {
    throw "ESP-IDF pin mismatch. Expected $($config.EspIdf.Commit), got $idfHead"
}

$shortSha = $watcherHead.Substring(0, 12)
$artifactRoot = Join-Path $repoRoot (Join-Path 'artifacts\esp32s3\build' (Join-Path $shortSha $Example))
$buildRoot = Join-Path $artifactRoot 'build'
if ($Clean -and (Test-Path -LiteralPath $buildRoot)) {
    Remove-Item -LiteralPath $buildRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $artifactRoot | Out-Null

if ($Example -eq 'pibbi') {
    $prepareOverlay = Join-Path $repoRoot 'tools\esp32s3\prepare-vendor-overlay.py'
    $upstreamMain = Join-Path $watcherRoot 'examples\factory_firmware\main'
    $overlayMain = Join-Path $projectRoot 'vendor_overlay\main'

    & python $prepareOverlay --source $upstreamMain --output $overlayMain
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to prepare pibbi-owned vendor overlay (exit $LASTEXITCODE)"
    }
}

# idf.py v5.2.1 mirrors Ninja stdout/stderr through Python TextIO.
# With Windows legacy code page 950, a non-CP950 build message raises
# UnicodeEncodeError and hides the child process' actual build result.
# Override Python stream encoding for this invocation, including CMake/Ninja
# Python subprocesses, without changing the user's global locale.
# esp-sr's bare COMMAND python is resolved in the project's CMakeLists.txt
# through an IMPORTED executable target with an absolute interpreter path.
$pythonEnvRoot = [Environment]::GetEnvironmentVariable('IDF_PYTHON_ENV_PATH', 'Process')
if ([string]::IsNullOrWhiteSpace($pythonEnvRoot)) {
    throw "ESP-IDF export did not set IDF_PYTHON_ENV_PATH"
}
$idfPythonExe = Join-Path $pythonEnvRoot 'Scripts\python.exe'
if (-not (Test-Path -LiteralPath $idfPythonExe -PathType Leaf)) {
    throw "ESP-IDF Python executable missing: $idfPythonExe"
}

$oldTarget = [Environment]::GetEnvironmentVariable('IDF_TARGET', 'Process')
$oldPythonIoEncoding = [Environment]::GetEnvironmentVariable('PYTHONIOENCODING', 'Process')
try {
    $env:IDF_TARGET = $config.EspIdf.Target
    $env:PYTHONIOENCODING = 'utf-8'

    # Check the actual interpreter CMake will inject into ESP-SR's model rule.
    & $idfPythonExe --version
    if ($LASTEXITCODE -ne 0) {
        throw "ESP-IDF Python failed to run: $idfPythonExe"
    }

    Push-Location $projectRoot
    try {
        idf.py -B $buildRoot build
        if ($LASTEXITCODE -ne 0) {
            throw "idf.py build failed with exit code $LASTEXITCODE"
        }
    }
    finally {
        Pop-Location
    }
}
finally {
    if ($null -eq $oldTarget) {
        Remove-Item Env:IDF_TARGET -ErrorAction SilentlyContinue
    }
    else {
        $env:IDF_TARGET = $oldTarget
    }
    if ($null -eq $oldPythonIoEncoding) {
        Remove-Item Env:PYTHONIOENCODING -ErrorAction SilentlyContinue
    }
    else {
        $env:PYTHONIOENCODING = $oldPythonIoEncoding
    }
}

$elf = Get-ChildItem -LiteralPath $buildRoot -Filter '*.elf' -File | Select-Object -First 1
$appBin = Get-ChildItem -LiteralPath $buildRoot -Filter '*.bin' -File | Select-Object -First 1
$flashAppArgsPath = Join-Path $buildRoot 'flash_app_args'
if (-not $elf) { throw "Build completed but no application ELF was found in $buildRoot" }
if (-not $appBin) { throw "Build completed but no application BIN was found in $buildRoot" }
if (-not (Test-Path -LiteralPath $flashAppArgsPath -PathType Leaf)) { throw "Build completed but flash_app_args was not found in $buildRoot" }

$manifest = [ordered]@{
    SchemaVersion = 1
    Platform = 'esp32s3'
    Target = $config.EspIdf.Target
    Example = $Example
    WatcherRepository = $config.WatcherFirmware.Url
    WatcherCommit = $watcherHead
    EspIdfVersion = $config.EspIdf.Version
    EspIdfCommit = $idfHead
    BuiltAtUtc = [DateTime]::UtcNow.ToString('o')
    Elf = [ordered]@{
        Path = $elf.Name
        Size = $elf.Length
        Sha256 = (Get-FileHash -LiteralPath $elf.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    ApplicationBin = [ordered]@{
        Path = $appBin.Name
        Size = $appBin.Length
        Sha256 = (Get-FileHash -LiteralPath $appBin.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    FlashAppArgs = 'build\flash_app_args'
}

$manifestPath = Join-Path $artifactRoot 'build-manifest.json'
$manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

Write-Host ''
Write-Host 'ESP32-S3 build complete.'
Write-Host "Example : $Example"
Write-Host "Build   : $buildRoot"
Write-Host "ELF SHA : $($manifest.Elf.Sha256)"
Write-Host "BIN SHA : $($manifest.ApplicationBin.Sha256)"
Write-Host "Manifest: $manifestPath"
