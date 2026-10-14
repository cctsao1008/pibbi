[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '..\setup\common.ps1')

$root = Get-PibbiRepoRoot
$config = Get-Hx6538ToolConfig
$native = Join-Path $root $config.SscmaWe2.Directory
$legacy = Join-Path $root '.tools\work\hx6538-sscma-legacy'
$app = Join-Path $legacy 'EPII_CM55M_APP_S'
$micro = Join-Path $app 'library\sscma_micro'
$elfRel = 'obj_epii_evb_icv30_bdv10\gnu_epii_evb_WLCSP65\EPII_CM55M_gnu_epii_evb_WLCSP65_s.elf'
$nativeSha = '3ac4e9f557f09fbe4e62806c2a19b5e8a23a9a70'
$legacySha = '37fed7a8e27b9d50f64b6784c3aff7bbf04cf70d'
$microSha = 'c90065ddd2d763728b0aa24902af9337922b94fb'

function GitRead([string]$directory, [string[]]$options) {
    $result = (& git -C $directory @options | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) { throw "Git command failed in $directory" }
    return $result
}
function AssertClean([string]$directory) {
    $status = GitRead $directory @('status', '--porcelain=v1', '--untracked-files=all')
    if ($status.Length -ne 0) {
        throw "Working tree not clean: $directory : $status"
    }
}
function RestoreKnownArchives([string]$directory) {
    $status = GitRead $directory @('status', '--porcelain=v1', '--untracked-files=all')
    if ($status.Length -eq 0) { return }
    $paths = @()
    foreach ($line in ($status -split '[\r\n]+')) {
        if (-not $line.StartsWith(' M ')) { throw "Unexpected modification: $line" }
        $path = $line.Substring(3).Trim('"')
        if ($path -notlike 'EPII_CM55M_APP_S/prebuilt_libs/gnu/*.a') {
            throw "Unexpected modification: $line"
        }
        $paths += $path
    }
    if ($paths.Count -gt 0) {
        & git -C $directory restore --worktree -- @paths
        if ($LASTEXITCODE -ne 0) { throw 'Cannot restore build-generated vendor archives.' }
        Write-Host ("Restored {0} known build-generated vendor archives." -f $paths.Count)
    }
}

foreach ($dir in @($native, $legacy, $app, $micro)) {
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
        throw "Missing checkout: $dir"
    }
}
if ((GitRead $native @('rev-parse', 'HEAD')) -ne $nativeSha) {
    throw 'Baseline Native SDK revision changed.'
}
if ((GitRead $legacy @('rev-parse', 'HEAD')) -ne $legacySha) {
    throw 'Legacy SSCMA SDK revision changed.'
}
if ((GitRead $micro @('rev-parse', 'HEAD')) -ne $microSha) {
    throw 'Legacy SSCMA-Micro revision changed.'
}
$gitlink = GitRead $legacy @('ls-tree', 'HEAD', '--', 'EPII_CM55M_APP_S/library/sscma_micro')
if (-not $gitlink.StartsWith("160000 commit $microSha")) {
    throw 'Legacy gitlink and checked-out submodule are inconsistent.'
}
AssertClean $native
AssertClean $legacy
AssertClean $micro

$make = Get-PibbiExecutable -RepoRoot $root -FileName 'make.exe' -PreferredDirectory $config.WindowsBuildTools.Directory -FallbackCommand 'make'
$gcc = Get-PibbiExecutable -RepoRoot $root -FileName 'arm-none-eabi-gcc.exe' -PreferredDirectory $config.ArmGnuToolchain.Directory -FallbackCommand 'arm-none-eabi-gcc'
$size = Get-PibbiExecutable -RepoRoot $root -FileName 'arm-none-eabi-size.exe' -PreferredDirectory $config.ArmGnuToolchain.Directory -FallbackCommand 'arm-none-eabi-size'
$readelf = Get-PibbiExecutable -RepoRoot $root -FileName 'arm-none-eabi-readelf.exe' -PreferredDirectory $config.ArmGnuToolchain.Directory -FallbackCommand 'arm-none-eabi-readelf'
if (-not $make -or -not $gcc -or -not $size -or -not $readelf) {
    throw 'Missing local GNU Make/Arm tools. Run bootstrap-hx6538.ps1.'
}

$runId = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssfffZ') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
$out = Join-Path $root (Join-Path 'artifacts\hx6538\build-sscma-legacy' $runId)
New-Item -ItemType Directory -Path $out -Force | Out-Null
$logFile = Join-Path $out 'build.log'
$defines = '-DCONFIG_EL_TARGET_HIMAX -DCONFIG_EL_BOARD_SENSECAP_WATCHER'
$makeArgs = @('TARGET=SENSECAP_WATCHER', 'APP_TYPE=sscma', 'TOOLCHAIN=gnu', 'OLEVEL=O2', 'MAP=1', "ADT_COPT=$defines", "ADT_CXXOPT=$defines")
$oldPath = $env:PATH
$env:PATH = "$(Split-Path -Parent $gcc.Path);$(Split-Path -Parent $make.Path);$oldPath"
$success = $false

Write-Host 'pibbi SSCMA legacy build: SENSECAP_WATCHER, ELF/MAP only'
Write-Host "Legacy SDK: $legacySha"
Write-Host "SSCMA-Micro: $microSha"
Write-Host "Artifacts: $out"
try {
    Push-Location $app
    try {
        foreach ($goal in @('clean', 'all')) {
            Write-Host "==> make $goal"
            & $make.Path @makeArgs $goal 2>&1 | Tee-Object -FilePath $logFile -Append
            $exitCode = $LASTEXITCODE
            if ($exitCode -ne 0) {
                throw "make $goal failed with exit code $exitCode. See $logFile"
            }
        }
    }
    finally { Pop-Location }

    $elf = Join-Path $app $elfRel
    $map = $elf + '.map'
    if (-not (Test-Path -LiteralPath $elf -PathType Leaf)) {
        throw "ELF not found after build: $elf"
    }
    if (-not (Test-Path -LiteralPath $map -PathType Leaf)) {
        throw "MAP not found after build: $map"
    }

    $destElf = Join-Path $out 'sscma-watcher.elf'
    $destMap = Join-Path $out 'sscma-watcher.elf.map'
    Copy-Item -LiteralPath $elf -Destination $destElf
    Copy-Item -LiteralPath $map -Destination $destMap

    & $size.Path -A $destElf | Out-File -LiteralPath (Join-Path $out 'sections-size.txt') -Encoding utf8
    if ($LASTEXITCODE -ne 0) { throw 'arm-none-eabi-size failed.' }
    & $readelf.Path -W -S $destElf | Out-File -LiteralPath (Join-Path $out 'sections-readelf.txt') -Encoding utf8
    if ($LASTEXITCODE -ne 0) { throw 'arm-none-eabi-readelf failed.' }

    RestoreKnownArchives $legacy
    AssertClean $legacy
    AssertClean $micro
    AssertClean $native

    $compilerVersion = Invoke-PibbiToolText -Path $gcc.Path -Arguments @('--version')
    $manifest = [ordered]@{
        SchemaVersion = 1
        Status = 'BUILD_PASS_NOT_FLASHED'
        BuiltAtUtc = (Get-Date).ToUniversalTime().ToString('o')
        SdkCommit = $legacySha
        SscmaMicroCommit = $microSha
        Target = 'SENSECAP_WATCHER'
        AppType = 'sscma'
        Toolchain = ($compilerVersion -split '[\r\n]+')[0]
        MakeArguments = $makeArgs
        Elf = [ordered]@{
            Artifact = $destElf
            Bytes = (Get-Item -LiteralPath $destElf).Length
            Sha256 = (Get-FileHash -LiteralPath $destElf -Algorithm SHA256).Hash.ToLowerInvariant()
        }
        Map = [ordered]@{
            Artifact = $destMap
            Sha256 = (Get-FileHash -LiteralPath $destMap -Algorithm SHA256).Hash.ToLowerInvariant()
        }
        DeviceTest = 'NOT_ATTEMPTED'
        Flash = 'NOT_ATTEMPTED'
    }
    $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $out 'build-manifest.json') -Encoding UTF8
    $success = $true

    Write-Host ''
    Write-Host 'SSCMA LEGACY BUILD PASS (ELF/MAP only)'
    Write-Host "ELF: $destElf"
    Write-Host "MAP: $destMap"
    Write-Host "Manifest: $(Join-Path $out 'build-manifest.json')"
    Write-Host 'Safety: NO IMAGE / NO FLASH / NO DEVICE I/O'
}
finally {
    $env:PATH = $oldPath
    if (-not $success) {
        Write-Warning "Build did not complete. Diagnostics retained: $out"
        Write-Warning 'Native baseline SDK was not used for compilation.'
    }
}
