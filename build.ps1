# build.ps1 — 离线质量门禁：AST lint（Error/Warn）+ Pester 测试 + 可选代码覆盖率（v0.7）
# 练习点：子脚本退出码、Pester -CodeCoverage、覆盖率阈值门禁、汇总输出
[CmdletBinding()]
param(
    [switch]$SkipLint,
    [switch]$SkipTests,
    [switch]$Coverage,
    [ValidateRange(0, 100)]
    [double]$MinCoverage = 60
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = $PSScriptRoot
$failed = $false
$sw = [System.Diagnostics.Stopwatch]::StartNew()

Write-Host '=== WsDoctor build ===' -ForegroundColor Cyan

# 1) 导入模块（语法/清单错误会在这一步暴露）
Import-Module (Join-Path $root 'WsDoctor.psd1') -Force
Write-Host ('[1/4] 模块导入 OK  ({0})' -f (Get-Module WsDoctor).Version)

# 2) AST 静态检查（Error 失败，Warn 只提示）
if ($SkipLint) {
    Write-Host '[2/4] lint 跳过'
} elseif (Test-Path (Join-Path $root 'lint-wsdoctor.ps1')) {
    & (Join-Path $root 'lint-wsdoctor.ps1') -Root $root
    if ($LASTEXITCODE -ne 0) {
        Write-Host '[2/4] lint 失败' -ForegroundColor Red
        $failed = $true
    } else {
        Write-Host '[2/4] lint 通过' -ForegroundColor Green
    }
} else {
    Write-Host '[2/4] 未找到 lint 脚本'
    $failed = $true
}

# 3) Pester（本机 3.4，语法保持兼容；-Coverage 时启用代码覆盖率）
$coveragePercent = $null
if ($SkipTests) {
    Write-Host '[3/4] 测试跳过'
} else {
    try {
        # 固定加载 Pester 3.x：测试使用 Pester 3 语法（Should Be），
        # CI runner 自带 Pester 5 时 -MinimumVersion 会加载 5 导致全部失败。
        $pester3 = Get-Module -ListAvailable Pester |
            Where-Object { $_.Version -ge [version]'3.0' -and $_.Version -lt [version]'4.0' } |
            Sort-Object Version -Descending |
            Select-Object -First 1
        if ($null -eq $pester3) { throw '未安装 Pester 3.x（请安装 Pester 3.4.0）' }
        Import-Module $pester3.Path -Force -ErrorAction Stop
        $testArgs = @{ Path = (Join-Path $root 'tests'); PassThru = $true }
        if ($Coverage) { $testArgs.CodeCoverage = (Join-Path $root 'WsDoctor.psm1') }
        $testResult = Invoke-Pester @testArgs
        if ($testResult.FailedCount -gt 0) {
            Write-Host ('[3/4] 测试失败 {0} 项' -f $testResult.FailedCount) -ForegroundColor Red
            $failed = $true
        } else {
            Write-Host ('[3/4] 测试通过 {0} 项' -f $testResult.PassedCount) -ForegroundColor Green
        }
        if ($Coverage -and $testResult.CodeCoverage) {
            $analyzed = [int]$testResult.CodeCoverage.NumberOfCommandsAnalyzed
            $executed = [int]$testResult.CodeCoverage.NumberOfCommandsExecuted
            if ($analyzed -gt 0) {
                $coveragePercent = [math]::Round($executed / $analyzed * 100, 2)
                Write-Host ('[3/4] 代码覆盖率 {0}%  ({1}/{2} 条命令)' -f $coveragePercent, $executed, $analyzed)
                $missedFile = Join-Path $root 'coverage-missed.txt'
                $testResult.CodeCoverage.MissedCommands |
                    Select-Object File, Function, Line, Command |
                    Format-Table -AutoSize |
                    Out-String |
                    Set-Content -LiteralPath $missedFile -Encoding UTF8
                Write-Host ('      未覆盖明细已写入 {0}' -f $missedFile)
            }
        }
    } catch {
        Write-Host ('[3/4] Pester 不可用: ' + $_.Exception.Message) -ForegroundColor Red
        $failed = $true
    }
}

# 4) 覆盖率门禁
if ($Coverage) {
    if ($null -eq $coveragePercent) {
        Write-Host '[4/4] 覆盖率不可用' -ForegroundColor Red
        $failed = $true
    } elseif ($coveragePercent -lt $MinCoverage) {
        Write-Host ('[4/4] 覆盖率 {0}% 低于阈值 {1}%' -f $coveragePercent, $MinCoverage) -ForegroundColor Red
        $failed = $true
    } else {
        Write-Host ('[4/4] 覆盖率 {0}% ≥ 阈值 {1}%' -f $coveragePercent, $MinCoverage) -ForegroundColor Green
    }
} else {
    Write-Host '[4/4] 覆盖率未启用（加 -Coverage 开启）'
}

$sw.Stop()
if ($failed) {
    Write-Host ('=== FAILED  ({0:N0} ms) ===' -f $sw.Elapsed.TotalMilliseconds) -ForegroundColor Red
    exit 1
}
Write-Host ('=== BUILD OK  ({0:N0} ms) ===' -f $sw.Elapsed.TotalMilliseconds) -ForegroundColor Green
exit 0
