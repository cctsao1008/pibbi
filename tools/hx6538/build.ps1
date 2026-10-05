[CmdletBinding()]
param(
    [switch]$NoClean,
    [switch]$KeepVendorBuildArtifacts
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot '..\setup\common.ps1')

$repoRoot = Get-PibbiRepoRoot
$config = Get-Hx6538ToolConfig
$sdkRoot = Join-Path $repoRoot $config.SscmaWe2.Directory
$appRoot = Join-Path $sdkRoot 'EPII_CM55M_APP_S'
$elfRelative = 'obj_epii_evb_icv30_bdv10\gnu_epii_evb_WLCSP65\EPII_CM55M_gnu_epii_evb_WLCSP65_s.elf'
$elfPath = Join-Path $appRoot $elfRelative

function Get-GitStatusLines {
    param([Parameter(Mandatory = $true)][string]$Repository)

    $lines = & git -C $Repository status --porcelain=v1 --untracked-files=all 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "git status failed for $Repository"
    }

    return @($lines | ForEach-Object { $_.ToString() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Get-PorcelainPath {
    param([Parameter(Mandatory = $true)][string]$Line)

    if ($Line.Length -lt 4) {
        return ''
    }

    $path = $Line.Substring(3)
    if ($path -match ' -> ') {
        $path = ($path -split ' -> ')[-1]
    }

    return $path.Trim('"')
}

function Test-UpstreamBuildGeneratedArchive {
    param([Parameter(Mandatory = $true)][string]$Line)

    # Only restore unstaged working-tree modifications. Never auto-restore staged
    # changes, deletions, renames, or untracked files.
    if (-not $Line.StartsWith(' M ')) {
        return $false
    }

    $path = Get-PorcelainPath -Line $Line
    return $path -like 'EPII_CM55M_APP_S/prebuilt_libs/gnu/*.a'
}

function Restore-UpstreamBuildGeneratedArchives {
    param(
        [Parameter(Mandatory = $true)][string]$Repository,
        [Parameter(Mandatory = $true)][string[]]$StatusLines
    )

    $paths = @($StatusLines | ForEach-Object { Get-PorcelainPath -Line $_ })
    if ($paths.Count -eq 0) {
        return
    }

    Write-Host ('Restoring {0} upstream-generated prebuilt archive(s)...' -f $paths.Count)
    & git -C $Repository restore --worktree -- @paths
    if ($LASTEXITCODE -ne 0) {
        throw 'git restore failed while cleaning upstream-generated prebuilt archives'
    }
}

if (-not (Test-Path -LiteralPath $sdkRoot -PathType Container)) {
    throw "HX6538 SDK checkout not found: $sdkRoot. Run tools\setup\bootstrap-hx6538.ps1 first."
}

if (-not (Test-Path -LiteralPath $appRoot -PathType Container)) {
    throw "HX6538 application directory not found: $appRoot"
}

$gitCommand = Get-Command git -ErrorAction Stop
$make = Get-PibbiExecutable `
    -RepoRoot $repoRoot `
    -FileName 'make.exe' `
    -PreferredDirectory $config.WindowsBuildTools.Directory `
    -FallbackCommand 'make'
$armGcc = Get-PibbiExecutable `
    -RepoRoot $repoRoot `
    -FileName 'arm-none-eabi-gcc.exe' `
    -PreferredDirectory $config.ArmGnuToolchain.Directory `
    -FallbackCommand 'arm-none-eabi-gcc'

if (-not $make) {
    throw 'GNU Make is unavailable. Run tools\setup\bootstrap-hx6538.ps1.'
}
if (-not $armGcc) {
    throw 'Arm GNU Toolchain is unavailable. Run tools\setup\bootstrap-hx6538.ps1.'
}

$sdkHead = (& git -C $sdkRoot rev-parse HEAD).Trim()
$sdkBranch = (& git -C $sdkRoot branch --show-current).Trim()

Write-Host 'pibbi HX6538 upstream build'
Write-Host ("SDK       : {0}" -f $sdkRoot)
Write-Host ("SDK HEAD  : {0}" -f $sdkHead)
Write-Host ("SDK branch: {0}" -f $sdkBranch)
Write-Host ''

# Upstream rebuilds selected libraries and copies the resulting archives back into
# tracked prebuilt_libs/gnu/*.a files. Repair only that known build side effect if
# it is left over from a previous build. Any other SDK modification is a hard stop.
$initialStatus = Get-GitStatusLines -Repository $sdkRoot
if ($initialStatus.Count -gt 0) {
    $expectedInitial = @($initialStatus | Where-Object { Test-UpstreamBuildGeneratedArchive -Line $_ })
    $unexpectedInitial = @($initialStatus | Where-Object { -not (Test-UpstreamBuildGeneratedArchive -Line $_) })

    if ($unexpectedInitial.Count -gt 0) {
        Write-Host 'Unexpected SDK modifications detected:'
        $unexpectedInitial | ForEach-Object { Write-Host "  $_" }
        throw 'Refusing to build on top of an unexpectedly modified vendor SDK tree.'
    }

    Restore-UpstreamBuildGeneratedArchives -Repository $sdkRoot -StatusLines $expectedInitial
}

$remainingStatus = Get-GitStatusLines -Repository $sdkRoot
if ($remainingStatus.Count -ne 0) {
    throw 'SDK working tree is not clean after pre-build repair.'
}

$armBin = Split-Path -Parent $armGcc.Path
$makeBin = Split-Path -Parent $make.Path
$oldPath = $env:PATH
$env:PATH = "$armBin;$makeBin;$oldPath"

try {
    Push-Location $appRoot
    try {
        if (-not $NoClean) {
            Write-Host '==> make clean'
            & $make.Path clean
            if ($LASTEXITCODE -ne 0) {
                throw "make clean failed with exit code $LASTEXITCODE"
            }
        }

        Write-Host '==> make'
        & $make.Path
        if ($LASTEXITCODE -ne 0) {
            throw "make failed with exit code $LASTEXITCODE"
        }
    }
    finally {
        Pop-Location
    }
}
finally {
    $env:PATH = $oldPath
}

if (-not (Test-Path -LiteralPath $elfPath -PathType Leaf)) {
    throw "Build completed without the expected ELF: $elfPath"
}

$postStatus = Get-GitStatusLines -Repository $sdkRoot
$expectedPost = @($postStatus | Where-Object { Test-UpstreamBuildGeneratedArchive -Line $_ })
$unexpectedPost = @($postStatus | Where-Object { -not (Test-UpstreamBuildGeneratedArchive -Line $_) })

if ($unexpectedPost.Count -gt 0) {
    Write-Host 'Unexpected SDK modifications created by the build:'
    $unexpectedPost | ForEach-Object { Write-Host "  $_" }
    throw 'Build produced unexpected changes in the vendor SDK tree; leaving them intact for inspection.'
}

if ($expectedPost.Count -gt 0 -and -not $KeepVendorBuildArtifacts) {
    Restore-UpstreamBuildGeneratedArchives -Repository $sdkRoot -StatusLines $expectedPost
}
elseif ($expectedPost.Count -gt 0) {
    Write-Warning 'Leaving upstream-generated prebuilt archive modifications in the SDK tree because -KeepVendorBuildArtifacts was specified.'
}

if (-not $KeepVendorBuildArtifacts) {
    $finalStatus = Get-GitStatusLines -Repository $sdkRoot
    if ($finalStatus.Count -ne 0) {
        throw 'SDK working tree is not clean after post-build repair.'
    }
}

$elfItem = Get-Item -LiteralPath $elfPath
$elfHash = (Get-FileHash -LiteralPath $elfPath -Algorithm SHA256).Hash.ToLowerInvariant()
$armVersion = Invoke-PibbiToolText -Path $armGcc.Path -Arguments @('--version')
$makeVersion = Invoke-PibbiToolText -Path $make.Path -Arguments @('--version')
$armFirstLine = ($armVersion -split "`r?`n")[0]
$makeFirstLine = ($makeVersion -split "`r?`n")[0]

$artifactDir = Join-Path $repoRoot (Join-Path 'artifacts\hx6538\build' $sdkHead.Substring(0, 12))
New-Item -ItemType Directory -Force -Path $artifactDir | Out-Null
$artifactElf = Join-Path $artifactDir $elfItem.Name
Copy-Item -LiteralPath $elfPath -Destination $artifactElf -Force

$manifest = [ordered]@{
    SchemaVersion = 1
    BuiltAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    SdkCommit = $sdkHead
    SdkBranch = $sdkBranch
    Toolchain = $armFirstLine
    Make = $makeFirstLine
    Elf = [ordered]@{
        Source = $elfRelative -replace '\\', '/'
        Artifact = (Resolve-Path -LiteralPath $artifactElf).Path
        Bytes = $elfItem.Length
        Sha256 = $elfHash
    }
}

$manifestPath = Join-Path $artifactDir 'build-manifest.json'
$manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

Write-Host ''
Write-Host 'HX6538 build PASS'
Write-Host ("ELF       : {0}" -f $elfPath)
Write-Host ("ELF bytes : {0}" -f $elfItem.Length)
Write-Host ("ELF SHA256: {0}" -f $elfHash)
Write-Host ("Artifact  : {0}" -f $artifactElf)
Write-Host ("Manifest  : {0}" -f $manifestPath)
if (-not $KeepVendorBuildArtifacts) {
    Write-Host 'SDK tree  : clean (known upstream prebuilt archive side effects restored)'
}
