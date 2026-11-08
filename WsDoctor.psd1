@{
    RootModule        = 'WsDoctor.psm1'
    ModuleVersion     = '1.4.0'
    GUID              = 'b6f0c6d4-3a8e-4f2b-9c71-8f4a2d1e5c90'
    Author            = 'confident'
    CompanyName       = 'personal'
    Copyright         = '(c) 2026 confident. MIT License.'
    Description       = '工作区体检工具（v1.0）：体积扫描（串行/DirBucket 并行）、重复文件检测、空目录清理、JSON 配置与多格式报告、规则体检、打包与周计划任务'
    PowerShellVersion = '7.0'

    FunctionsToExport = @('Invoke-WsScan', 'Find-WsDuplicateFile', 'Measure-WsDuplicateWork', 'Measure-WsScanWork', 'Remove-WsEmptyDirectory', 'Format-WsSize', 'Import-WsConfig', 'Export-WsReport', 'Invoke-WsWorkspaceAudit')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    FormatsToProcess  = @('formats\WsDoctor.format.ps1xml')

    PrivateData = @{
        PSData = @{
            Tags         = @('Workspace', 'DiskUsage', 'Duplicate', 'Cleanup', 'CLI')
            ProjectUri   = 'https://github.com/c0nfident/twdl-zh'
            ReleaseNotes = 'v1.4.0: self-contained 发布（免装 .NET，离线可组装）+ PowerShell 7 检测/引导 + --check-env 环境检查'
        }
    }
}
