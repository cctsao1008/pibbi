[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$script:RequiredFailures = 0

function Write-CheckResult {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("PASS", "WARN", "FAIL")]
        [string]$Status,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [string]$Detail = ""
    )

    if ($Status -eq "FAIL") {
        $script:RequiredFailures++
    }

    if ([string]::IsNullOrWhiteSpace($Detail)) {
        Write-Host ("[{0}] {1}" -f $Status, $Name)
    }
    else {
        Write-Host ("[{0}] {1}: {2}" -f $Status, $Name, $Detail)
    }
}

function Get-CommandOutput {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command,

        [string[]]$Arguments = @()
    )

    try {
        $commandInfo = Get-Command $Command -ErrorAction Stop
        $output = & $commandInfo.Source @Arguments 2>&1
        return (($output | ForEach-Object { $_.ToString() }) -join " ").Trim()
    }
    catch {
        return $null
    }
}

Write-Host "pibbi HX6538 development environment check"
Write-Host ""

# Git
$gitVersion = Get-CommandOutput -Command "git" -Arguments @("--version")
if ($gitVersion) {
    Write-CheckResult -Status "PASS" -Name "Git" -Detail $gitVersion
}
else {
    Write-CheckResult -Status "FAIL" -Name "Git" -Detail "git was not found in PATH"
}

# Python: prefer python.exe, then fall back to the Windows py launcher.
$pythonCommand = $null
$pythonPrefixArgs = @()
$pythonVersion = Get-CommandOutput -Command "python" -Arguments @("--version")

if ($pythonVersion -and ($pythonVersion -match "Python\s+(\d+)\.(\d+)\.(\d+)")) {
    $pythonCommand = "python"
}
else {
    $pythonVersion = Get-CommandOutput -Command "py" -Arguments @("-3", "--version")
    if ($pythonVersion -and ($pythonVersion -match "Python\s+(\d+)\.(\d+)\.(\d+)")) {
        $pythonCommand = "py"
        $pythonPrefixArgs = @("-3")
    }
}

if ($pythonCommand -and ($pythonVersion -match "Python\s+(\d+)\.(\d+)\.(\d+)")) {
    $pythonMajor = [int]$Matches[1]
    $pythonMinor = [int]$Matches[2]

    if (($pythonMajor -gt 3) -or (($pythonMajor -eq 3) -and ($pythonMinor -ge 8))) {
        Write-CheckResult -Status "PASS" -Name "Python" -Detail $pythonVersion
    }
    else {
        Write-CheckResult -Status "FAIL" -Name "Python" -Detail ("{0}; Python 3.8 or newer is required" -f $pythonVersion)
    }
}
else {
    Write-CheckResult -Status "FAIL" -Name "Python" -Detail "Python 3 was not found"
}

# pip, using the same Python interpreter selected above.
if ($pythonCommand) {
    try {
        $pythonInfo = Get-Command $pythonCommand -ErrorAction Stop
        $pipArgs = @()
        $pipArgs += $pythonPrefixArgs
        $pipArgs += @("-m", "pip", "--version")
        $pipOutput = & $pythonInfo.Source @pipArgs 2>&1
        $pipVersion = (($pipOutput | ForEach-Object { $_.ToString() }) -join " ").Trim()

        if ($LASTEXITCODE -eq 0 -and $pipVersion) {
            Write-CheckResult -Status "PASS" -Name "pip" -Detail $pipVersion
        }
        else {
            Write-CheckResult -Status "FAIL" -Name "pip" -Detail "python -m pip is unavailable"
        }
    }
    catch {
        Write-CheckResult -Status "FAIL" -Name "pip" -Detail "python -m pip is unavailable"
    }
}
else {
    Write-CheckResult -Status "FAIL" -Name "pip" -Detail "Python is unavailable"
}

# GNU Make
$makeVersion = Get-CommandOutput -Command "make" -Arguments @("--version")
if ($makeVersion) {
    $makeFirstLine = ($makeVersion -split "  ")[0]
    Write-CheckResult -Status "PASS" -Name "GNU Make" -Detail $makeFirstLine
}
else {
    Write-CheckResult -Status "FAIL" -Name "GNU Make" -Detail "make was not found in PATH"
}

# Arm GNU Toolchain. Keep the expected release explicit for reproducible HX6538 builds.
$armGccVersion = Get-CommandOutput -Command "arm-none-eabi-gcc" -Arguments @("--version")
if ($armGccVersion) {
    if ($armGccVersion -match "13\.2\.Rel1") {
        Write-CheckResult -Status "PASS" -Name "Arm GNU Toolchain" -Detail "13.2.Rel1"
    }
    else {
        Write-CheckResult -Status "FAIL" -Name "Arm GNU Toolchain" -Detail ("arm-none-eabi-gcc found, but expected 13.2.Rel1; detected: {0}" -f $armGccVersion)
    }
}
else {
    Write-CheckResult -Status "FAIL" -Name "Arm GNU Toolchain" -Detail "arm-none-eabi-gcc was not found in PATH"
}

# SDK checkout. This is intentionally only a warning until bootstrap automation is added.
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$sdkCandidates = @()

if (-not [string]::IsNullOrWhiteSpace($env:SSCMA_WE2_ROOT)) {
    $sdkCandidates += $env:SSCMA_WE2_ROOT
}

$sdkCandidates += (Join-Path $repoRoot "third_party\sscma-example-we2")
$sdkCandidates += (Join-Path (Split-Path $repoRoot -Parent) "sscma-example-we2")

$sdkPath = $null
foreach ($candidate in $sdkCandidates) {
    if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Container)) {
        $sdkPath = (Resolve-Path -LiteralPath $candidate).Path
        break
    }
}

if ($sdkPath) {
    Write-CheckResult -Status "PASS" -Name "sscma-example-we2" -Detail $sdkPath
}
else {
    Write-CheckResult -Status "WARN" -Name "sscma-example-we2" -Detail "SDK checkout not found; bootstrap support will be added later"
}

Write-Host ""
if ($script:RequiredFailures -gt 0) {
    Write-Host ("Environment check failed: {0} required check(s) failed." -f $script:RequiredFailures)
    exit 1
}

Write-Host "Environment check passed."
exit 0
