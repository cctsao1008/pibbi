[CmdletBinding()]
param(
    [switch]$KeepWorkDir
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot '..\setup\common.ps1')

$repoRoot = Get-PibbiRepoRoot
$config = Get-Hx6538ToolConfig
$sdkRoot = Join-Path $repoRoot $config.SscmaWe2.Directory
$imageGenSource = Join-Path $sdkRoot 'we2_image_gen_local'
$projectConfigName = 'project_case1_blp_wlcsp.json'
$generatorName = 'we2_local_image_gen.exe'

function Get-GitStatusLines {
    param([Parameter(Mandatory = $true)][string]$Repository)

    $lines = & git -C $Repository status --porcelain=v1 --untracked-files=all 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "git status failed for $Repository"
    }

    return @($lines | ForEach-Object { $_.ToString() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Resolve-PibbiArtifactPath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Artifact
    )

    if ([System.IO.Path]::IsPathRooted($Artifact)) {
        return $Artifact
    }

    $localPath = $Artifact -replace '/', '\'
    return (Join-Path $Root $localPath)
}

if (-not (Test-Path -LiteralPath $sdkRoot -PathType Container)) {
    throw "HX6538 SDK checkout not found: $sdkRoot. Run tools\setup\bootstrap-hx6538.ps1 first."
}

if (-not (Test-Path -LiteralPath $imageGenSource -PathType Container)) {
    throw "HX6538 image generator directory not found: $imageGenSource"
}

$gitCommand = Get-Command git -ErrorAction Stop
$sdkHead = (& git -C $sdkRoot rev-parse HEAD).Trim()
$sdkBranch = (& git -C $sdkRoot branch --show-current).Trim()
$sdkShort = $sdkHead.Substring(0, 12)

$status = @(Get-GitStatusLines -Repository $sdkRoot)
if ($status.Count -ne 0) {
    Write-Host 'SDK working tree is not clean:'
    $status | ForEach-Object { Write-Host "  $_" }
    throw 'Refusing to generate an image from a modified vendor SDK tree. Run the build wrapper or inspect the SDK changes first.'
}

$buildArtifactDir = Join-Path $repoRoot (Join-Path 'artifacts\hx6538\build' $sdkShort)
$buildManifestPath = Join-Path $buildArtifactDir 'build-manifest.json'
if (-not (Test-Path -LiteralPath $buildManifestPath -PathType Leaf)) {
    throw "Build manifest not found for SDK $sdkHead. Run tools\hx6538\build.ps1 first."
}

$buildManifest = Get-Content -LiteralPath $buildManifestPath -Raw | ConvertFrom-Json
if ([string]::IsNullOrWhiteSpace([string]$buildManifest.SdkCommit)) {
    throw "Build manifest is missing SdkCommit: $buildManifestPath"
}
if ([string]$buildManifest.SdkCommit -ne $sdkHead) {
    throw "Build manifest SDK commit does not match the current SDK. Manifest: $($buildManifest.SdkCommit); current: $sdkHead"
}
if (-not $buildManifest.Elf -or [string]::IsNullOrWhiteSpace([string]$buildManifest.Elf.Artifact)) {
    throw "Build manifest is missing Elf.Artifact: $buildManifestPath"
}

$buildElfPath = Resolve-PibbiArtifactPath -Root $repoRoot -Artifact ([string]$buildManifest.Elf.Artifact)
if (-not (Test-Path -LiteralPath $buildElfPath -PathType Leaf)) {
    throw "Build ELF artifact not found: $buildElfPath"
}

$buildElfItem = Get-Item -LiteralPath $buildElfPath
$buildElfHash = (Get-FileHash -LiteralPath $buildElfPath -Algorithm SHA256).Hash.ToLowerInvariant()
$manifestElfHash = ([string]$buildManifest.Elf.Sha256).ToLowerInvariant()
if ($buildElfHash -ne $manifestElfHash) {
    throw "Build ELF SHA-256 mismatch. Manifest: $manifestElfHash; actual: $buildElfHash"
}

$buildManifestHash = (Get-FileHash -LiteralPath $buildManifestPath -Algorithm SHA256).Hash.ToLowerInvariant()

Write-Host 'pibbi HX6538 image generation'
Write-Host ("SDK       : {0}" -f $sdkRoot)
Write-Host ("SDK HEAD  : {0}" -f $sdkHead)
Write-Host ("Build ELF : {0}" -f $buildElfPath)
Write-Host ("ELF SHA256: {0}" -f $buildElfHash)
Write-Host ''

# Generate from an archive of the exact SDK commit instead of running inside the
# live third_party checkout. This keeps ignored generator inputs/outputs from
# accumulating in the vendor working tree and guarantees that the image tooling
# itself comes from the same SDK commit recorded by the build manifest.
$workBase = Join-Path $repoRoot '.tools\work\hx6538-image'
New-Item -ItemType Directory -Force -Path $workBase | Out-Null
$workRoot = Join-Path $workBase ([guid]::NewGuid().ToString('N'))
$extractRoot = Join-Path $workRoot 'src'
$archivePath = Join-Path $workRoot 'we2-image-gen.zip'
New-Item -ItemType Directory -Force -Path $extractRoot | Out-Null

$artifactDir = Join-Path $repoRoot (Join-Path 'artifacts\hx6538\image' $sdkShort)
New-Item -ItemType Directory -Force -Path $artifactDir | Out-Null
$logPath = Join-Path $artifactDir 'image-gen.log'
$stdoutPath = Join-Path $workRoot 'image-gen.stdout.log'
$stderrPath = Join-Path $workRoot 'image-gen.stderr.log'

$generationSucceeded = $false
try {
    Write-Host '==> Export exact image-generator tree from SDK commit'
    & git -C $sdkRoot archive --format=zip "--output=$archivePath" $sdkHead we2_image_gen_local
    if ($LASTEXITCODE -ne 0) {
        throw "git archive failed with exit code $LASTEXITCODE"
    }

    Expand-Archive -LiteralPath $archivePath -DestinationPath $extractRoot -Force
    Remove-Item -LiteralPath $archivePath -Force

    $imageGenRoot = Join-Path $extractRoot 'we2_image_gen_local'
    $projectConfigPath = Join-Path $imageGenRoot $projectConfigName
    $generatorPath = Join-Path $imageGenRoot $generatorName

    if (-not (Test-Path -LiteralPath $projectConfigPath -PathType Leaf)) {
        throw "Image project configuration not found: $projectConfigPath"
    }
    if (-not (Test-Path -LiteralPath $generatorPath -PathType Leaf)) {
        throw "Windows image generator not found: $generatorPath"
    }

    $project = Get-Content -LiteralPath $projectConfigPath -Raw | ConvertFrom-Json
    if ([string]::IsNullOrWhiteSpace([string]$project.partition_setting)) {
        throw "Image project configuration is missing partition_setting: $projectConfigPath"
    }
    if ([string]::IsNullOrWhiteSpace([string]$project.output_folder)) {
        throw "Image project configuration is missing output_folder: $projectConfigPath"
    }

    $partitionRelative = [string]$project.partition_setting
    $partitionPath = Join-Path $imageGenRoot $partitionRelative
    if (-not (Test-Path -LiteralPath $partitionPath -PathType Leaf)) {
        throw "Partition configuration not found: $partitionPath"
    }

    $partition = Get-Content -LiteralPath $partitionPath -Raw | ConvertFrom-Json
    if (-not $partition.cm55m_s_application -or [string]::IsNullOrWhiteSpace([string]$partition.cm55m_s_application.input_file)) {
        throw "Partition configuration is missing cm55m_s_application.input_file: $partitionPath"
    }

    $inputElfRelative = [string]$partition.cm55m_s_application.input_file
    $inputElfPath = Join-Path $imageGenRoot $inputElfRelative
    $inputElfDir = Split-Path -Parent $inputElfPath
    New-Item -ItemType Directory -Force -Path $inputElfDir | Out-Null
    Copy-Item -LiteralPath $buildElfPath -Destination $inputElfPath -Force

    $stagedElfHash = (Get-FileHash -LiteralPath $inputElfPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($stagedElfHash -ne $buildElfHash) {
        throw "Staged ELF SHA-256 mismatch. Source: $buildElfHash; staged: $stagedElfHash"
    }

    $outputDir = Join-Path $imageGenRoot ([string]$project.output_folder)
    if (Test-Path -LiteralPath $outputDir) {
        Remove-Item -LiteralPath $outputDir -Recurse -Force
    }

    $generatorHash = (Get-FileHash -LiteralPath $generatorPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $projectConfigHash = (Get-FileHash -LiteralPath $projectConfigPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $partitionHash = (Get-FileHash -LiteralPath $partitionPath -Algorithm SHA256).Hash.ToLowerInvariant()

    Write-Host ('==> {0} {1}' -f $generatorName, $projectConfigName)
    $process = Start-Process `
        -FilePath $generatorPath `
        -ArgumentList @($projectConfigName) `
        -WorkingDirectory $imageGenRoot `
        -Wait `
        -PassThru `
        -NoNewWindow `
        -RedirectStandardOutput $stdoutPath `
        -RedirectStandardError $stderrPath

    $logLines = @()
    $logLines += '=== stdout ==='
    if (Test-Path -LiteralPath $stdoutPath) {
        $stdout = @(Get-Content -LiteralPath $stdoutPath)
        $logLines += $stdout
        $stdout | ForEach-Object { Write-Host $_ }
    }
    $logLines += '=== stderr ==='
    if (Test-Path -LiteralPath $stderrPath) {
        $stderr = @(Get-Content -LiteralPath $stderrPath)
        $logLines += $stderr
        $stderr | ForEach-Object { Write-Host $_ }
    }
    $logLines | Set-Content -LiteralPath $logPath -Encoding UTF8

    if ($process.ExitCode -ne 0) {
        throw "HX6538 image generator failed with exit code $($process.ExitCode). See $logPath"
    }

    $generatedImagePath = Join-Path $outputDir 'output.img'
    if (-not (Test-Path -LiteralPath $generatedImagePath -PathType Leaf)) {
        throw "Image generator completed without expected output: $generatedImagePath"
    }

    $generatedImageItem = Get-Item -LiteralPath $generatedImagePath
    if ($generatedImageItem.Length -le 0) {
        throw "Generated image is empty: $generatedImagePath"
    }

    $imageHash = (Get-FileHash -LiteralPath $generatedImagePath -Algorithm SHA256).Hash.ToLowerInvariant()
    $artifactImage = Join-Path $artifactDir 'output.img'
    Copy-Item -LiteralPath $generatedImagePath -Destination $artifactImage -Force

    $artifactImageHash = (Get-FileHash -LiteralPath $artifactImage -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($artifactImageHash -ne $imageHash) {
        throw "Copied image SHA-256 mismatch. Generated: $imageHash; artifact: $artifactImageHash"
    }

    $buildManifestRelative = ('artifacts/hx6538/build/{0}/build-manifest.json' -f $sdkShort)
    $buildElfRelative = ('artifacts/hx6538/build/{0}/{1}' -f $sdkShort, $buildElfItem.Name)
    $imageArtifactRelative = ('artifacts/hx6538/image/{0}/output.img' -f $sdkShort)
    $logRelative = ('artifacts/hx6538/image/{0}/image-gen.log' -f $sdkShort)

    $manifest = [ordered]@{
        SchemaVersion = 1
        GeneratedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
        SdkCommit = $sdkHead
        SdkBranch = $sdkBranch
        Build = [ordered]@{
            Manifest = $buildManifestRelative
            ManifestSha256 = $buildManifestHash
            Elf = $buildElfRelative
            ElfBytes = $buildElfItem.Length
            ElfSha256 = $buildElfHash
        }
        Generator = [ordered]@{
            Executable = "we2_image_gen_local/$generatorName"
            ExecutableSha256 = $generatorHash
            ProjectConfig = "we2_image_gen_local/$projectConfigName"
            ProjectConfigSha256 = $projectConfigHash
            PartitionConfig = ('we2_image_gen_local/{0}' -f ($partitionRelative -replace '\\', '/'))
            PartitionConfigSha256 = $partitionHash
        }
        Image = [ordered]@{
            Artifact = $imageArtifactRelative
            Bytes = $generatedImageItem.Length
            Sha256 = $imageHash
        }
        Log = $logRelative
    }

    $manifestPath = Join-Path $artifactDir 'image-manifest.json'
    $manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

    $generationSucceeded = $true

    Write-Host ''
    Write-Host 'HX6538 image generation PASS'
    Write-Host ("Image     : {0}" -f $artifactImage)
    Write-Host ("Image bytes: {0}" -f $generatedImageItem.Length)
    Write-Host ("Image SHA256: {0}" -f $imageHash)
    Write-Host ("Manifest  : {0}" -f $manifestPath)
    Write-Host ("Log       : {0}" -f $logPath)
    Write-Host 'SDK tree  : untouched (image generation ran from an archived staging copy)'
}
finally {
    if ($generationSucceeded -and -not $KeepWorkDir) {
        if (Test-Path -LiteralPath $workRoot) {
            Remove-Item -LiteralPath $workRoot -Recurse -Force
        }
    }
    else {
        if (Test-Path -LiteralPath $workRoot) {
            Write-Warning "Image-generation work directory preserved for inspection: $workRoot"
        }
    }
}
