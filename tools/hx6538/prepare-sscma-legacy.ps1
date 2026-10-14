[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$sdkRoot = Join-Path $repoRoot 'third_party\sscma-example-we2'
$workRoot = Join-Path $repoRoot '.tools\work\hx6538-sscma-legacy'
$submoduleRel = 'EPII_CM55M_APP_S/library/sscma_micro'

# These revisions were independently checked against Seeed's public branches.
$baselineSdkSha = '3ac4e9f557f09fbe4e62806c2a19b5e8a23a9a70'
$legacySdkSha = '37fed7a8e27b9d50f64b6784c3aff7bbf04cf70d'
$legacyMicroSha = 'c90065ddd2d763728b0aa24902af9337922b94fb'

if (-not (Test-Path -LiteralPath $sdkRoot -PathType Container)) {
    throw "Missing baseline vendor SDK: $sdkRoot"
}
if (Test-Path -LiteralPath $workRoot) {
    throw "Refusing to replace an existing experiment worktree: $workRoot"
}

$head = (& git -C $sdkRoot rev-parse HEAD)
if ($LASTEXITCODE -ne 0 -or $head.Trim() -ne $baselineSdkSha) {
    throw 'Baseline SDK HEAD changed. Refusing to prepare a different source revision.'
}

$status = @(& git -C $sdkRoot status --porcelain=v1 --untracked-files=all)
if ($LASTEXITCODE -ne 0 -or $status.Count -ne 0) {
    throw 'Baseline SDK tree is not clean. Resolve changes first; no files were changed.'
}

# Fetch only the historical source branch; the working tree remains untouched.
Write-Host 'Fetching the historical, internally matched SSCMA source branch...'
& git -C $sdkRoot fetch origin 'refs/heads/b/1.0.x:refs/remotes/origin/b/1.0.x'
if ($LASTEXITCODE -ne 0) { throw 'Fetch failed' }
$remoteSha = (& git -C $sdkRoot rev-parse 'refs/remotes/origin/b/1.0.x')
if ($LASTEXITCODE -ne 0 -or $remoteSha.Trim() -ne $legacySdkSha) {
    throw 'Historical branch has moved from the reviewed revision; refusing to use it.'
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $workRoot) | Out-Null

Write-Host 'Creating an isolated detached worktree...'
& git -C $sdkRoot worktree add --detach $workRoot $legacySdkSha
if ($LASTEXITCODE -ne 0) { throw 'Worktree creation failed; inspect state manually.' }

Write-Host 'Checking out the historically paired SSCMA-Micro submodule...'
& git -C $workRoot submodule update --init --recursive -- $submoduleRel
if ($LASTEXITCODE -ne 0) { throw 'Submodule initialization failed; isolated worktree retained.' }

$submodulePath = Join-Path $workRoot ($submoduleRel -replace '/', '\')
$actualMicroSha = (& git -C $submodulePath rev-parse HEAD)
if ($LASTEXITCODE -ne 0 -or $actualMicroSha.Trim() -ne $legacyMicroSha) {
    throw "Submodule identity mismatch: $actualMicroSha. Worktree retained for inspection."
}

$requiredFiles = @(
    'EPII_CM55M_APP_S/app/scenario_app/sscma/sscma.cpp',
    'EPII_CM55M_APP_S/app/scenario_app/sscma/sscma.mk',
    'EPII_CM55M_APP_S/app/scenario_app/sscma/linker/watcher.ld',
    'EPII_CM55M_APP_S/library/sscma_micro/sscma/main_task.hpp',
    'EPII_CM55M_APP_S/library/sscma_micro/porting/himax/we2/boards/sensecap_watcher/board.h'
)
foreach ($relative in $requiredFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $workRoot $relative))) {
        throw "Missing required legacy file: $relative. Worktree retained."
    }
}

$finalStatus = @(& git -C $sdkRoot status --porcelain=v1 --untracked-files=all)
if ($LASTEXITCODE -ne 0 -or $finalStatus.Count -ne 0) {
    throw 'Baseline SDK working tree changed unexpectedly; inspect before proceeding.'
}

Write-Host ''
Write-Host 'Legacy SSCMA source CHECKOUT READY (no build)'
Write-Host ("SDK HEAD   : {0}" -f $legacySdkSha)
Write-Host ("SSCMA-Micro: {0}" -f $legacyMicroSha)
Write-Host ("Worktree   : {0}" -f $workRoot)
Write-Host 'Baseline   : original vendor SDK working tree remains clean'
Write-Host 'Safety     : NO BUILD / NO IMAGE / NO FLASH / NO DEVICE I/O'
