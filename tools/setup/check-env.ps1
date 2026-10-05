[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$script:RequiredFailures = 0
$script:Warnings = 0

. (Join-Path $PSScriptRoot 'common.ps1')

$repoRoot = Get-PibbiRepoRoot
$config = Get-Hx6538ToolConfig

function Write-CheckResult {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('PASS', 'WARN', 'FAIL')]
        [string]$Status,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [string]$Detail = ''
    )

    switch ($Status) {
        'FAIL' { $script:RequiredFailures++ }
        'WARN' { $script:Warnings++ }
    }

    if ([string]::IsNullOrWhiteSpace($Detail)) {
        Write-Host ('[{0}] {1}' -f $Status, $Name)
    }
    else {
        Write-Host ('[{0}] {1}: {2}' -f $Status, $Name, $Detail)
    }
}

Write-Host 'pibbi HX6538 development environment check'
Write-Host ''

# Git is required both for pibbi and for the managed upstream SDK checkout.
$git = Get-PibbiExecutable -RepoRoot $repoRoot -FileName 'git.exe' -FallbackCommand 'git'
if ($git) {
    $gitVersion = Invoke-PibbiToolText -Path $git.Path -Arguments @('--version')
    Write-CheckResult -Status 'PASS' -Name 'Git' -Detail $gitVersion
}
else {
    Write-CheckResult -Status 'FAIL' -Name 'Git' -Detail 'git was not found in PATH'
}

# Python: prefer python.exe, then the Windows py launcher.
$pythonPath = $null
$pythonPrefixArgs = @()
try {
    $pythonPath = (Get-Command 'python' -ErrorAction Stop).Source
}
catch {
    try {
        $pythonPath = (Get-Command 'py' -ErrorAction Stop).Source
        $pythonPrefixArgs = @('-3')
    }
    catch {
        $pythonPath = $null
    }
}

$pythonVersion = $null
if ($pythonPath) {
    $pythonVersion = Invoke-PibbiToolText -Path $pythonPath -Arguments ($pythonPrefixArgs + @('--version'))
}

if ($pythonVersion -and ($pythonVersion -match 'Python\s+(\d+)\.(\d+)(?:\.(\d+))?')) {
    $pythonDetected = [version](('{0}.{1}' -f $Matches[1], $Matches[2]))
    $pythonMinimum = [version]$config.Python.MinimumVersion

    if ($pythonDetected -ge $pythonMinimum) {
        Write-CheckResult -Status 'PASS' -Name 'Python' -Detail $pythonVersion
    }
    else {
        Write-CheckResult -Status 'FAIL' -Name 'Python' -Detail ("$pythonVersion; >= $pythonMinimum is required")
    }
}
else {
    Write-CheckResult -Status 'FAIL' -Name 'Python' -Detail 'Python 3 was not found'
}

# pip, using the same interpreter selected above.
if ($pythonPath) {
    $pipVersion = Invoke-PibbiToolText -Path $pythonPath -Arguments ($pythonPrefixArgs + @('-m', 'pip', '--version'))
    if ($pipVersion -and $pipVersion -match '^pip\s+') {
        Write-CheckResult -Status 'PASS' -Name 'pip' -Detail $pipVersion
    }
    else {
        Write-CheckResult -Status 'FAIL' -Name 'pip' -Detail 'python -m pip is unavailable'
    }
}
else {
    Write-CheckResult -Status 'FAIL' -Name 'pip' -Detail 'Python is unavailable'
}

# Prefer the project-local, pinned xPack build tools over any system installation.
$make = Get-PibbiExecutable `
    -RepoRoot $repoRoot `
    -FileName 'make.exe' `
    -PreferredDirectory $config.WindowsBuildTools.Directory `
    -FallbackCommand 'make'

if ($make) {
    $makeVersion = Invoke-PibbiToolText -Path $make.Path -Arguments @('--version')
    $makeFirstLine = ($makeVersion -split "`r?`n")[0]

    if (-not ($makeFirstLine -match '^GNU Make\s+')) {
        Write-CheckResult -Status 'FAIL' -Name 'GNU Make' -Detail ("unexpected make implementation at $($make.Path): $makeFirstLine")
    }
    elseif ($makeFirstLine -match [regex]::Escape($config.WindowsBuildTools.MakeVersion)) {
        Write-CheckResult -Status 'PASS' -Name 'GNU Make' -Detail ("$makeFirstLine [$($make.Source)]")
    }
    else {
        Write-CheckResult -Status 'WARN' -Name 'GNU Make' -Detail ("$makeFirstLine [$($make.Source)]; pibbi pins $($config.WindowsBuildTools.MakeVersion)")
    }
}
else {
    Write-CheckResult -Status 'FAIL' -Name 'GNU Make' -Detail 'make was not found; run bootstrap-hx6538.ps1'
}

# HX6538 upstream currently documents Arm GNU Toolchain 13.2.Rel1. Prefer the
# project-local toolchain so unrelated firmware projects can keep newer compilers.
$armGcc = Get-PibbiExecutable `
    -RepoRoot $repoRoot `
    -FileName 'arm-none-eabi-gcc.exe' `
    -PreferredDirectory $config.ArmGnuToolchain.Directory `
    -FallbackCommand 'arm-none-eabi-gcc'

if ($armGcc) {
    $armGccVersion = Invoke-PibbiToolText -Path $armGcc.Path -Arguments @('--version')
    $armFirstLine = ($armGccVersion -split "`r?`n")[0]

    if ($armGccVersion -match [regex]::Escape($config.ArmGnuToolchain.Version)) {
        Write-CheckResult -Status 'PASS' -Name 'Arm GNU Toolchain' -Detail ("$($config.ArmGnuToolchain.Version) [$($armGcc.Source)]")
    }
    else {
        Write-CheckResult -Status 'FAIL' -Name 'Arm GNU Toolchain' -Detail ("expected $($config.ArmGnuToolchain.Version); detected $armFirstLine [$($armGcc.Source)]")
    }
}
else {
    Write-CheckResult -Status 'FAIL' -Name 'Arm GNU Toolchain' -Detail 'arm-none-eabi-gcc was not found; run bootstrap-hx6538.ps1'
}

# Managed SDK checkout. An external override is supported for debugging, but the
# repository-local checkout is the reproducible path and is always preferred.
$managedSdkPath = Join-Path $repoRoot $config.SscmaWe2.Directory
$sdkPath = $null
$sdkSource = $null

if (Test-Path -LiteralPath $managedSdkPath -PathType Container) {
    $sdkPath = (Resolve-Path -LiteralPath $managedSdkPath).Path
    $sdkSource = 'project-managed'
}
elseif (-not [string]::IsNullOrWhiteSpace($env:SSCMA_WE2_ROOT) -and (Test-Path -LiteralPath $env:SSCMA_WE2_ROOT -PathType Container)) {
    $sdkPath = (Resolve-Path -LiteralPath $env:SSCMA_WE2_ROOT).Path
    $sdkSource = 'external override'
}

if (-not $sdkPath) {
    Write-CheckResult -Status 'FAIL' -Name 'sscma-example-we2' -Detail 'managed SDK checkout not found; run bootstrap-hx6538.ps1'
}
elseif (-not (Test-Path -LiteralPath (Join-Path $sdkPath '.git'))) {
    Write-CheckResult -Status 'FAIL' -Name 'sscma-example-we2' -Detail ("not a Git checkout: $sdkPath")
}
else {
    $sdkHead = (& $git.Path -C $sdkPath rev-parse HEAD 2>$null).Trim()
    $sdkBranch = (& $git.Path -C $sdkPath branch --show-current 2>$null).Trim()
    $sdkDirty = (& $git.Path -C $sdkPath status --porcelain 2>$null)

    Write-CheckResult -Status 'PASS' -Name 'sscma-example-we2' -Detail ("$sdkPath [$sdkSource], HEAD $sdkHead")

    if ($sdkSource -ne 'project-managed') {
        Write-CheckResult -Status 'WARN' -Name 'SDK location' -Detail 'using SSCMA_WE2_ROOT override instead of the managed third_party checkout'
    }

    if (-not [string]::IsNullOrWhiteSpace($config.SscmaWe2.Commit)) {
        if ($sdkHead -eq $config.SscmaWe2.Commit) {
            Write-CheckResult -Status 'PASS' -Name 'SDK pin' -Detail $sdkHead
        }
        else {
            Write-CheckResult -Status 'FAIL' -Name 'SDK pin' -Detail ("expected $($config.SscmaWe2.Commit); detected $sdkHead")
        }
    }
    else {
        if ($sdkBranch -eq $config.SscmaWe2.Track) {
            Write-CheckResult -Status 'WARN' -Name 'SDK pin' -Detail ("tracking $sdkBranch until the first known-good Watcher baseline is validated")
        }
        else {
            Write-CheckResult -Status 'WARN' -Name 'SDK pin' -Detail ("baseline is not pinned yet; current branch is '$sdkBranch', expected track '$($config.SscmaWe2.Track)'")
        }
    }

    if ($sdkDirty) {
        Write-CheckResult -Status 'WARN' -Name 'SDK working tree' -Detail 'local modifications detected in third_party/sscma-example-we2'
    }
    else {
        Write-CheckResult -Status 'PASS' -Name 'SDK working tree' -Detail 'clean'
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
