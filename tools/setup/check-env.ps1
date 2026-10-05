[CmdletBinding()]
param(
    [ValidateSet('all', 'hx6538', 'esp32s3')]
    [string]$Platform = 'all'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$checks = @()
if ($Platform -eq 'all' -or $Platform -eq 'hx6538') {
    $checks += [pscustomobject]@{
        Name = 'HX6538'
        Path = Join-Path $PSScriptRoot 'check-hx6538-env.ps1'
    }
}
if ($Platform -eq 'all' -or $Platform -eq 'esp32s3') {
    $checks += [pscustomobject]@{
        Name = 'ESP32-S3'
        Path = Join-Path $PSScriptRoot 'check-esp32s3-env.ps1'
    }
}

$failures = 0
Write-Host 'pibbi development environment check'
Write-Host ''

foreach ($check in $checks) {
    Write-Host ('===== {0} =====' -f $check.Name)
    & $check.Path
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        $failures++
    }
    Write-Host ''
}

if ($failures -gt 0) {
    Write-Host ("pibbi environment check failed: {0} platform check(s) failed." -f $failures)
    exit 1
}

Write-Host 'pibbi environment check passed.'
exit 0
