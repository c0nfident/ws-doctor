# build.ps1 — 用 PowerShell 自带的 Roslyn 编译 C# GUI（无需 dotnet SDK）
# 练习点：Microsoft.CodeAnalysis API、MetadataReference、编译诊断、增量构建
[CmdletBinding()]
param(
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$guiRoot = $PSScriptRoot
$srcDir = Join-Path $guiRoot 'src'
$binDir = Join-Path $guiRoot 'bin'
$outputDll = Join-Path $binDir 'WsDoctorGui.dll'

$sources = @(Get-ChildItem -LiteralPath $srcDir -Filter '*.cs' -File -Recurse | Sort-Object FullName)
if ($sources.Count -eq 0) { throw 'src 下没有 .cs 文件' }

# 增量构建：所有源文件都不比 dll 新则跳过
if (-not $Force -and (Test-Path -LiteralPath $outputDll)) {
    $dllTime = (Get-Item -LiteralPath $outputDll).LastWriteTimeUtc
    $newer = $sources | Where-Object { $_.LastWriteTimeUtc -gt $dllTime }
    if (-not $newer) {
        Write-Host ('[build] 已是最新: ' + $outputDll)
        exit 0
    }
}

if (-not (Test-Path -LiteralPath $binDir -PathType Container)) {
    New-Item -ItemType Directory -Path $binDir -Force | Out-Null
}

$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
[System.Reflection.Assembly]::LoadFrom((Join-Path $PSHOME 'Microsoft.CodeAnalysis.dll')) | Out-Null
[System.Reflection.Assembly]::LoadFrom((Join-Path $PSHOME 'Microsoft.CodeAnalysis.CSharp.dll')) | Out-Null

# 引用：PS 运行时里全部托管程序集（含 WinForms / Drawing / Text.Json）
$references = [System.Collections.Generic.List[Microsoft.CodeAnalysis.MetadataReference]]::new()
foreach ($dll in Get-ChildItem -LiteralPath $PSHOME -Filter '*.dll') {
    try {
        $null = [System.Reflection.AssemblyName]::GetAssemblyName($dll.FullName)
    } catch {
        continue
    }
    $references.Add([Microsoft.CodeAnalysis.MetadataReference]::CreateFromFile($dll.FullName))
}

$trees = [System.Collections.Generic.List[Microsoft.CodeAnalysis.SyntaxTree]]::new()
foreach ($source in $sources) {
    $text = [System.IO.File]::ReadAllText($source.FullName)
    $tree = [Microsoft.CodeAnalysis.CSharp.CSharpSyntaxTree]::ParseText($text)
    $trees.Add($tree)
}

$options = [Microsoft.CodeAnalysis.CSharp.CSharpCompilationOptions]::new([Microsoft.CodeAnalysis.OutputKind]::DynamicallyLinkedLibrary)
$options = $options.WithNullableContextOptions([Microsoft.CodeAnalysis.NullableContextOptions]::Enable)
$options = $options.WithOptimizationLevel([Microsoft.CodeAnalysis.OptimizationLevel]::Release)
$options = $options.WithPlatform([Microsoft.CodeAnalysis.Platform]::AnyCpu)

$compilation = [Microsoft.CodeAnalysis.CSharp.CSharpCompilation]::Create(
    'WsDoctorGui',
    [Microsoft.CodeAnalysis.SyntaxTree[]]$trees.ToArray(),
    [Microsoft.CodeAnalysis.MetadataReference[]]$references.ToArray(),
    $options
)

$stream = [System.IO.MemoryStream]::new()
try {
    $emitResult = $compilation.Emit($stream)
    if (-not $emitResult.Success) {
        $errorList = @($emitResult.Diagnostics | Where-Object { $_.Severity -eq 'Error' })
        Write-Host ('[build] 编译失败（{0} 项错误）:' -f $errorList.Count) -ForegroundColor Red
        $errorLines = foreach ($diagnostic in $errorList) {
            $lineSpan = $diagnostic.Location.GetLineSpan()
            $path = [string]$lineSpan.Path
            $fileName = if ([string]::IsNullOrWhiteSpace($path)) { '<no-file>' } else { Split-Path $path -Leaf }
            ('{0}({1},{2}): {3}' -f $fileName, ($lineSpan.StartLinePosition.Line + 1), ($lineSpan.StartLinePosition.Character + 1), $diagnostic.GetMessage())
        }
        $errorLines | Set-Content -LiteralPath (Join-Path $binDir 'compile-errors.txt') -Encoding UTF8
        $errorLines | Select-Object -First 30 | ForEach-Object { Write-Host ('  ' + $_) -ForegroundColor Red }
        exit 1
    }
    [System.IO.File]::WriteAllBytes($outputDll, $stream.ToArray())
} finally {
    $stream.Dispose()
}

$stopwatch.Stop()
$size = [math]::Round((Get-Item -LiteralPath $outputDll).Length / 1KB, 1)
Write-Host ('[build] OK: {0} ({1} KB, {2} 个源文件, {3:N0} ms)' -f
    (Split-Path $outputDll -Leaf), $size, $sources.Count, $stopwatch.Elapsed.TotalMilliseconds) -ForegroundColor Green
exit 0
