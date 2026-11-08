# build-exe.ps1 — 用 VS Code 自动安装的 .NET SDK 构建独立 exe（v1.1）
# 产物：gui\dist-exe\WsDoctorGui.exe（框架依赖单文件，需要 .NET 10 WindowsDesktop 运行时；
#       本机已被 VS Code 的 .NET Install Tool 安装好）
[CmdletBinding()]
param(
    [switch]$SelfContained,
    [string]$OutputDirectory = (Join-Path $PSScriptRoot 'dist-exe')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$guiRoot = $PSScriptRoot
$projectFile = Join-Path $guiRoot 'WsDoctorGui.csproj'
if (-not (Test-Path $projectFile)) { throw ('找不到 csproj: ' + $projectFile) }

# 定位 dotnet
$dotnetPath = 'C:\Program Files\dotnet\dotnet.exe'
if (-not (Test-Path $dotnetPath)) {
    $command = Get-Command dotnet -ErrorAction SilentlyContinue
    if ($null -eq $command) { throw '找不到 dotnet（请先安装 .NET 10 SDK，或让 VS Code 的 C# 扩展自动安装）' }
    $dotnetPath = $command.Source
}
Write-Host ('[build-exe] dotnet: ' + $dotnetPath) -ForegroundColor Cyan
& $dotnetPath --version

# 受限环境（DSH 沙箱）下 ~ 不可写，把 CLI 主目录指到项目内
$env:DOTNET_CLI_HOME = Join-Path $guiRoot '.dotnet-home'
$env:DOTNET_NOLOGO = '1'
$env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
$env:DOTNET_GENERATE_ASPNET_CERTIFICATE = 'false'
$env:DOTNET_SKIP_FIRST_TIME_EXPERIENCE = '1'
New-Item -ItemType Directory -Path $env:DOTNET_CLI_HOME -Force | Out-Null

# 无 RID 的普通 build：不需要 runtime pack，不访问 NuGet（配合 gui\NuGet.config 清空源）
$buildArguments = [System.Collections.Generic.List[string]]::new()
$buildArguments.AddRange([string[]]@('build', $projectFile, '-c', 'Release', '--nologo', '-v', 'minimal'))
if ($SelfContained) {
    $buildArguments.AddRange([string[]]@('-p:SelfContained=true', '-r', 'win-x64'))
}

Write-Host ('[build-exe] dotnet ' + ($buildArguments -join ' ')) -ForegroundColor DarkGray
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
& $dotnetPath @buildArguments
$exitCode = $LASTEXITCODE
$stopwatch.Stop()
if ($exitCode -ne 0) {
    Write-Host ('[build-exe] 构建失败（exit=' + $exitCode + '）') -ForegroundColor Red
    exit $exitCode
}

$buildOutput = Join-Path $guiRoot 'bin\Release\net10.0-windows'
$required = @('WsDoctorGui.exe', 'WsDoctorGui.dll', 'WsDoctorGui.runtimeconfig.json', 'WsDoctorGui.deps.json')
foreach ($file in $required) {
    if (-not (Test-Path (Join-Path $buildOutput $file))) {
        Write-Host ('[build-exe] 缺少构建产物: ' + $file) -ForegroundColor Red
        exit 1
    }
}
if (Test-Path $OutputDirectory) { Remove-Item $OutputDirectory -Recurse -Force }
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
foreach ($file in Get-ChildItem $buildOutput -File) {
    Copy-Item -LiteralPath $file.FullName -Destination $OutputDirectory -Force
}
$exeItem = Get-Item (Join-Path $OutputDirectory 'WsDoctorGui.exe')
$totalKb = [math]::Round(((Get-ChildItem $OutputDirectory -File | Measure-Object -Property Length -Sum).Sum / 1KB), 1)
Write-Host ('[build-exe] OK: {0} + {1} 个文件, 共 {2} KB, {3:N0} ms' -f $exeItem.Name, ((Get-ChildItem $OutputDirectory -File).Count - 1), $totalKb, $stopwatch.Elapsed.TotalMilliseconds) -ForegroundColor Green
Write-Host '[build-exe] 用法: .\WsDoctorGui.exe        # 打开窗口'
Write-Host '          .\WsDoctorGui.exe --selftest # C# 自检'
exit 0
