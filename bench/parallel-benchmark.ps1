# parallel-benchmark.ps1 — 串行 / DirBucket / Subtree / Chunk 四种扫描模式对比（v0.6）
# 练习点：Measure-Command、并行模式设计差异、等价性校验、Amdahl 定律与负载均衡观察
[CmdletBinding()]
param(
    [string]$Path = 'D:\1Work\项目',
    [int]$Top = 10,
    [int]$ThrottleLimit = 8,
    [string[]]$Exclude
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'WsDoctor.psd1') -Force

if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
    Write-Error ('路径不存在: ' + $Path)
    exit 2
}

$scanArgs = @{ Path = $Path; Top = $Top }
if ($Exclude) { $scanArgs.Exclude = $Exclude }

Write-Host ('基准目录: {0}  （ThrottleLimit={1}）' -f $Path, $ThrottleLimit) -ForegroundColor Cyan

function Test-SameResult($A, $B) {
    return ($A.TotalFiles -eq $B.TotalFiles) -and
           ($A.TotalSize -eq $B.TotalSize) -and
           ($A.DirectoryCount -eq $B.DirectoryCount) -and
           ((@($A.TopFiles | ForEach-Object { $_.Path }) -join '|') -eq (@($B.TopFiles | ForEach-Object { $_.Path }) -join '|'))
}

$serial = $null
$serialMs = (Measure-Command { $serial = Invoke-WsScan @scanArgs }).TotalMilliseconds
$bucket = $null
$bucketMs = (Measure-Command { $bucket = Invoke-WsScan @scanArgs -Parallel -ParallelMode DirBucket -ThrottleLimit $ThrottleLimit }).TotalMilliseconds
$subtree = $null
$subtreeMs = (Measure-Command { $subtree = Invoke-WsScan @scanArgs -Parallel -ParallelMode Subtree -ThrottleLimit $ThrottleLimit }).TotalMilliseconds
$chunk = $null
$chunkMs = (Measure-Command { $chunk = Invoke-WsScan @scanArgs -Parallel -ParallelMode Chunk -ThrottleLimit $ThrottleLimit }).TotalMilliseconds

$rows = @(
    [pscustomobject]@{ Mode = '串行（默认）'; Ms = [math]::Round($serialMs, 1); Files = $serial.TotalFiles }
    [pscustomobject]@{ Mode = '并行 DirBucket（目录分桶）'; Ms = [math]::Round($bucketMs, 1); Files = $bucket.TotalFiles }
    [pscustomobject]@{ Mode = '并行 Subtree（子树）'; Ms = [math]::Round($subtreeMs, 1); Files = $subtree.TotalFiles }
    [pscustomobject]@{ Mode = '并行 Chunk（只并行聚合）'; Ms = [math]::Round($chunkMs, 1); Files = $chunk.TotalFiles }
)
$base = [math]::Max(1, $rows[0].Ms)
$rows | ForEach-Object { $_ | Add-Member -NotePropertyName Speedup -NotePropertyValue ([math]::Round($base / [Math]::Max(1, $_.Ms), 2)) -PassThru } |
    Format-Table -AutoSize | Out-Host

$ok = (Test-SameResult $serial $bucket) -and (Test-SameResult $serial $subtree) -and (Test-SameResult $serial $chunk)
Write-Host ('等价性（四种模式结果一致）: {0}' -f $ok) -ForegroundColor $(if ($ok) { 'Green' } else { 'Red' })
if (-not $ok) { exit 1 }
exit 0