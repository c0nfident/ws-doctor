<#
.SYNOPSIS
    WsDoctor — 工作区体检工具（体积扫描 / 重复文件 / 空目录清理 / 规则体检 / 报告）。
.DESCRIPTION
    v1.0 单入口 CLI：
    - 默认扫描目录（串行或并行），列出目录体积与最大文件；
    - 可组合动作：-FindDuplicates 重复文件、-CleanEmptyDirs 空目录清理、-Audit 规则体检；
    - 支持 JSON 配置（默认 → 用户文件 → CLI 参数三层合并）与 JSON/CSV/HTML 报告导出；
    - -DryRun 全局演练：所有写盘/删除动作只预览；-Version 显示版本。
.EXAMPLE
    pwsh -NoProfile -File .\wsdoctor.ps1 -Path D:\1Work -Top 5
.EXAMPLE
    pwsh -NoProfile -File .\wsdoctor.ps1 -Path D:\1Work -Audit -CleanEmptyDirs -DryRun
.EXAMPLE
    pwsh -NoProfile -File .\wsdoctor.ps1 -Path D:\1Work -Parallel -ParallelMode DirBucket -OutDir .\reports -Format All
.EXAMPLE
    pwsh -NoProfile -File .\wsdoctor.ps1 -Version
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Position = 0)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
    [ArgumentCompleter({
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
            Get-ChildItem -Directory -Force -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -like ($wordToComplete + '*') } |
                ForEach-Object { [System.Management.Automation.CompletionResult]::new($_.FullName, $_.Name, 'ProviderContainer', $_.FullName) }
        })]
    [string]$Path = '.',

    [ValidateRange(1, 1000)]
    [int]$Top,

    [string[]]$Exclude,

    [switch]$Parallel,

    [ValidateSet('DirBucket', 'Subtree', 'Chunk')]
    [ArgumentCompleter({
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
            @('DirBucket', 'Subtree', 'Chunk') |
                Where-Object { $_ -like ($wordToComplete + '*') } |
                ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_ + ' 并行模式') }
        })]
    [string]$ParallelMode,

    [ValidateRange(1, 64)]
    [int]$ThrottleLimit,

    [switch]$Scan,
    [switch]$CleanEmptyDirs,
    [switch]$FindDuplicates,
    [switch]$Audit,
    [switch]$DryRun,

    [ValidateRange(0, [long]::MaxValue)]
    [long]$MinDupSize,

    [ArgumentCompleter({
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
            Get-ChildItem -File -Force -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -like ($wordToComplete + '*') } |
                ForEach-Object { [System.Management.Automation.CompletionResult]::new($_.FullName, $_.Name, 'ProviderItem', $_.FullName) }
        })]
    [string]$ConfigPath,

    [ArgumentCompleter({
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
            Get-ChildItem -Directory -Force -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -like ($wordToComplete + '*') } |
                ForEach-Object { [System.Management.Automation.CompletionResult]::new($_.FullName, $_.Name, 'ProviderContainer', $_.FullName) }
        })]
    [string]$OutDir,

    [ValidateSet('Json', 'Csv', 'Html', 'All')]
    [ArgumentCompleter({
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
            @('Json', 'Csv', 'Html', 'All') |
                Where-Object { $_ -like ($wordToComplete + '*') } |
                ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_ + ' 报告格式') }
        })]
    [string[]]$Format,

    [switch]$Version
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'WsDoctor.psd1') -Force

# -Version：只打印版本后退出（便于脚本/计划任务探测）
if ($Version) {
    Write-Output ('WsDoctor ' + (Get-Module WsDoctor).Version)
    exit 0
}

# 配置优先级：默认配置 → 用户配置文件 → CLI 参数
$override = @{}
$scanOverride = @{}
if ($PSBoundParameters.ContainsKey('Top')) { $scanOverride['top'] = $Top }
if ($PSBoundParameters.ContainsKey('Exclude')) { $scanOverride['exclude'] = $Exclude }
if ($PSBoundParameters.ContainsKey('Parallel')) { $scanOverride['parallel'] = [bool]$Parallel }
if ($PSBoundParameters.ContainsKey('ThrottleLimit')) { $scanOverride['throttleLimit'] = $ThrottleLimit }
if ($scanOverride.Count -gt 0) { $override['scan'] = $scanOverride }
$dupOverride = @{}
if ($PSBoundParameters.ContainsKey('MinDupSize')) { $dupOverride['minSize'] = $MinDupSize }
if ($dupOverride.Count -gt 0) { $override['duplicates'] = $dupOverride }

$configArgs = @{}
if ($PSBoundParameters.ContainsKey('ConfigPath')) { $configArgs.Path = $ConfigPath }
if ($override.Count -gt 0) { $configArgs.Override = $override }
$config = Import-WsConfig @configArgs

$effectiveTop = [int]$config.scan.top
$effectiveParallel = [bool]$config.scan.parallel
$effectiveThrottle = [int]$config.scan.throttleLimit
$effectiveExclude = @($config.scan.exclude)
$effectiveMinDupSize = [long]$config.duplicates.minSize
$effectiveParallelMode = if ($PSBoundParameters.ContainsKey('ParallelMode')) { $ParallelMode } else { 'DirBucket' }
$reportFormats = if ($PSBoundParameters.ContainsKey('Format')) { @($Format) } else { @($config.report.formats) }

# -DryRun：所有会写盘/删除的动作都走预览（等价于全局 -WhatIf）
if ($DryRun) {
    $WhatIfPreference = $true
    Write-Host '*** DRY-RUN：仅预览，不删除/不写入任何文件 ***' -ForegroundColor Magenta
}

# 动作选择：显式指定任一动作就只跑这些；否则默认跑扫描
$actions = [System.Collections.Generic.List[string]]::new()
if ($Scan) { $actions.Add('scan') }
if ($CleanEmptyDirs) { $actions.Add('clean') }
if ($FindDuplicates) { $actions.Add('dup') }
if ($Audit) { $actions.Add('audit') }
if ($actions.Count -eq 0) { $actions.Add('scan') }

$scanResult = $null
$dupGroups = @()

function Write-WsHeader {
    param([string]$Text)
    Write-Host ''
    Write-Host $Text -ForegroundColor Yellow
}

try {
    Write-Verbose ('配置: top={0} parallel={1} mode={2} throttle={3} minDupSize={4} exclude={5} 项 formats={6}' -f
        $effectiveTop, $effectiveParallel, $effectiveParallelMode, $effectiveThrottle,
        $effectiveMinDupSize, $effectiveExclude.Count, ($reportFormats -join ','))

    if ($actions.Contains('scan')) {
        $scanResult = Invoke-WsScan -Path $Path -Top $effectiveTop -Exclude $effectiveExclude `
            -Parallel:$effectiveParallel -ParallelMode $effectiveParallelMode -ThrottleLimit $effectiveThrottle
        Write-Host ''
        Write-Host ('WsDoctor 体检报告  {0}' -f $scanResult.Root) -ForegroundColor Cyan
        Write-Host ('  文件 {0:N0} 个 · 总大小 {1} · 耗时 {2} ms · 访问错误 {3} 个' -f
            $scanResult.TotalFiles, $scanResult.GetTotalSizeText(), $scanResult.DurationMs, $scanResult.ErrorCount)
        if ($scanResult.Directories.Count -gt 0) {
            Write-WsHeader ('按目录（Top {0}）:' -f [Math]::Min($effectiveTop, $scanResult.DirectoryCount))
            $scanResult.Directories |
                Select-Object -First $effectiveTop -Property Path, Files,
                    @{ Name = 'Size'; Expression = { $_.SizeText } }, Severity |
                Format-Table -AutoSize | Out-Host
        }
        if ($scanResult.TopFiles.Count -gt 0) {
            Write-WsHeader '最大的文件:'
            $scanResult.TopFiles |
                Select-Object -Property @{ Name = 'Size'; Expression = { $_.SizeText } }, Path |
                Format-Table -AutoSize | Out-Host
        }
        if ($scanResult.ErrorCount -gt 0) {
            Write-Warning ('有 {0} 个路径无法访问（已跳过），示例: {1}' -f $scanResult.ErrorCount, $scanResult.Errors[0])
        }
    }

    if ($actions.Contains('dup')) {
        $dupGroups = @(Find-WsDuplicateFile -Path $Path -MinSize $effectiveMinDupSize -Exclude $effectiveExclude)
        $wasted = 0L
        foreach ($g in $dupGroups) { $wasted += $g.Wasted }
        Write-WsHeader ('重复文件: {0} 组 · 可回收 {1}' -f $dupGroups.Count, (Format-WsSize -Bytes $wasted))
        if ($dupGroups.Count -gt 0) {
            $dupGroups | Select-Object -First 20 | Format-Table -AutoSize | Out-Host
            if ($dupGroups.Count -gt 20) { Write-Host ('  ...（共 {0} 组，只显示前 20）' -f $dupGroups.Count) }
        }
    }

    if ($actions.Contains('clean')) {
        Write-WsHeader '清理空目录（-WhatIf 可预览）:'
        $removed = Remove-WsEmptyDirectory -Path $Path -Exclude $effectiveExclude -WhatIf:$WhatIfPreference
        if ($WhatIfPreference) {
            Write-Host '  以上为 -WhatIf 预览，未实际删除'
        } else {
            Write-Host ('  已删除 {0} 个空目录' -f @($removed).Count) -ForegroundColor Green
        }
    }

    if ($actions.Contains('audit')) {
        $findings = @(Invoke-WsWorkspaceAudit -Path $Path -Config $config)
        Write-WsHeader ('工作区体检: {0} 条发现' -f $findings.Count)
        if ($findings.Count -gt 0) {
            $findings | Format-Table -AutoSize | Out-Host
            $severe = @($findings | Where-Object { $_.Severity -eq 'Warn' -or $_.Severity -eq 'Error' }).Count
            if ($severe -gt 0) { Write-Warning ('有 {0} 条需要处理的发现（Warn/Error）' -f $severe) }
        } else {
            Write-Host '  未发现异常' -ForegroundColor Green
        }
    }

    # 报告导出（可选）：-OutDir 指定目录，格式来自 -Format 或配置文件
    if ($PSBoundParameters.ContainsKey('OutDir') -and -not [string]::IsNullOrWhiteSpace($OutDir)) {
        # 可为空的 class 参数不要显式传 $null，用 splat 按需拼参数
        $exportArgs = @{ OutputDirectory = $OutDir; Format = $reportFormats }
        if ($null -ne $scanResult) { $exportArgs.ScanResult = $scanResult }
        if (@($dupGroups).Count -gt 0) { $exportArgs.DuplicateGroups = $dupGroups }
        $reportFiles = Export-WsReport @exportArgs -WhatIf:$WhatIfPreference
        Write-WsHeader ('报告已导出到 {0}:' -f $OutDir)
        foreach ($file in @($reportFiles)) { Write-Host ('  ' + $file) }
    }

    exit 0
} catch {
    Write-Error ('WsDoctor 执行失败: ' + $_.Exception.Message)
    exit 1
}
