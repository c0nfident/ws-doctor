# run.ps1 — 启动 WsDoctor GUI（C# WinForms，需 STA 线程）
# 用法：
#   pwsh -STA -NoProfile -File .\run.ps1                  # 打开窗口
#   pwsh -STA -NoProfile -File .\run.ps1 -SelfTest        # 运行 C# 自检
#   pwsh -STA -NoProfile -File .\run.ps1 -Screenshot out.png  # 离屏渲染截图
[CmdletBinding()]
param(
    [switch]$SelfTest,
    [switch]$Integration,
    [string]$Screenshot,
    [switch]$Rebuild
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$guiRoot = $PSScriptRoot
$outputDll = Join-Path $guiRoot 'bin\WsDoctorGui.dll'
# 告诉 C# 侧项目根目录（gui 的上一级）
$env:WSDOC_GUI_ROOT = Split-Path -Parent $guiRoot

$buildArgs = @{}
if ($Rebuild) { $buildArgs.Force = $true }
& (Join-Path $guiRoot 'build.ps1') @buildArgs | Out-Host
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$assembly = [System.Reflection.Assembly]::LoadFrom($outputDll)
$programType = $assembly.GetType('WsDoctorGui.Program')
if ($null -eq $programType) { throw '找不到 WsDoctorGui.Program 类型' }

if ($SelfTest) {
    $exitCode = [int]$programType.GetMethod('RunSelfTest').Invoke($null, @())
    exit $exitCode
}

if ($Integration) {
    $exitCode = [int]$programType.GetMethod('RunIntegrationTest').Invoke($null, @())
    exit $exitCode
}

if ($Screenshot) {
    $fullPath = if ([System.IO.Path]::IsPathRooted($Screenshot)) { $Screenshot } else { Join-Path (Get-Location) $Screenshot }
    try {
        [void]$programType.GetMethod('RenderScreenshot').Invoke($null, @($fullPath))
    } catch {
        $inner = $_.Exception.InnerException
        Write-Host '[gui] 截图失败:' -ForegroundColor Red
        Write-Host ($inner ?? $_.Exception).ToString()
        exit 1
    }
    Write-Host ('[gui] 截图已保存: ' + $fullPath) -ForegroundColor Green
    exit 0
}

[void]$programType.GetMethod('RunGui').Invoke($null, @())
exit 0
