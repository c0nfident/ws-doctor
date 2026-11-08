# WsDoctor.Tests.ps1 — Pester 3.4 兼容（本机离线可用）
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$moduleRoot = Split-Path -Parent $here
Import-Module (Join-Path $moduleRoot 'WsDoctor.psd1') -Force

Describe 'Invoke-WsScan' {

    It '统计文件数、总大小与目录数' {
        $root = Join-Path $TestDrive 'scan-basic'
        $dirA = Join-Path $root 'a'
        New-Item -ItemType Directory -Path $dirA -Force | Out-Null
        [System.IO.File]::WriteAllBytes((Join-Path $dirA 'one.bin'), [byte[]]::new(100))
        [System.IO.File]::WriteAllBytes((Join-Path $root 'two.bin'), [byte[]]::new(200))

        $result = Invoke-WsScan -Path $root -Top 5

        $result.TotalFiles | Should Be 2
        $result.TotalSize | Should Be 300
        $result.Directories.Count | Should Be 2
        $result.DurationMs | Should BeGreaterThan -1
    }

    It '默认排除 node_modules / .git 等目录' {
        $root = Join-Path $TestDrive 'scan-exclude'
        $excluded = Join-Path $root 'node_modules\lib'
        New-Item -ItemType Directory -Path $excluded -Force | Out-Null
        [System.IO.File]::WriteAllBytes((Join-Path $excluded 'dep.js'), [byte[]]::new(500))
        New-Item -ItemType Directory -Path (Join-Path $root 'src') -Force | Out-Null
        [System.IO.File]::WriteAllBytes((Join-Path $root 'src\app.ps1'), [byte[]]::new(42))

        $result = Invoke-WsScan -Path $root

        $result.TotalFiles | Should Be 1
        $result.TotalSize | Should Be 42
    }

    It 'TopFiles 按大小降序且数量受限' {
        $root = Join-Path $TestDrive 'scan-top'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        [System.IO.File]::WriteAllBytes((Join-Path $root 'small.bin'), [byte[]]::new(10))
        [System.IO.File]::WriteAllBytes((Join-Path $root 'big.bin'), [byte[]]::new(900))
        [System.IO.File]::WriteAllBytes((Join-Path $root 'mid.bin'), [byte[]]::new(100))

        $result = Invoke-WsScan -Path $root -Top 2

        $result.TopFiles.Count | Should Be 2
        (Split-Path $result.TopFiles[0].Path -Leaf) | Should Be 'big.bin'
        (Split-Path $result.TopFiles[1].Path -Leaf) | Should Be 'mid.bin'
    }

    It '不存在的路径被参数校验拒绝' {
        # 注：Pester 3.4 的 Should Throw 对参数绑定校验异常捕获不稳定，
        # 这里用 try/catch 显式断言，逻辑等价且跨版本可用
        $threw = $false
        try {
            Invoke-WsScan -Path 'Z:\definitely-not-exists' -ErrorAction Stop
        } catch {
            $threw = $true
        }
        $threw | Should Be $true
    }

    It '新旧枚举器结果完全一致（性能优化等价性）' {
        $root = Join-Path $TestDrive 'scan-equivalence'
        New-Item -ItemType Directory -Path (Join-Path $root 'a\b') -Force | Out-Null
        [System.IO.File]::WriteAllBytes((Join-Path $root 'a\b\x.bin'), [byte[]]::new(11))
        [System.IO.File]::WriteAllBytes((Join-Path $root 'a\y.bin'), [byte[]]::new(22))
        [System.IO.File]::WriteAllBytes((Join-Path $root 'z.bin'), [byte[]]::new(33))

        $fast = Invoke-WsScan -Path $root -Top 3
        $legacy = Invoke-WsScan -Path $root -Top 3 -LegacyEnumerator

        $fast.TotalFiles | Should Be $legacy.TotalFiles
        $fast.TotalSize | Should Be $legacy.TotalSize
        $fast.Directories.Count | Should Be $legacy.Directories.Count
        @($fast.TopFiles | ForEach-Object { $_.Path }) -join '|' |
            Should Be (@($legacy.TopFiles | ForEach-Object { $_.Path }) -join '|')
    }
}

Describe 'Find-WsDuplicateFile' {

    It '找出内容相同的重复文件并计算可回收空间' {
        $root = Join-Path $TestDrive 'dup-basic'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        [System.IO.File]::WriteAllBytes((Join-Path $root 'a.bin'), [byte[]]::new(300))
        [System.IO.File]::WriteAllBytes((Join-Path $root 'b.bin'), [byte[]]::new(300))
        [System.IO.File]::WriteAllBytes((Join-Path $root 'unique.bin'), [byte[]]::new(500))

        $groups = @(Find-WsDuplicateFile -Path $root -MinSize 0)

        $groups.Count | Should Be 1
        $groups[0].Files.Count | Should Be 2
        $groups[0].Wasted | Should Be 300
        $groups[0].Hash.Length | Should BeGreaterThan 32
    }

    It '同大小但内容不同不算重复' {
        $root = Join-Path $TestDrive 'dup-diff'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $a = [byte[]]::new(400)
        $b = [byte[]]::new(400)
        $a[0] = 1
        $b[0] = 2
        [System.IO.File]::WriteAllBytes((Join-Path $root 'a.bin'), $a)
        [System.IO.File]::WriteAllBytes((Join-Path $root 'b.bin'), $b)

        $groups = @(Find-WsDuplicateFile -Path $root -MinSize 0)

        $groups.Count | Should Be 0
    }

    It 'MinSize 过滤小文件' {
        $root = Join-Path $TestDrive 'dup-minsize'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        [System.IO.File]::WriteAllBytes((Join-Path $root 'a.bin'), [byte[]]::new(50))
        [System.IO.File]::WriteAllBytes((Join-Path $root 'b.bin'), [byte[]]::new(50))

        @(Find-WsDuplicateFile -Path $root).Count | Should Be 0
        @(Find-WsDuplicateFile -Path $root -MinSize 10).Count | Should Be 1
    }

    It '排除目录中的文件不参与去重' {
        $root = Join-Path $TestDrive 'dup-exclude'
        $nm = Join-Path $root 'node_modules\pkg'
        New-Item -ItemType Directory -Path $nm -Force | Out-Null
        [System.IO.File]::WriteAllBytes((Join-Path $root 'a.bin'), [byte[]]::new(300))
        [System.IO.File]::WriteAllBytes((Join-Path $nm 'copy.bin'), [byte[]]::new(300))

        $groups = @(Find-WsDuplicateFile -Path $root -MinSize 0)

        $groups.Count | Should Be 0
    }
}

Describe 'Remove-WsEmptyDirectory' {

    It '-WhatIf 只预览不删除' {
        $root = Join-Path $TestDrive 'clean-whatif'
        $nested = Join-Path $root 'a\b\c'
        New-Item -ItemType Directory -Path $nested -Force | Out-Null

        Remove-WsEmptyDirectory -Path $root -WhatIf | Out-Null

        Test-Path -LiteralPath $nested | Should Be $true
    }

    It '级联删除所有空目录，保留根目录' {
        $root = Join-Path $TestDrive 'clean-empty'
        $nested = Join-Path $root 'a\b\c'
        New-Item -ItemType Directory -Path $nested -Force | Out-Null

        $removed = Remove-WsEmptyDirectory -Path $root

        @($removed).Count | Should Be 3
        Test-Path -LiteralPath (Join-Path $root 'a') | Should Be $false
        Test-Path -LiteralPath $root | Should Be $true
    }

    It '非空目录不会被删除' {
        $root = Join-Path $TestDrive 'clean-nonempty'
        $keep = Join-Path $root 'keep'
        New-Item -ItemType Directory -Path $keep -Force | Out-Null
        [System.IO.File]::WriteAllBytes((Join-Path $keep 'data.bin'), [byte[]]::new(8))

        $removed = Remove-WsEmptyDirectory -Path $root

        @($removed).Count | Should Be 0
        Test-Path -LiteralPath (Join-Path $keep 'data.bin') | Should Be $true
    }
}

Describe 'Import-WsConfig' {

    It '默认配置包含 scan/duplicates/report 节点' {
        $cfg = Import-WsConfig
        $cfg.scan.top | Should Be 10
        @($cfg.scan.exclude).Count | Should BeGreaterThan 0
        @($cfg.report.formats).Count | Should BeGreaterThan 0
        $cfg.duplicates.minSize | Should Be 1024
    }

    It '用户配置与默认配置深合并（只写差异）' {
        $path = Join-Path $TestDrive 'user-config.json'
        '{"scan":{"top":3},"duplicates":{"minSize":2048}}' | Set-Content -LiteralPath $path -Encoding UTF8
        $cfg = Import-WsConfig -Path $path
        $cfg.scan.top | Should Be 3
        $cfg.duplicates.minSize | Should Be 2048
        $cfg.report.outDir | Should Be 'reports'
        @($cfg.scan.exclude).Count | Should BeGreaterThan 0
    }

    It 'Override 参数优先级最高' {
        $cfg = Import-WsConfig -Override @{ scan = @{ top = 7 } }
        $cfg.scan.top | Should Be 7
    }

    It '非法值抛出可读错误' {
        $threw = $false
        try { $null = Import-WsConfig -Override @{ scan = @{ top = 0 } } } catch { $threw = $true }
        $threw | Should Be $true
    }

    It 'JSON 语法错误抛出错误' {
        $path = Join-Path $TestDrive 'broken.json'
        '{ not json' | Set-Content -LiteralPath $path -Encoding UTF8
        $threw = $false
        try { $null = Import-WsConfig -Path $path } catch { $threw = $true }
        $threw | Should Be $true
    }
}

Describe 'Export-WsReport' {

    It '导出 JSON/CSV/HTML 到目录且内容可读' {
        $root = Join-Path $TestDrive 'report-src'
        New-Item -ItemType Directory -Path (Join-Path $root 'a') -Force | Out-Null
        $bytes = [byte[]]::new(300)
        [System.IO.File]::WriteAllBytes((Join-Path $root 'a\same.bin'), $bytes)
        [System.IO.File]::WriteAllBytes((Join-Path $root 'same-copy.bin'), $bytes)

        $scan = Invoke-WsScan -Path $root
        $dups = @(Find-WsDuplicateFile -Path $root -MinSize 0)
        $outDir = Join-Path $TestDrive 'report-out'
        $files = @(Export-WsReport -ScanResult $scan -DuplicateGroups $dups -OutputDirectory $outDir -Format All)

        $files.Count | Should Be 5
        foreach ($file in $files) { Test-Path -LiteralPath $file | Should Be $true }

        $jsonFile = $files | Where-Object { $_ -like '*.json' } | Select-Object -First 1
        $json = Get-Content -LiteralPath $jsonFile -Raw | ConvertFrom-Json
        $json.schemaVersion | Should Be 1
        $json.overview.totalFiles | Should Be 2
        @($json.duplicates).Count | Should Be 1

        $dirCsv = $files | Where-Object { $_ -like '*directories.csv' } | Select-Object -First 1
        @(Import-Csv -LiteralPath $dirCsv).Count | Should Be 2

        $htmlFile = $files | Where-Object { $_ -like '*.html' } | Select-Object -First 1
        $html = Get-Content -LiteralPath $htmlFile -Raw
        $html | Should Match '<table'
        $html | Should Match 'WsDoctor 体检报告'
    }

    It '既没有 ScanResult 也没有 DuplicateGroups 时抛错' {
        $threw = $false
        try { $null = Export-WsReport -OutputDirectory (Join-Path $TestDrive 'none') } catch { $threw = $true }
        $threw | Should Be $true
    }
}

Describe '格式化视图' {

    It 'WsScanResult / WsDuplicateGroup 的自定义 view 已加载' {
        (Get-FormatData -TypeName 'WsScanResult').FormatViewDefinition.Count | Should BeGreaterThan 0
        (Get-FormatData -TypeName 'WsDuplicateGroup').FormatViewDefinition.Count | Should BeGreaterThan 0
    }
}
Describe '并行扫描（v0.5）' {

    It '并行与串行结果完全一致（分块合并正确）' {
        $root = Join-Path $TestDrive 'parallel-equiv'
        for ($i = 0; $i -lt 3; $i++) {
            $dir = Join-Path $root ('d' + $i)
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            [System.IO.File]::WriteAllBytes((Join-Path $dir 'a.bin'), [byte[]]::new(100 + $i * 50))
            [System.IO.File]::WriteAllBytes((Join-Path $dir 'b.bin'), [byte[]]::new(200 + $i * 30))
        }
        [System.IO.File]::WriteAllBytes((Join-Path $root 'root.bin'), [byte[]]::new(999))

        $serial = Invoke-WsScan -Path $root -Top 5
        $parallel = Invoke-WsScan -Path $root -Top 5 -Parallel -ThrottleLimit 2

        $parallel.TotalFiles | Should Be $serial.TotalFiles
        $parallel.TotalSize | Should Be $serial.TotalSize
        $parallel.DirectoryCount | Should Be $serial.DirectoryCount
        (@($parallel.TopFiles | ForEach-Object { $_.Path }) -join '|') |
            Should Be (@($serial.TopFiles | ForEach-Object { $_.Path }) -join '|')
    }

    It '空目录并行扫描返回 0' {
        $root = Join-Path $TestDrive 'parallel-empty'
        New-Item -ItemType Directory -Path $root -Force | Out-Null

        $result = Invoke-WsScan -Path $root -Parallel -ThrottleLimit 4

        $result.TotalFiles | Should Be 0
        $result.TotalSize | Should Be 0
    }

    It '-Parallel 与 -LegacyEnumerator 互斥' {
        $threw = $false
        try {
            Invoke-WsScan -Path $TestDrive -Parallel -LegacyEnumerator -ErrorAction Stop
        } catch {
            $threw = $true
        }
        $threw | Should Be $true
    }

    It '配置文件提供 parallel / throttleLimit 默认值' {
        $cfg = Import-WsConfig
        $cfg.scan.parallel | Should Be $false
        $cfg.scan.throttleLimit | Should Be 4
    }
}
Describe 'Chunk 并行模式（v0.5）' {

    It 'Chunk 模式与串行结果一致' {
        $root = Join-Path $TestDrive 'parallel-chunk'
        for ($i = 0; $i -lt 3; $i++) {
            $dir = Join-Path $root ('c' + $i)
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            [System.IO.File]::WriteAllBytes((Join-Path $dir 'a.bin'), [byte[]]::new(120 + $i * 40))
        }
        [System.IO.File]::WriteAllBytes((Join-Path $root 'r.bin'), [byte[]]::new(800))

        $serial = Invoke-WsScan -Path $root -Top 3
        $chunk = Invoke-WsScan -Path $root -Top 3 -Parallel -ParallelMode Chunk -ThrottleLimit 2

        $chunk.TotalFiles | Should Be $serial.TotalFiles
        $chunk.TotalSize | Should Be $serial.TotalSize
        $chunk.DirectoryCount | Should Be $serial.DirectoryCount
        (@($chunk.TopFiles | ForEach-Object { $_.Path }) -join '|') |
            Should Be (@($serial.TopFiles | ForEach-Object { $_.Path }) -join '|')
    }

    It 'ParallelMode 非法值被参数校验拒绝' {
        $threw = $false
        try {
            Invoke-WsScan -Path $TestDrive -Parallel -ParallelMode 'Nope' -ErrorAction Stop
        } catch {
            $threw = $true
        }
        $threw | Should Be $true
    }
}
Describe 'DirBucket 并行（v0.6）' {

    It 'DirBucket 模式与串行结果一致' {
        $root = Join-Path $TestDrive 'dirbucket-equiv'
        for ($i = 0; $i -lt 3; $i++) {
            $dir = Join-Path $root ('b' + $i + '\sub')
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            [System.IO.File]::WriteAllBytes((Join-Path $dir 'x.bin'), [byte[]]::new(90 + $i * 20))
        }
        [System.IO.File]::WriteAllBytes((Join-Path $root 'top.bin'), [byte[]]::new(700))

        $serial = Invoke-WsScan -Path $root -Top 3
        $bucket = Invoke-WsScan -Path $root -Top 3 -Parallel -ParallelMode DirBucket -ThrottleLimit 3

        $bucket.TotalFiles | Should Be $serial.TotalFiles
        $bucket.TotalSize | Should Be $serial.TotalSize
        $bucket.DirectoryCount | Should Be $serial.DirectoryCount
        (@($bucket.TopFiles | ForEach-Object { $_.Path }) -join '|') |
            Should Be (@($serial.TopFiles | ForEach-Object { $_.Path }) -join '|')
    }

    It 'DirBucket 跳过排除目录' {
        $root = Join-Path $TestDrive 'dirbucket-exclude'
        $nm = Join-Path $root 'node_modules\pkg'
        New-Item -ItemType Directory -Path $nm -Force | Out-Null
        [System.IO.File]::WriteAllBytes((Join-Path $nm 'dep.bin'), [byte[]]::new(500))
        New-Item -ItemType Directory -Path (Join-Path $root 'src') -Force | Out-Null
        [System.IO.File]::WriteAllBytes((Join-Path $root 'src\app.bin'), [byte[]]::new(40))

        $result = Invoke-WsScan -Path $root -Parallel -ParallelMode DirBucket

        $result.TotalFiles | Should Be 1
        $result.TotalSize | Should Be 40
    }
}

Describe '工作区体检（v0.6）' {

    It '快照数量超过保留策略时给出可删项' {
        $root = Join-Path $TestDrive 'audit-snapshots'
        for ($i = 1; $i -le 5; $i++) {
            New-Item -ItemType Directory -Path (Join-Path $root ('.dsh-snapshots\2026010{0}-000000-weekly' -f $i)) -Force | Out-Null
        }
        $config = Import-WsConfig -Override @{ workspace = @{ snapshotKeep = 4 } }

        $findings = @(Invoke-WsWorkspaceAudit -Path $root -Config $config)

        @($findings | Where-Object { $_.Category -eq '快照保留' }).Count | Should Be 1
        ($findings | Where-Object { $_.Category -eq '快照保留' } | Select-Object -First 1).Message | Should Match '5'
    }

    It '命中残留规则的目录被报告' {
        $root = Join-Path $TestDrive 'audit-residue'
        New-Item -ItemType Directory -Path (Join-Path $root '2287723691') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $root 'KeepMe') -Force | Out-Null

        $findings = @(Invoke-WsWorkspaceAudit -Path $root -Config (Import-WsConfig))

        @($findings | Where-Object { $_.Category -eq '疑似残留' }).Count | Should Be 1
        ($findings | Where-Object { $_.Category -eq '疑似残留' } | Select-Object -First 1).Target | Should Match '2287723691'
    }

    It '空 temp 目录被报告' {
        $root = Join-Path $TestDrive 'audit-temp'
        New-Item -ItemType Directory -Path (Join-Path $root 'temp') -Force | Out-Null

        $findings = @(Invoke-WsWorkspaceAudit -Path $root -Config (Import-WsConfig))

        @($findings | Where-Object { $_.Category -eq '空目录' }).Count | Should Be 1
    }

    It '配置提供 workspace 默认值' {
        $cfg = Import-WsConfig
        $cfg.workspace.snapshotKeep | Should Be 4
        @($cfg.workspace.residuePatterns).Count | Should Be 2
    }
}
Describe '补充覆盖（v0.7）' {

    It 'Format-WsSize 覆盖 KB / MB / GB 三种分支' {
        Format-WsSize -Bytes 2048 | Should Be '2 KB'
        Format-WsSize -Bytes (2MB) | Should Be '2.0 MB'
        Format-WsSize -Bytes (2GB) | Should Be '2.00 GB'
    }

    It '类构造函数对非法输入抛错' {
        $fileThrew = $false
        try { $null = [WsFileItem]::new('', 1) } catch { $fileThrew = $true }
        $fileThrew | Should Be $true

        $dupThrew = $false
        try { $null = [WsDuplicateGroup]::new(1, ('a' * 64), @('only-one')) } catch { $dupThrew = $true }
        $dupThrew | Should Be $true
    }

    It 'WsDuplicateGroup 的 SizeText / WastedText / ToString 可读' {
        $root = Join-Path $TestDrive 'cover-dup-text'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $bytes = [byte[]]::new(1MB)
        [System.IO.File]::WriteAllBytes((Join-Path $root 'one.bin'), $bytes)
        [System.IO.File]::WriteAllBytes((Join-Path $root 'two.bin'), $bytes)

        $group = @(Find-WsDuplicateFile -Path $root -MinSize 0)[0]

        $group.SizeText | Should Be '1.0 MB'
        $group.WastedText | Should Be '1.0 MB'
        $group.ToString() | Should Match 'x2'
    }

    It 'WsScanItem 的 Severity 阈值分支（>100MB → Info）' {
        $root = Join-Path $TestDrive 'cover-severity'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $stream = [System.IO.File]::Create((Join-Path $root 'big.bin'))
        try { $stream.SetLength(105MB) } finally { $stream.Dispose() }

        $scan = Invoke-WsScan -Path $root -Top 3

        ($scan.Directories | Where-Object { $_.Path -eq $root }).Severity | Should Be 'Info'
        $scan.TotalSize | Should BeGreaterThan (100MB)
    }

    It '配置校验的各类错误分支都会抛出' {
        $badOverrides = @(
            @{ scan = @{ parallel = 'yes' } }
            @{ scan = @{ throttleLimit = 0 } }
            @{ scan = @{ exclude = 'not-an-array' } }
            @{ duplicates = @{ minSize = -1 } }
            @{ report = @{ formats = @('xml') } }
            @{ workspace = @{ snapshotKeep = 0 } }
            @{ workspace = @{ residuePatterns = 'bad' } }
        )
        foreach ($override in $badOverrides) {
            $threw = $false
            try { $null = Import-WsConfig -Override $override } catch { $threw = $true }
            $threw | Should Be $true
        }
    }

    It '配置文件不存在时抛出错误' {
        $threw = $false
        try { $null = Import-WsConfig -Path (Join-Path $TestDrive 'missing-config.json') } catch { $threw = $true }
        $threw | Should Be $true
    }

    It 'Export-WsReport -WhatIf 不创建目录' {
        $root = Join-Path $TestDrive 'cover-whatif-src'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $scan = Invoke-WsScan -Path $root
        $outDir = Join-Path $TestDrive 'cover-whatif-out'

        $files = @(Export-WsReport -ScanResult $scan -OutputDirectory $outDir -WhatIf)

        $files.Count | Should Be 0
        Test-Path -LiteralPath $outDir | Should Be $false
    }

    It '体检在快照不足保留数时不报快照问题' {
        $root = Join-Path $TestDrive 'cover-audit-keep'
        New-Item -ItemType Directory -Path (Join-Path $root '.dsh-snapshots\20260101-000000-weekly') -Force | Out-Null

        $findings = @(Invoke-WsWorkspaceAudit -Path $root -Config (Import-WsConfig))

        @($findings | Where-Object { $_.Category -eq '快照保留' }).Count | Should Be 0
    }

    It 'Remove-WsEmptyDirectory 不会删除命中排除规则的目录' {
        $root = Join-Path $TestDrive 'cover-clean-exclude'
        New-Item -ItemType Directory -Path (Join-Path $root '.git\empty') -Force | Out-Null

        $removed = Remove-WsEmptyDirectory -Path $root

        @($removed).Count | Should Be 0
        Test-Path -LiteralPath (Join-Path $root '.git\empty') | Should Be $true
    }
}
Describe '交付脚本（v0.8）' {

    It 'CLI -DryRun 只预览、不删除空目录' {
        $projectRoot = Split-Path -Parent $here
        $demo = Join-Path $TestDrive 'dryrun-clean'
        $nested = Join-Path $demo 'a\b'
        New-Item -ItemType Directory -Path $nested -Force | Out-Null

        & (Join-Path $projectRoot 'wsdoctor.ps1') -Path $demo -CleanEmptyDirs -DryRun -Top 3 | Out-Null

        Test-Path -LiteralPath $nested | Should Be $true
    }

    It 'pack.ps1 -WhatIf 只打印计划、不生成 zip' {
        $projectRoot = Split-Path -Parent $here
        $outDir = Join-Path $TestDrive 'pack-out'

        & (Join-Path $projectRoot 'pack.ps1') -OutputDirectory $outDir -WhatIf | Out-Null

        Test-Path -LiteralPath $outDir | Should Be $false
    }

    It '计划任务脚本 -WhatIf 只打印计划、不触碰 CIM' {
        $projectRoot = Split-Path -Parent $here
        $installScript = Join-Path $projectRoot 'install\Register-WsDoctorTask.ps1'

        { & $installScript -Path $TestDrive -WhatIf | Out-Null } | Should Not Throw
    }
}
Describe 'v1.0 收尾（帮助 / 补全 / 版本）' {

    It 'CLI -Version 输出模块版本' {
        $projectRoot = Split-Path -Parent $here
        $output = & (Join-Path $projectRoot 'wsdoctor.ps1') -Version
        ($output -join ' ') | Should Match 'WsDoctor \d+\.\d+\.\d+'
    }

    It '模块版本与清单一致（1.x）' {
        $projectRoot = Split-Path -Parent $here
        $manifest = Import-PowerShellDataFile -LiteralPath (Join-Path $projectRoot 'WsDoctor.psd1')
        (Get-Module WsDoctor).Version.ToString() | Should Be ([string]$manifest.ModuleVersion)
        ([string]$manifest.ModuleVersion) | Should Match '^1\.'
    }

    It '关键参数带 ArgumentCompleter（Tab 补全可用）' {
        $projectRoot = Split-Path -Parent $here
        $command = Get-Command (Join-Path $projectRoot 'wsdoctor.ps1')
        foreach ($parameterName in @('Format', 'ParallelMode', 'Path', 'OutDir', 'ConfigPath')) {
            @($command.Parameters[$parameterName].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ArgumentCompleterAttribute] }).Count | Should BeGreaterThan 0
        }
    }
}
Describe '重复检测性能与估算（v1.2）' {

    It '两阶段哈希与全量哈希结果一致' {
        $root = Join-Path $TestDrive 'two-stage-equiv'
        New-Item -ItemType Directory -Path "$root\a","$root\b" -Force | Out-Null
        $bytes = [byte[]]::new(200000)
        [System.Random]::new(11).NextBytes($bytes)
        $different = [byte[]]::new(200000)
        [System.Random]::new(12).NextBytes($different)
        [System.IO.File]::WriteAllBytes((Join-Path $root 'a\big.bin'), $bytes)
        [System.IO.File]::WriteAllBytes((Join-Path $root 'b\big-copy.bin'), $bytes)
        [System.IO.File]::WriteAllBytes((Join-Path $root 'b\big-different.bin'), $different)

        $twoStage = @(Find-WsDuplicateFile -Path $root -MinSize 0 -ThrottleLimit 4 -SampleSize 65536)
        $fullOnly = @(Find-WsDuplicateFile -Path $root -MinSize 0 -ThrottleLimit 4 -SampleSize 0)

        $twoStage.Count | Should Be $fullOnly.Count
        if ($twoStage.Count -gt 0) {
            $twoStage[0].Hash | Should Be $fullOnly[0].Hash
            $twoStage[0].FileCount | Should Be $fullOnly[0].FileCount
        }
        ($twoStage.Files -join '|') | Should Not Match 'big-different'
    }

    It 'Measure-WsDuplicateWork 返回候选统计与预计时间' {
        $root = Join-Path $TestDrive 'measure-work'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $bytes = [byte[]]::new(5000)
        [System.IO.File]::WriteAllBytes((Join-Path $root 'one.bin'), $bytes)
        [System.IO.File]::WriteAllBytes((Join-Path $root 'two.bin'), $bytes)
        [System.IO.File]::WriteAllBytes((Join-Path $root 'unique.bin'), [byte[]]::new(3000))

        $estimate = Measure-WsDuplicateWork -Path $root -MinSize 0

        $estimate.CandidateFiles | Should Be 2
        $estimate.CandidateBytes | Should Be 10000
        $estimate.EstimatedSeconds | Should BeGreaterThan 0
        $estimate.EstimatedText | Should Match '\d'
    }

    It 'MinSize 过滤与自动策略下仍保持一致' {
        $root = Join-Path $TestDrive 'two-stage-minsize'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        [System.IO.File]::WriteAllBytes((Join-Path $root 'a.bin'), [byte[]]::new(50))
        [System.IO.File]::WriteAllBytes((Join-Path $root 'b.bin'), [byte[]]::new(50))
        @(Find-WsDuplicateFile -Path $root -MinSize 1024).Count | Should Be 0
        @(Find-WsDuplicateFile -Path $root -MinSize 10).Count | Should Be 1
    }
}