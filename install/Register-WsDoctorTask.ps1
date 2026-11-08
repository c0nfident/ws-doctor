# install/Register-WsDoctorTask.ps1 — 注册/删除"每周工作区体检"计划任务（v0.8）
# 练习点：计划任务参数构造、SupportsShouldProcess、-WhatIf 只打印计划（不触碰 CIM）
# 注意：实际注册必须在**本机普通终端**运行（沙箱会拦截 CIM 访问）；这里保证预览永远可用。
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory, Position = 0)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
    [string]$Path,

    [string]$TaskName = 'WsDoctor Weekly Audit',

    [ValidateSet('Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday')]
    [string]$DayOfWeek = 'Saturday',

    [ValidatePattern('^([01]\d|2[0-3]):[0-5]\d$')]
    [string]$Time = '09:00',

    [string]$OutDir,

    [string]$PwshPath,

    [switch]$Unregister
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$cliPath = Join-Path $root 'wsdoctor.ps1'
if (-not (Test-Path -LiteralPath $cliPath)) {
    throw ('找不到 wsdoctor.ps1: ' + $cliPath)
}
$workspacePath = (Resolve-Path -LiteralPath $Path).ProviderPath
if (-not $PwshPath) {
    $PwshPath = (Get-Command pwsh -ErrorAction Stop).Source
}

if ($Unregister) {
    if ($PSCmdlet.ShouldProcess($TaskName, '删除计划任务')) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction Stop
        Write-Host ('已删除计划任务: ' + $TaskName) -ForegroundColor Green
    } else {
        Write-Host ('[WhatIf] 将删除计划任务: {0}' -f $TaskName)
    }
    return
}

$argumentList = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -Path "{1}" -Audit' -f $cliPath, $workspacePath
if ($OutDir) { $argumentList += (' -OutDir "{0}"' -f $OutDir) }

Write-Host ('计划任务: {0}' -f $TaskName)
Write-Host ('  程序: {0}' -f $PwshPath)
Write-Host ('  参数: {0}' -f $argumentList)
Write-Host ('  触发: 每周 {0} {1}' -f $DayOfWeek, $Time)
Write-Host '  权限: 当前登录用户，RunLevel Limited（普通权限即可）'
Write-Host '  说明: 实际注册需在本机普通终端执行（沙箱环境会拦截 CIM / 计划任务服务）'

if (-not $PSCmdlet.ShouldProcess($TaskName, '注册计划任务')) {
    Write-Host ('[WhatIf] 将注册计划任务: {0}' -f $TaskName) -ForegroundColor Yellow
    return
}

$action = New-ScheduledTaskAction -Execute $PwshPath -Argument $argumentList
$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek $DayOfWeek -At $Time
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
$principal = New-ScheduledTaskPrincipal -UserId ([System.Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Limited

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings `
    -Principal $principal -Description 'WsDoctor 工作区周体检（快照保留 / 残留目录 / 空目录）' -Force | Out-Null
Write-Host ('已注册计划任务: ' + $TaskName) -ForegroundColor Green
Write-Host ('查看: Get-ScheduledTask -TaskName "{0}"' -f $TaskName)
Write-Host ('立即试跑: Start-ScheduledTask -TaskName "{0}"' -f $TaskName)
Write-Host ('删除: 重新运行本脚本并加 -Unregister')
