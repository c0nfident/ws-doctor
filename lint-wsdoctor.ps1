# lint-wsdoctor.ps1 — 用 PowerShell AST 做静态检查（v0.7：规则分级 + 批准动词 + 命名/长度/路径规则）
# 练习点：Parser::ParseFile / AST 遍历 / 规则引擎（Error/Warn 分级）/ Get-Verb / 退出码
[CmdletBinding()]
param(
    [string]$Root = $PSScriptRoot,
    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$aliasBlacklist = @(
    '%', '?', 'gci', 'ls', 'dir', 'cat', 'gc', 'sc', 'cp', 'copy', 'mv', 'move', 'ren',
    'rm', 'del', 'ri', 'echo', 'write', 'type', 'select', 'where', 'sort', 'measure',
    'group', 'ft', 'fl', 'ni', 'mi', 'mkdir', 'md', 'pushd', 'popd', 'cls', 'clear',
    'sleep', 'start', 'kill', 'ps', 'gi', 'si', 'ipmo', 'gmo'
)
$approvedVerbs = @((Get-Verb).Verb)
$maxFunctionLines = 150

$targets = @(
    (Join-Path $Root 'WsDoctor.psm1'),
    (Join-Path $Root 'wsdoctor.ps1'),
    (Join-Path $Root 'build.ps1')
)
$targets += @(Get-ChildItem -LiteralPath (Join-Path $Root 'tests') -Filter '*.ps1' -File -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty FullName)
$targets += @(Get-ChildItem -LiteralPath (Join-Path $Root 'install') -Filter '*.ps1' -File -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty FullName)
$targets += (Join-Path $Root 'pack.ps1')
$targets = @($targets | Where-Object { Test-Path -LiteralPath $_ })

$findings = [System.Collections.Generic.List[pscustomobject]]::new()

function Add-Finding {
    param(
        [ValidateSet('Error', 'Warn')][string]$Level,
        [string]$Rule,
        [string]$File,
        [int]$Line,
        [string]$Message
    )
    $findings.Add([pscustomobject]@{
        Level   = $Level
        Rule    = $Rule
        File    = $File
        Line    = $Line
        Message = $Message
    })
}

foreach ($file in $targets) {
    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$tokens, [ref]$errors)
    $isModule = $file -like '*.psm1'

    foreach ($parseError in $errors) {
        Add-Finding -Level Error -Rule 'ParseError' -File $file -Line $parseError.Extent.StartLineNumber -Message $parseError.Message
    }

    $commands = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true))
    $functions = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))

    # 规则：禁止别名（全部文件）
    foreach ($cmd in $commands) {
        $name = $cmd.GetCommandName()
        if ($name -and $aliasBlacklist -contains $name.ToLowerInvariant()) {
            Add-Finding -Level Error -Rule 'NoAlias' -File $file -Line $cmd.Extent.StartLineNumber -Message ('不要使用别名: ' + $name)
        }
    }

    # 规则：参数名必须 PascalCase（全部函数）
    foreach ($function in $functions) {
        $parameters = @()
        if ($function.Body.ParamBlock) { $parameters = @($function.Body.ParamBlock.Parameters) }
        foreach ($parameter in $parameters) {
            $paramName = $parameter.Name.VariablePath.UserPath
            if ($paramName -cnotmatch '^[A-Z]') {
                Add-Finding -Level Warn -Rule 'ParamPascalCase' -File $file -Line $parameter.Extent.StartLineNumber -Message ('参数名建议 PascalCase: $' + $paramName)
            }
        }
        # 规则：函数体过长（Warn，>150 行）
        $lineCount = $function.Extent.EndLineNumber - $function.Extent.StartLineNumber + 1
        if ($lineCount -gt $maxFunctionLines) {
            Add-Finding -Level Warn -Rule 'FunctionTooLong' -File $file -Line $function.Extent.StartLineNumber -Message ('函数 {0} 有 {1} 行（上限 {2}）' -f $function.Name, $lineCount, $maxFunctionLines)
        }

    }

    # 模块专属规则
    if ($isModule) {
        $strict = @($commands | Where-Object { $_.GetCommandName() -eq 'Set-StrictMode' })
        if ($strict.Count -eq 0) {
            Add-Finding -Level Error -Rule 'StrictMode' -File $file -Line 1 -Message '模块缺少 Set-StrictMode -Version Latest'
        }
        foreach ($hit in @($commands | Where-Object { $_.GetCommandName() -eq 'Write-Host' })) {
            Add-Finding -Level Error -Rule 'NoWriteHost' -File $file -Line $hit.Extent.StartLineNumber -Message '模块内不要用 Write-Host，改用 Write-Verbose/Write-Information'
        }
        $hasEap = @($ast.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                    $node.Left.Extent.Text -eq '$ErrorActionPreference'
                }, $true)).Count -gt 0
        if (-not $hasEap) {
            Add-Finding -Level Warn -Rule 'ErrorActionPreference' -File $file -Line 1 -Message '模块建议设置 $ErrorActionPreference = ''Stop'''
        }
        # 规则：模块代码中不应出现绝对盘符路径字面量（可移植性）
        $strings = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true))
        foreach ($stringNode in $strings) {
            if ($stringNode.Value -match '^[A-Za-z]:\\') {
                Add-Finding -Level Error -Rule 'AbsolutePathLiteral' -File $file -Line $stringNode.Extent.StartLineNumber -Message ('模块内出现绝对路径字面量: ' + $stringNode.Value)
            }
        }
    }
}

# 规则：模块清单里的导出函数必须存在、是高级函数、且使用批准动词
$moduleFile = Join-Path $Root 'WsDoctor.psm1'
$manifestFile = Join-Path $Root 'WsDoctor.psd1'
if ((Test-Path $moduleFile) -and (Test-Path $manifestFile)) {
    $manifest = Import-PowerShellDataFile -LiteralPath $manifestFile
    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($moduleFile, [ref]$tokens, [ref]$errors)
    $functions = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))
    foreach ($exported in $manifest.FunctionsToExport) {
        $verb = ([string]$exported).Split('-')[0]
        if ($approvedVerbs -notcontains $verb) {
            Add-Finding -Level Error -Rule 'ApprovedVerb' -File $manifestFile -Line 1 -Message ('导出函数不使用批准动词: ' + $exported)
        }
        $fn = $functions | Where-Object { $_.Name -eq $exported } | Select-Object -First 1
        if (-not $fn) {
            Add-Finding -Level Error -Rule 'MissingExport' -File $moduleFile -Line 1 -Message ('清单导出的函数不存在: ' + $exported)
            continue
        }
        $hasCmdletBinding = @($fn.Body.ParamBlock.Attributes | Where-Object { $_.TypeName.Name -eq 'CmdletBinding' }).Count -gt 0
        if (-not $hasCmdletBinding) {
            Add-Finding -Level Error -Rule 'AdvancedFunction' -File $moduleFile -Line $fn.Extent.StartLineNumber -Message ('导出函数缺少 [CmdletBinding()]: ' + $exported)
        }
        $hasOutputType = @($fn.Body.ParamBlock.Attributes | Where-Object { $_.TypeName.Name -eq 'OutputType' }).Count -gt 0
        if (-not $hasOutputType) {
            Add-Finding -Level Warn -Rule 'OutputType' -File $moduleFile -Line $fn.Extent.StartLineNumber -Message ('导出函数建议声明 [OutputType()]: ' + $exported)
        }
    }
}

$errorCount = @($findings | Where-Object { $_.Level -eq 'Error' }).Count
$warnCount = @($findings | Where-Object { $_.Level -eq 'Warn' }).Count

if ($Json) {
    [pscustomobject]@{
        TargetCount  = $targets.Count
        ErrorCount   = $errorCount
        WarnCount    = $warnCount
        Findings     = $findings
    } | ConvertTo-Json -Depth 4
} else {
    Write-Host ('lint: {0} 个文件，{1} 个错误，{2} 个警告' -f $targets.Count, $errorCount, $warnCount)
    foreach ($f in $findings) {
        $color = if ($f.Level -eq 'Error') { 'Red' } else { 'Yellow' }
        Write-Host ('  [{0}] {1}:{2}  {3}  {4}' -f $f.Level, (Split-Path $f.File -Leaf), $f.Line, $f.Rule, $f.Message) -ForegroundColor $color
    }
    if ($errorCount -gt 0) { Write-Host 'lint 失败（存在 Error 级问题）' -ForegroundColor Red }
}

if ($errorCount -gt 0) { exit 1 } else { exit 0 }
