# bridge.ps1 — C# GUI 与 WsDoctor 模块之间的桥（v1.0）
# 约定：GUI 用 Process 启动本脚本，结果写入 -ResultFile (JSON)，GUI 读取后反序列化。
#       不使用 stdout 管道（沙箱/受限环境安全），退出码：0 成功 / 1 业务失败 / 2 参数错误。
[CmdletBinding()]
param(
    [ValidateSet('Scan', 'Duplicates', 'Clean', 'Audit', 'Report', 'Estimate', 'EstimateScan')]
    [string]$Action = 'Scan',

    [Parameter(Mandatory)]
    [string]$Path,

    [int]$Top = 10,
    [long]$MinDupSize = 1024,
    [ValidateRange(1, 64)]
    [int]$ThrottleLimit = 4,
    [ValidateSet('DirBucket', 'Subtree', 'Chunk')]
    [string]$ParallelMode = 'DirBucket',
    [switch]$Parallel,
    [switch]$DryRun,
    [string]$OutDir,

    [Parameter(Mandatory)]
    [string]$ResultFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

$result = [ordered]@{
    action     = $Action
    success    = $false
    error      = ''
    startedAt  = (Get-Date).ToString('o')
    finishedAt = ''
    durationMs = 0
    version    = ''
    payload    = $null
}
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

try {
    Import-Module (Join-Path $root 'WsDoctor.psd1') -Force
    $result.version = (Get-Module WsDoctor).Version.ToString()
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw ('路径不存在: ' + $Path)
    }
    $scanArgs = @{ Path = $Path; Top = [Math]::Min([Math]::Max($Top, 1), 100) }
    if ($Parallel) { $scanArgs.Parallel = $true; $scanArgs.ParallelMode = $ParallelMode }

    switch ($Action) {
        'EstimateScan' {
            $estimate = Measure-WsScanWork -Path $Path -Parallel:$Parallel -ThrottleLimit $ThrottleLimit
            $result.payload = [ordered]@{
                kind             = 'scan-estimate'
                totalFiles       = $estimate.TotalFiles
                totalBytes       = $estimate.TotalBytes
                totalSizeText    = $estimate.TotalSizeText
                directoryCount   = $estimate.DirectoryCount
                parallel         = $estimate.Parallel
                throttleLimit    = $estimate.ThrottleLimit
                enumSeconds      = $estimate.EnumSeconds
                estimatedSeconds = $estimate.EstimatedSeconds
                estimatedText    = $estimate.EstimatedText
            }
        }
        'Estimate' {
            $estimate = Measure-WsDuplicateWork -Path $Path -MinSize $MinDupSize -ThrottleLimit $ThrottleLimit
            $result.payload = [ordered]@{
                kind                = 'estimate'
                totalFiles          = $estimate.TotalFiles
                totalBytes          = $estimate.TotalBytes
                totalSizeText       = $estimate.TotalSizeText
                candidateGroups     = $estimate.CandidateGroups
                candidateFiles      = $estimate.CandidateFiles
                candidateBytes      = $estimate.CandidateBytes
                candidateSizeText   = $estimate.CandidateSizeText
                sampleSize          = $estimate.SampleSize
                sampleBytes         = $estimate.SampleBytes
                estimatedFullBytes  = $estimate.EstimatedFullBytes
                enumSeconds         = $estimate.EnumSeconds
                throttleLimit       = $estimate.ThrottleLimit
                assumedMbPerSecond  = $estimate.AssumedMbPerSecond
                parallelSpeedup     = $estimate.ParallelSpeedup
                estimatedSeconds    = $estimate.EstimatedSeconds
                estimatedText       = $estimate.EstimatedText
            }
        }
        'Scan' {
            $scan = Invoke-WsScan @scanArgs
            $result.payload = [ordered]@{
                kind          = 'scan'
                root          = $scan.Root
                totalFiles    = $scan.TotalFiles
                totalSize     = $scan.TotalSize
                totalSizeText = $scan.GetTotalSizeText()
                directoryCount = $scan.DirectoryCount
                durationMs    = $scan.DurationMs
                errorCount    = $scan.ErrorCount
                directories   = @($scan.Directories | Select-Object -First 50 | ForEach-Object {
                        [ordered]@{ path = $_.Path; files = $_.Files; size = $_.Size; sizeText = $_.SizeText; severity = [string]$_.Severity }
                    })
                topFiles      = @($scan.TopFiles | ForEach-Object {
                        [ordered]@{ path = $_.Path; size = $_.Size; sizeText = $_.SizeText }
                    })
            }
        }
        'Duplicates' {
            $groups = @(Find-WsDuplicateFile -Path $Path -MinSize $MinDupSize -ThrottleLimit $ThrottleLimit)
            $wasted = 0L
            foreach ($group in $groups) { $wasted += $group.Wasted }
            $result.payload = [ordered]@{
                kind          = 'duplicates'
                groupCount    = $groups.Count
                wasted        = $wasted
                wastedText    = Format-WsSize -Bytes $wasted
                groups        = @($groups | Select-Object -First 100 | ForEach-Object {
                        [ordered]@{
                            size = $_.Size; sizeText = $_.SizeText; fileCount = $_.FileCount
                            wasted = $_.Wasted; wastedText = $_.WastedText
                            hash = $_.Hash; sampleFile = $_.SampleFile
                            files = @($_.Files | Select-Object -First 10)
                        }
                    })
            }
        }
        'Clean' {
            $removed = @(Remove-WsEmptyDirectory -Path $Path -WhatIf:$DryRun)
            $result.payload = [ordered]@{
                kind   = 'clean'
                dryRun = [bool]$DryRun
                count  = $removed.Count
                dirs   = @($removed | Select-Object -First 200)
            }
        }
        'Audit' {
            $findings = @(Invoke-WsWorkspaceAudit -Path $Path -Config (Import-WsConfig))
            $result.payload = [ordered]@{
                kind     = 'audit'
                count    = $findings.Count
                error    = @($findings | Where-Object { $_.Severity -eq 'Error' }).Count
                warn     = @($findings | Where-Object { $_.Severity -eq 'Warn' }).Count
                info     = @($findings | Where-Object { $_.Severity -eq 'Info' }).Count
                findings = @($findings | ForEach-Object {
                        [ordered]@{ severity = [string]$_.Severity; category = $_.Category; target = $_.Target; message = $_.Message; action = $_.Action }
                    })
            }
        }
        'Report' {
            $scan = Invoke-WsScan @scanArgs
            $groups = @(Find-WsDuplicateFile -Path $Path -MinSize $MinDupSize -ThrottleLimit $ThrottleLimit)
            $targetDir = if ($OutDir) { $OutDir } else { Join-Path ([System.IO.Path]::GetTempPath()) ('wsdoctor-report-' + (Get-Date -Format 'yyyyMMdd-HHmmss')) }
            $files = @(Export-WsReport -ScanResult $scan -DuplicateGroups $groups -OutputDirectory $targetDir -Format @('Json', 'Csv', 'Html'))
            $result.payload = [ordered]@{
                kind    = 'report'
                outDir  = $targetDir
                files   = @($files)
                groupCount = $groups.Count
            }
        }
    }
    $result.success = $true
} catch {
    $result.error = $_.Exception.Message
} finally {
    $stopwatch.Stop()
    $result.durationMs = [math]::Round($stopwatch.Elapsed.TotalMilliseconds, 1)
    $result.finishedAt = (Get-Date).ToString('o')
    $directory = Split-Path -Parent $ResultFile
    if ($directory -and -not (Test-Path -LiteralPath $directory -PathType Container)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    $result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $ResultFile -Encoding UTF8
}

if ($result.success) { exit 0 } else { exit 1 }
