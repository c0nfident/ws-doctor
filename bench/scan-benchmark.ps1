# scan-benchmark.ps1 — 串行 Get-ChildItem vs .NET EnumerateFiles 性能对照（v0.3）
# 练习点：Measure-Command、等价性校验、速率计算、退出码
[CmdletBinding()]
param(
    [string]$Path = 'D:\1Work\项目',
    [int]$Top = 10,
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

Write-Host ('基准目录: {0}' -f $Path) -ForegroundColor Cyan

$scanArgs = @{ Path = $Path; Top = $Top }
if ($Exclude) { $scanArgs.Exclude = $Exclude }

$fastResult = $null
$fast = Measure-Command { $fastResult = Invoke-WsScan @scanArgs }
$legacyResult = $null
$legacy = Measure-Command { $legacyResult = Invoke-WsScan @scanArgs -LegacyEnumerator }

# 等价性校验：两种实现必须得到相同的文件数与总大小
$sameFiles = $fastResult.TotalFiles -eq $legacyResult.TotalFiles
$sameSize = $fastResult.TotalSize -eq $legacyResult.TotalSize
$fastMs = [math]::Round($fast.TotalMilliseconds, 1)
$legacyMs = [math]::Round($legacy.TotalMilliseconds, 1)
$speedup = if ($fastMs -gt 0) { [math]::Round($legacyMs / $fastMs, 2) } else { 0 }

[pscustomobject]@{
    Mode = 'EnumerateFiles (v0.3 默认)'
    Ms = $fastMs
    Files = $fastResult.TotalFiles
    SizeMB = [math]::Round($fastResult.TotalSize / 1MB, 1)
    FilesPerSec = if ($fastMs -gt 0) { [math]::Round($fastResult.TotalFiles / ($fastMs / 1000), 0) } else { 0 }
} | Format-Table -AutoSize | Out-Host

[pscustomobject]@{
    Mode = 'Get-ChildItem (v0.1 -LegacyEnumerator)'
    Ms = $legacyMs
    Files = $legacyResult.TotalFiles
    SizeMB = [math]::Round($legacyResult.TotalSize / 1MB, 1)
    FilesPerSec = if ($legacyMs -gt 0) { [math]::Round($legacyResult.TotalFiles / ($legacyMs / 1000), 0) } else { 0 }
} | Format-Table -AutoSize | Out-Host

Write-Host ('加速比: {0}x   （节省 {1} ms）' -f $speedup, ($legacyMs - $fastMs)) -ForegroundColor Green
Write-Host ('等价性: TotalFiles={0}  TotalSize={1}' -f $sameFiles, $sameSize) -ForegroundColor $(if ($sameFiles -and $sameSize) { 'Green' } else { 'Red' })

if (-not ($sameFiles -and $sameSize)) { exit 1 }
exit 0
