# pack.ps1 — 打包发布 zip + SHA256 校验和（v0.8）
# 练习点：SupportsShouldProcess 打包演练（先算文件清单再动手）、ZipFile.CreateFromDirectory、Get-FileHash
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [string]$OutputDirectory = (Join-Path $PSScriptRoot 'dist')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = $PSScriptRoot
$manifest = Import-PowerShellDataFile -LiteralPath (Join-Path $root 'WsDoctor.psd1')
$version = [string]$manifest.ModuleVersion
$zipName = 'wsdoctor-{0}.zip' -f $version
$zipPath = Join-Path $OutputDirectory $zipName

$includeDirs = @('config', 'formats', 'bench', 'tests', 'docs', 'install', 'gui')
$includeFiles = @(
    'WsDoctor.psm1', 'WsDoctor.psd1', 'wsdoctor.ps1',
    'build.ps1', 'lint-wsdoctor.ps1', 'pack.ps1'
)

# 1) 先算清单（不落盘），保证 -WhatIf 只读、不产生半成品
$sources = [System.Collections.Generic.List[object]]::new()
foreach ($file in $includeFiles) {
    $source = Join-Path $root $file
    if (Test-Path -LiteralPath $source) {
        $sources.Add([pscustomobject]@{ Source = $source; Relative = $file })
    }
}
foreach ($dir in $includeDirs) {
    $sourceDir = Join-Path $root $dir
    if (-not (Test-Path -LiteralPath $sourceDir -PathType Container)) { continue }
    foreach ($file in Get-ChildItem -LiteralPath $sourceDir -Recurse -File) {
        $relative = $file.FullName.Substring($root.Length + 1)
        if ($relative -match '\\bin\\|\\obj\\|\\dist-exe\\|\\dist-selfcontained\\|\\.dotnet-home\\|\\signing\\') { continue }
        $sources.Add([pscustomobject]@{ Source = $file.FullName; Relative = $relative })
    }
}
$plan = @($sources | Sort-Object Relative)
$totalBytes = ($plan | ForEach-Object { (Get-Item -LiteralPath $_.Source).Length } | Measure-Object -Sum).Sum
if ($null -eq $totalBytes) { $totalBytes = 0 }

Write-Host ('打包计划: {0} 个文件 / {1:N1} KB → {2}' -f $plan.Count, ($totalBytes / 1KB), $zipPath)
foreach ($item in $plan) { Write-Host ('  ' + $item.Relative) }

if (-not $PSCmdlet.ShouldProcess($zipPath, ('打包 v' + $version))) {
    return
}

# 2) 暂存到临时目录（保留相对结构），再压缩
$stage = Join-Path ([System.IO.Path]::GetTempPath()) ('wsdoctor-stage-' + [guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path $stage -Force | Out-Null
    foreach ($item in $plan) {
        $destination = Join-Path $stage $item.Relative
        $destinationDir = Split-Path -Parent $destination
        if (-not (Test-Path -LiteralPath $destinationDir -PathType Container)) {
            New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
        }
        Copy-Item -LiteralPath $item.Source -Destination $destination -Force
    }

    if (-not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
    }
    if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::CreateFromDirectory($stage, $zipPath, [System.IO.Compression.CompressionLevel]::Optimal, $false)

    $hash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash
    $hashFile = $zipPath + '.sha256'
    ('{0}  {1}' -f $hash, $zipName) | Set-Content -LiteralPath $hashFile -Encoding ascii

    $zipItem = Get-Item -LiteralPath $zipPath
    Write-Host ('完成: {0}  ({1:N1} KB)' -f $zipItem.Name, ($zipItem.Length / 1KB)) -ForegroundColor Green
    Write-Host ('SHA256: {0}' -f $hash)
    Write-Host ('校验文件: {0}' -f $hashFile)
} finally {
    if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue }
}
