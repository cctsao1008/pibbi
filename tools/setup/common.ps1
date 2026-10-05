Set-StrictMode -Version Latest

function Get-PibbiRepoRoot {
    return (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

function Get-Hx6538ToolConfig {
    $configPath = Join-Path $PSScriptRoot 'hx6538-tools.psd1'
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
        throw "HX6538 tool configuration not found: $configPath"
    }

    return Import-PowerShellDataFile -LiteralPath $configPath
}

function Get-PibbiExecutable {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,

        [Parameter(Mandatory = $true)]
        [string]$FileName,

        [string]$PreferredDirectory = '',

        [string]$FallbackCommand = ''
    )

    $toolsRoot = Join-Path $RepoRoot '.tools'

    if (-not [string]::IsNullOrWhiteSpace($PreferredDirectory)) {
        $preferred = Join-Path $toolsRoot (Join-Path $PreferredDirectory (Join-Path 'bin' $FileName))
        if (Test-Path -LiteralPath $preferred -PathType Leaf) {
            return [pscustomobject]@{
                Path = (Resolve-Path -LiteralPath $preferred).Path
                Source = 'project-local'
            }
        }
    }

    if (Test-Path -LiteralPath $toolsRoot -PathType Container) {
        $localMatch = Get-ChildItem -LiteralPath $toolsRoot -Filter $FileName -File -Recurse -ErrorAction SilentlyContinue |
            Select-Object -First 1

        if ($localMatch) {
            return [pscustomobject]@{
                Path = $localMatch.FullName
                Source = 'project-local'
            }
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($FallbackCommand)) {
        try {
            $command = Get-Command $FallbackCommand -ErrorAction Stop
            return [pscustomobject]@{
                Path = $command.Source
                Source = 'PATH'
            }
        }
        catch {
            return $null
        }
    }

    return $null
}

function Invoke-PibbiToolText {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [string[]]$Arguments = @()
    )

    try {
        $output = & $Path @Arguments 2>&1
        return (($output | ForEach-Object { $_.ToString() }) -join "`n").Trim()
    }
    catch {
        return $null
    }
}
