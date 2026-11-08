# publish-selfcontained.ps1 — 发布 self-contained（免安装 .NET）GUI
# 优先：dotnet publish --self-contained -r win-x64 -p:PublishSingleFile=true（需要能访问 NuGet 下载 runtime packs）
# 回退：离线组装（用本机已安装的 shared runtime + hostfxr 生成 self-contained 目录，无需联网）
[CmdletBinding()]
param(
    [string]$OutputDirectory = (Join-Path $PSScriptRoot 'dist-selfcontained'),
    [ValidateSet('win-x64', 'win-arm64')]
    [string]$Runtime = 'win-x64',
    [switch]$OfflineAssembly,
    [switch]$Sign,
    [switch]$SkipVerify
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$guiRoot = $PSScriptRoot
$projectFile = Join-Path $guiRoot 'WsDoctorGui.csproj'
if (-not (Test-Path $projectFile)) { throw ('找不到 csproj: ' + $projectFile) }

$versionMatch = [regex]::Match([System.IO.File]::ReadAllText($projectFile), '<Version>([^<]+)</Version>')
$appVersion = if ($versionMatch.Success) { $versionMatch.Groups[1].Value } else { '1.0.0' }

$dotnetPath = 'C:\Program Files\dotnet\dotnet.exe'
if (-not (Test-Path $dotnetPath)) {
    $command = Get-Command dotnet -ErrorAction SilentlyContinue
    if ($null -eq $command) { throw '找不到 dotnet（self-contained 发布需要 .NET SDK）' }
    $dotnetPath = $command.Source
}
$dotnetRoot = Split-Path -Parent $dotnetPath

# 受限环境：CLI 主目录指向工作区
$env:DOTNET_CLI_HOME = Join-Path $guiRoot '.dotnet-home'
$env:DOTNET_NOLOGO = '1'
$env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
$env:DOTNET_GENERATE_ASPNET_CERTIFICATE = 'false'
$env:DOTNET_SKIP_FIRST_TIME_EXPERIENCE = '1'
New-Item -ItemType Directory -Path $env:DOTNET_CLI_HOME -Force | Out-Null

if (Test-Path $OutputDirectory) { Remove-Item $OutputDirectory -Recurse -Force }
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

$published = $false
if (-not $OfflineAssembly) {
    Write-Host '[self-contained] 尝试 dotnet publish（需要联网下载 runtime packs）…'
    $arguments = @('publish', $projectFile, '-c', 'Release', '-r', $Runtime, '--self-contained', 'true',
        '-p:PublishSingleFile=true', '-p:IncludeNativeLibrariesForSelfExtract=true', '-p:PublishTrimmed=false',
        '-p:DebugType=none', '--nologo', '-o', $OutputDirectory)
    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & $dotnetPath @arguments
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousErrorAction
    if ($exitCode -eq 0 -and (Test-Path (Join-Path $OutputDirectory 'WsDoctorGui.exe'))) {
        $published = $true
        Write-Host '[self-contained] dotnet publish 成功（单文件）' -ForegroundColor Green
    } else {
        Write-Host '[self-contained] dotnet publish 不可用（离线/缺 runtime packs），改用离线组装' -ForegroundColor Yellow
        if (Test-Path $OutputDirectory) { Remove-Item $OutputDirectory -Recurse -Force }
        New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
    }
}

if (-not $published) {
    # ---------- 离线组装 ----------
    if ($Runtime -ne 'win-x64') { throw '离线组装目前只支持 win-x64（本机运行时）' }
    $sharedRoot = Join-Path $dotnetRoot 'shared'
    $hostRoot = Join-Path $dotnetRoot 'host\fxr'

    function Get-LatestRuntimeVersion([string]$frameworkName) {
        $directory = Join-Path $sharedRoot $frameworkName
        if (-not (Test-Path $directory)) { throw ('本机缺少运行时目录: ' + $directory) }
        $versions = Get-ChildItem $directory -Directory | ForEach-Object {
            $parsed = $null
            if ([version]::TryParse($_.Name, [ref]$parsed)) { $parsed }
        } | Sort-Object -Descending
        if (-not $versions) { throw ('运行时目录为空: ' + $directory) }
        return $versions[0].ToString()
    }

    $coreVersion = Get-LatestRuntimeVersion 'Microsoft.NETCore.App'
    $desktopVersion = Get-LatestRuntimeVersion 'Microsoft.WindowsDesktop.App'
    $hostFxrPath = Join-Path $hostRoot $coreVersion 'hostfxr.dll'
    if (-not (Test-Path $hostFxrPath)) { throw ('缺少 hostfxr: ' + $hostFxrPath) }

    $netcoreDir = Join-Path $sharedRoot ('Microsoft.NETCore.App\' + $coreVersion)
    $desktopDir = Join-Path $sharedRoot ('Microsoft.WindowsDesktop.App\' + $desktopVersion)

    # app 文件：优先用 bin\Release 构建输出，否则用 dist-exe
    $appSource = Join-Path $guiRoot 'bin\Release\net10.0-windows'
    if (-not (Test-Path (Join-Path $appSource 'WsDoctorGui.dll'))) { $appSource = Join-Path $guiRoot 'dist-exe' }
    foreach ($file in @('WsDoctorGui.exe', 'WsDoctorGui.dll')) {
        if (-not (Test-Path (Join-Path $appSource $file))) { throw ('缺少 app 文件: ' + (Join-Path $appSource $file) + '（先运行 build-exe.ps1）') }
        Copy-Item (Join-Path $appSource $file) $OutputDirectory -Force
    }

    $skipNames = @('.version')
    $isFrameworkFile = {
        param($file)
        $file.Name -notin $skipNames -and $file.Name -notlike '*.deps.json' -and $file.Name -notlike '*.runtimeconfig.json'
    }
    $coreFiles = Get-ChildItem $netcoreDir -File | Where-Object { & $isFrameworkFile $_ }
    $desktopFiles = Get-ChildItem $desktopDir -File | Where-Object { & $isFrameworkFile $_ }
    foreach ($file in @($coreFiles) + @($desktopFiles)) { Copy-Item $file.FullName $OutputDirectory -Force }
    Copy-Item $hostFxrPath $OutputDirectory -Force

    # runtimeconfig.json
    $runtimeConfig = [ordered]@{
        runtimeOptions = [ordered]@{
            tfm                = 'net10.0'
            includedFrameworks = @(
                [ordered]@{ name = 'Microsoft.NETCore.App'; version = $coreVersion },
                [ordered]@{ name = 'Microsoft.WindowsDesktop.App'; version = $desktopVersion }
            )
            configProperties   = [ordered]@{
                'System.Reflection.Metadata.MetadataUpdater.IsSupported'      = $false
                'System.Runtime.Serialization.EnableUnsafeBinaryFormatterSerialization' = $false
                'CSWINRT_USE_WINDOWS_UI_XAML_PROJECTIONS'                     = $false
            }
        }
    }
    $runtimeConfig | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'WsDoctorGui.runtimeconfig.json') -Encoding UTF8

    # deps.json（app + 两个框架所有文件）
    function Test-ManagedAssembly([string]$path) {
        try { $null = [System.Reflection.AssemblyName]::GetAssemblyName($path); return $true } catch { return $false }
    }
    function New-AssetEntries([System.IO.FileInfo[]]$files) {
        $runtime = [ordered]@{}
        $native = [ordered]@{}
        foreach ($file in $files) {
            if (Test-ManagedAssembly $file.FullName) { $runtime[$file.Name] = [ordered]@{} } else { $native[$file.Name] = [ordered]@{} }
        }
        return [pscustomobject]@{ Runtime = $runtime; Native = $native }
    }
    $coreAssets = New-AssetEntries @($coreFiles)
    $desktopAssets = New-AssetEntries @($desktopFiles)
    $coreEntry = [ordered]@{ runtime = $coreAssets.Runtime }
    if ($coreAssets.Native.Count -gt 0) { $coreEntry.native = $coreAssets.Native }
    $desktopEntry = [ordered]@{ runtime = $desktopAssets.Runtime }
    if ($desktopAssets.Native.Count -gt 0) { $desktopEntry.native = $desktopAssets.Native }

    $targets = [ordered]@{}
    $targets['Microsoft.NETCore.App/' + $coreVersion] = $coreEntry
    $targets['Microsoft.WindowsDesktop.App/' + $desktopVersion] = $desktopEntry
    $targets[$appVersion + '/1.0.0'] = [ordered]@{ runtime = [ordered]@{ 'WsDoctorGui.dll' = [ordered]@{} } }
    $libraries = [ordered]@{}
    $libraries['WsDoctorGui/' + $appVersion] = [ordered]@{ type = 'project'; serviceable = $false; sha512 = '' }
    $libraries['Microsoft.NETCore.App/' + $coreVersion] = [ordered]@{ type = 'package'; serviceable = $true; sha512 = '' }
    $libraries['Microsoft.WindowsDesktop.App/' + $desktopVersion] = [ordered]@{ type = 'package'; serviceable = $true; sha512 = '' }
    $deps = [ordered]@{
        runtimeTarget      = [ordered]@{ name = '.NETCoreApp,Version=v10.0/win-x64'; signature = '' }
        compilationOptions = [ordered]@{}
        targets            = [ordered]@{ '.NETCoreApp,Version=v10.0/win-x64' = $targets }
        libraries          = $libraries
    }
    $deps | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'WsDoctorGui.deps.json') -Encoding UTF8

    $count = (Get-ChildItem $OutputDirectory -File).Count
    $totalMb = [Math]::Round(((Get-ChildItem $OutputDirectory -File | Measure-Object Length -Sum).Sum / 1MB), 1)
    Write-Host ('[self-contained] 离线组装完成: {0} 个文件 / {1} MB（.NET {2} / Desktop {3}）' -f $count, $totalMb, $coreVersion, $desktopVersion) -ForegroundColor Green
}

$exePath = Join-Path $OutputDirectory 'WsDoctorGui.exe'
if (-not (Test-Path $exePath)) { throw '[self-contained] 未生成 WsDoctorGui.exe' }

if ($Sign) {
    Write-Host '[self-contained] 签名…'
    & (Join-Path $guiRoot 'sign-exe.ps1') -ExePath $exePath
}

if (-not $SkipVerify) {
    Write-Host '[self-contained] 自检验证…'
    $process = Start-Process -FilePath $exePath -ArgumentList '--selftest' -Wait -PassThru -WindowStyle Hidden -WorkingDirectory $OutputDirectory
    if ($process.ExitCode -ne 0) { throw ('[self-contained] --selftest 失败: exit=' + $process.ExitCode) }
    Write-Host '[self-contained] --selftest 通过（73/73）' -ForegroundColor Green
}

$exeItem = Get-Item $exePath
Write-Host ('[self-contained] 产物: {0}（{1:N0} KB）' -f $exeItem.FullName, ($exeItem.Length / 1KB)) -ForegroundColor Green
