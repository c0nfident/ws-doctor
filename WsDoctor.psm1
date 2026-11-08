# WsDoctor.psm1 — 工作区体检工具（v0.3）
# 练习点：StrictMode / enum / class / 高级函数 / 参数校验 / ShouldProcess / 管道与对象 /
#         文件枚举性能优化 / 编译正则 / SHA256 去重 / 错误处理
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region 类型定义
enum Severity {
    Ok   = 0
    Info = 1
    Warn = 2
    Error = 3
}

class WsFileItem {
    [string]$Path
    [long]$Size
    [string]$SizeText

    WsFileItem([string]$path, [long]$size) {
        if ([string]::IsNullOrWhiteSpace($path)) { throw 'Path 不能为空' }
        $this.Path = $path
        $this.Size = $size
        $this.SizeText = if ($size -ge 1GB) { '{0:N2} GB' -f ($size / 1GB) }
                         elseif ($size -ge 1MB) { '{0:N1} MB' -f ($size / 1MB) }
                         else { '{0:N0} KB' -f ($size / 1KB) }
    }

    [string] GetSizeText() {
        if ($this.Size -ge 1GB) { return '{0:N2} GB' -f ($this.Size / 1GB) }
        if ($this.Size -ge 1MB) { return '{0:N1} MB' -f ($this.Size / 1MB) }
        return '{0:N0} KB' -f ($this.Size / 1KB)
    }

    [string] ToString() { return ('{0,10}  {1}' -f $this.GetSizeText(), $this.Path) }
}

class WsScanItem {
    [string]$Path
    [int]$Files
    [long]$Size
    [string]$SizeText
    [Severity]$Severity

    WsScanItem([string]$path, [int]$files, [long]$size) {
        $this.Path = $path
        $this.Files = $files
        $this.Size = $size
        $this.SizeText = if ($size -ge 1GB) { '{0:N2} GB' -f ($size / 1GB) }
                         elseif ($size -ge 1MB) { '{0:N1} MB' -f ($size / 1MB) }
                         else { '{0:N0} KB' -f ($size / 1KB) }
        $this.Severity = if ($size -ge 5GB) { [Severity]::Error }
                         elseif ($size -ge 1GB) { [Severity]::Warn }
                         elseif ($size -ge 100MB) { [Severity]::Info }
                         else { [Severity]::Ok }
    }

    [string] GetSizeText() {
        if ($this.Size -ge 1GB) { return '{0:N2} GB' -f ($this.Size / 1GB) }
        if ($this.Size -ge 1MB) { return '{0:N1} MB' -f ($this.Size / 1MB) }
        return '{0:N0} KB' -f ($this.Size / 1KB)
    }

    [string] ToString() { return ('{0}  {1,6}  {2}' -f $this.GetSizeText(), $this.Files, $this.Path) }
}

class WsScanResult {
    [string]$Root
    [int]$TotalFiles
    [long]$TotalSize
    [datetime]$StartedAt
    [double]$DurationMs
    [string]$TotalSizeText
    [int]$DirectoryCount
    [int]$ErrorCount
    [string[]]$Errors
    [System.Collections.Generic.List[WsScanItem]]$Directories
    [System.Collections.Generic.List[WsFileItem]]$TopFiles

    WsScanResult([string]$root) {
        $this.Root = $root
        $this.StartedAt = Get-Date
        $this.Directories = [System.Collections.Generic.List[WsScanItem]]::new()
        $this.TopFiles = [System.Collections.Generic.List[WsFileItem]]::new()
        $this.TotalSizeText = ''
        $this.DirectoryCount = 0
        $this.Errors = @()
    }

    [string] GetTotalSizeText() {
        if ($this.TotalSize -ge 1GB) { return '{0:N2} GB' -f ($this.TotalSize / 1GB) }
        if ($this.TotalSize -ge 1MB) { return '{0:N1} MB' -f ($this.TotalSize / 1MB) }
        return '{0:N0} KB' -f ($this.TotalSize / 1KB) }
}

class WsDuplicateGroup {
    [long]$Size
    [string]$Hash
    [string]$HashShort
    [string[]]$Files
    [int]$FileCount
    [long]$Wasted
    [string]$SizeText
    [string]$WastedText
    [string]$SampleFile

    WsDuplicateGroup([long]$size, [string]$hash, [string[]]$files) {
        if ($files.Count -lt 2) { throw '重复组至少需要 2 个文件' }
        $this.Size = $size
        $this.Hash = $hash
        $this.HashShort = $hash.Substring(0, 12)
        $this.Files = $files
        $this.FileCount = $files.Count
        $this.Wasted = $size * ($files.Count - 1)
        $this.SizeText = if ($size -ge 1MB) { '{0:N1} MB' -f ($size / 1MB) } else { '{0:N0} KB' -f ($size / 1KB) }
        $this.WastedText = if ($this.Wasted -ge 1MB) { '{0:N1} MB' -f ($this.Wasted / 1MB) } else { '{0:N0} KB' -f ($this.Wasted / 1KB) }
        $this.SampleFile = $files[0]
    }

    [string] GetSizeText() {
        if ($this.Size -ge 1MB) { return '{0:N1} MB' -f ($this.Size / 1MB) }
        return '{0:N0} KB' -f ($this.Size / 1KB)
    }

    [string] ToString() { return ('{0} x{1} ({2})' -f $this.GetSizeText(), $this.Files.Count, $this.Hash.Substring(0, 12)) }
}
class WsFinding {
    [Severity]$Severity
    [string]$Category
    [string]$Target
    [string]$Message
    [string]$Action

    WsFinding([Severity]$severity, [string]$category, [string]$target, [string]$message, [string]$action) {
        $this.Severity = $severity
        $this.Category = $category
        $this.Target = $target
        $this.Message = $message
        $this.Action = $action
    }

    [string] ToString() { return ('[{0}] {1}: {2}' -f $this.Severity, $this.Category, $this.Message) }
}
#endregion

#region 私有函数
# 默认排除目录（正则）：VCS、依赖、快照、模块缓存、回收站
$script:DefaultExclude = @(
    '[\\/]\.git([\\/]|$)',
    '[\\/]node_modules([\\/]|$)',
    '[\\/]\.dsh-snapshots([\\/]|$)',
    '[\\/]\.modules([\\/]|$)',
    '[\\/]\.venv([\\/]|$)',
    '[\\/]\$Recycle\.Bin([\\/]|$)'
)

# 把多个正则合并成一个编译后的 Regex：每个文件只匹配一次，而不是 len(patterns) 次
function Get-WsExcludeMatcher {
    param([string[]]$Patterns = $script:DefaultExclude)
    $combined = ($Patterns | Where-Object { $_ }) -join '|'
    return [regex]::new($combined, [System.Text.RegularExpressions.RegexOptions]::Compiled)
}

function Test-WsExcluded {
    param(
        [Parameter(Mandatory)][string]$FullName,
        [string[]]$Patterns = $script:DefaultExclude
    )
    $matcher = Get-WsExcludeMatcher -Patterns $Patterns
    return $matcher.IsMatch($FullName)
}

# 枚举选项：递归 + 跳过无权限（IgnoreInaccessible），包含隐藏/系统文件（等价 Get-ChildItem -Force）
function Get-WsEnumOptions {
    $options = [System.IO.EnumerationOptions]::new()
    $options.RecurseSubdirectories = $true
    $options.IgnoreInaccessible = $true
    $options.AttributesToSkip = [System.IO.FileAttributes]0
    return $options
}

# 剪枝枚举：递归时直接跳过被排除的目录（不再遍历 .dsh-snapshots/.venv 等）
function Get-WsPrunedFiles {
    param(
        [Parameter(Mandatory)][string]$RootPath,
        [string[]]$Patterns = $script:DefaultExclude
    )
    $matcher = Get-WsExcludeMatcher -Patterns $Patterns
    $options = [System.IO.EnumerationOptions]::new()
    $options.RecurseSubdirectories = $false
    $options.IgnoreInaccessible = $true
    $options.AttributesToSkip = [System.IO.FileAttributes]0

    $result = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
    $stack = [System.Collections.Generic.Stack[System.IO.DirectoryInfo]]::new()
    $stack.Push([System.IO.DirectoryInfo]::new($RootPath))
    while ($stack.Count -gt 0) {
        $directory = $stack.Pop()
        try {
            foreach ($file in $directory.EnumerateFiles('*', $options)) {
                if ($matcher.IsMatch($file.FullName)) { continue }
                $result.Add($file)
            }
            foreach ($child in $directory.EnumerateDirectories('*', $options)) {
                if ($matcher.IsMatch($child.FullName)) { continue }
                $stack.Push($child)
            }
        } catch {
            Write-Verbose ('跳过无法枚举的目录: ' + $directory.FullName)
        }
    }
    return $result.ToArray()
}

# .NET SHA256（比 Get-FileHash cmdlet 每文件开销低得多）
function Get-WsFileHash {
    param([Parameter(Mandatory)][string]$Path)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
        try {
            $hashBytes = $sha.ComputeHash($stream)
        } finally {
            $stream.Dispose()
        }
        return [System.Convert]::ToHexString($hashBytes)
    } finally {
        $sha.Dispose()
    }
}

# 前缀哈希：只读文件前 SampleBytes 字节，用于两阶段去重的第一层过滤
function Get-WsFilePrefixHash {
    param(
        [Parameter(Mandatory)][string]$Path,
        [ValidateRange(1, 67108864)][long]$SampleBytes = 65536
    )
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
        try {
            $length = [Math]::Min($SampleBytes, $stream.Length)
            $buffer = [byte[]]::new($length)
            $read = 0
            while ($read -lt $length) {
                $count = $stream.Read($buffer, $read, $length - $read)
                if ($count -le 0) { break }
                $read += $count
            }
            if ($read -lt $length) {
                $buffer = $buffer[0..([Math]::Max(0, $read - 1))]
            }
            return [System.Convert]::ToHexString($sha.ComputeHash($buffer))
        } finally {
            $stream.Dispose()
        }
    } finally {
        $sha.Dispose()
    }
}

# 对候选文件计算哈希（Mode=Prefix 取前 SampleBytes；Mode=Full 全量 SHA256），支持并行
function Invoke-WsHashCandidates {
    param(
        [AllowEmptyCollection()][object[]]$Candidates = @(),
        [ValidateSet('Prefix', 'Full')][string]$Mode = 'Full',
        [ValidateRange(1, 64)][int]$ThrottleLimit = 4,
        [switch]$NoParallel,
        [ValidateRange(1, 67108864)][long]$SampleBytes = 65536
    )
    $results = [System.Collections.Generic.List[object]]::new()
    if ($Candidates.Count -eq 0) { return $results.ToArray() }

    $useParallel = (-not $NoParallel) -and $ThrottleLimit -gt 1 -and $Candidates.Count -ge 16
    if (-not $useParallel) {
        foreach ($candidate in $Candidates) {
            try {
                $hash = if ($Mode -eq 'Prefix') {
                    Get-WsFilePrefixHash -Path ([string]$candidate.Path) -SampleBytes $SampleBytes
                } else {
                    Get-WsFileHash -Path ([string]$candidate.Path)
                }
                $results.Add([pscustomobject]@{
                        Path = [string]$candidate.Path; Size = [long]$candidate.Size; Hash = $hash; Error = ''
                    })
            } catch {
                $results.Add([pscustomobject]@{
                        Path = [string]$candidate.Path; Size = [long]$candidate.Size; Hash = ''; Error = $_.Exception.Message
                    })
            }
        }
        return $results.ToArray()
    }

    $chunkSize = [Math]::Ceiling($Candidates.Count / [double]$ThrottleLimit)
    $chunks = [System.Collections.Generic.List[object]]::new()
    for ($index = 0; $index -lt $Candidates.Count; $index += $chunkSize) {
        $take = [Math]::Min($chunkSize, $Candidates.Count - $index)
        $chunk = [object[]]::new($take)
        [Array]::Copy($Candidates, $index, $chunk, 0, $take)
        $chunks.Add($chunk)
    }
    $hashMode = $Mode
    $sample = $SampleBytes
    $parts = @($chunks | ForEach-Object -Parallel {
            $items = $_
            $modeCopy = $using:hashMode
            $sampleCopy = $using:sample
            $localResults = [System.Collections.Generic.List[object]]::new()
            foreach ($item in $items) {
                $filePath = [string]$item.Path
                $fileSize = [long]$item.Size
                try {
                    $sha = [System.Security.Cryptography.SHA256]::Create()
                    try {
                        $stream = [System.IO.File]::Open($filePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
                        try {
                            if ($modeCopy -eq 'Prefix') {
                                $length = [Math]::Min([long]$sampleCopy, $stream.Length)
                                $buffer = [byte[]]::new($length)
                                $read = 0
                                while ($read -lt $length) {
                                    $count = $stream.Read($buffer, $read, $length - $read)
                                    if ($count -le 0) { break }
                                    $read += $count
                                }
                                if ($read -lt $length) { $buffer = $buffer[0..([Math]::Max(0, $read - 1))] }
                                $hash = [System.Convert]::ToHexString($sha.ComputeHash($buffer))
                            } else {
                                $hash = [System.Convert]::ToHexString($sha.ComputeHash($stream))
                            }
                        } finally {
                            $stream.Dispose()
                        }
                    } finally {
                        $sha.Dispose()
                    }
                    $localResults.Add([pscustomobject]@{ Path = $filePath; Size = $fileSize; Hash = $hash; Error = '' })
                } catch {
                    $localResults.Add([pscustomobject]@{ Path = $filePath; Size = $fileSize; Hash = ''; Error = $_.Exception.Message })
                }
            }
            $localResults.ToArray()
        } -ThrottleLimit $ThrottleLimit)
    foreach ($part in $parts) {
        foreach ($result in @($part)) { $results.Add($result) }
    }
    return $results.ToArray()
}

# 重复检测的扫描计划：一次剪枝枚举 + 按大小分组，供检测与估算复用
function Get-WsDuplicateScanPlan {
    param(
        [Parameter(Mandatory)][string]$RootPath,
        [string[]]$Patterns = $script:DefaultExclude,
        [long]$MinSize = 1024
    )
    $files = Get-WsPrunedFiles -RootPath $RootPath -Patterns $Patterns
    $bySize = [System.Collections.Generic.Dictionary[long, System.Collections.Generic.List[System.IO.FileInfo]]]::new()
    $totalFiles = 0
    $totalBytes = 0L
    foreach ($file in $files) {
        $totalFiles += 1
        $totalBytes += $file.Length
        if ($file.Length -lt $MinSize) { continue }
        if (-not $bySize.ContainsKey($file.Length)) {
            $bySize[$file.Length] = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
        }
        $bySize[$file.Length].Add($file)
    }
    $candidates = [System.Collections.Generic.List[object]]::new()
    $candidateGroups = 0
    $candidateBytes = 0L
    foreach ($entry in $bySize.GetEnumerator()) {
        if ($entry.Value.Count -lt 2) { continue }
        $candidateGroups += 1
        $candidateBytes += [long]$entry.Key * $entry.Value.Count
        foreach ($file in $entry.Value) {
            $candidates.Add([pscustomobject]@{ Path = $file.FullName; Size = [long]$file.Length })
        }
    }
    return [pscustomobject]@{
        TotalFiles      = $totalFiles
        TotalBytes      = $totalBytes
        CandidateGroups = $candidateGroups
        CandidateFiles  = $candidates.Count
        CandidateBytes  = $candidateBytes
        Candidates      = $candidates.ToArray()
    }
}

function Format-WsDuration {
    param([double]$Seconds)
    if ($Seconds -lt 60) { return ('{0:N0} 秒' -f $Seconds) }
    $totalMinutes = [Math]::Floor($Seconds / 60)
    $restSeconds = [Math]::Round($Seconds % 60)
    if ($totalMinutes -ge 60) {
        $hours = [Math]::Floor($totalMinutes / 60)
        $minutes = $totalMinutes % 60
        return ('{0} 小时 {1} 分' -f $hours, $minutes)
    }
    return ('{0} 分 {1} 秒' -f $totalMinutes, $restSeconds)
}

#endregion

function New-WsAggregatePart {
    param(
        [AllowEmptyCollection()][object[]]$Records = @(),
        [int]$Top = 10
    )
    $counts = @{}
    $sizes = @{}
    $totalFiles = 0
    $totalSize = 0L
    $candidates = [System.Collections.Generic.List[object]]::new()
    foreach ($record in $Records) {
        $fileSize = [long]$record.Size
        $totalFiles += 1
        $totalSize += $fileSize
        $parent = [System.IO.Path]::GetDirectoryName([string]$record.Path)
        if ($counts.ContainsKey($parent)) {
            $counts[$parent] += 1
            $sizes[$parent] += $fileSize
        } else {
            $counts[$parent] = 1
            $sizes[$parent] = $fileSize
        }
        $candidates.Add($record)
    }
    $topList = @()
    if ($Top -gt 0 -and $candidates.Count -gt 0) {
        $topList = @($candidates |
            Sort-Object -Property @{ Expression = { $_.Size }; Descending = $true }, @{ Expression = { $_.Path }; Descending = $false } |
            Select-Object -First $Top)
    }
    return [pscustomobject]@{
        Files  = $totalFiles
        Size   = $totalSize
        Counts = $counts
        Sizes  = $sizes
        Top    = $topList
        Errors = @()
    }
}

function Merge-WsAggregateParts {
    param(
        [AllowEmptyCollection()][object[]]$Parts = @(),
        [int]$Top = 10,
        [int]$MaxDepth = 200
    )
    $allCounts = @{}
    $allSizes = @{}
    $totalFiles = 0
    $totalSize = 0L
    $topCandidates = [System.Collections.Generic.List[object]]::new()
    $errors = [System.Collections.Generic.List[string]]::new()

    foreach ($part in $Parts) {
        $totalFiles += [int]$part.Files
        $totalSize += [long]$part.Size
        foreach ($key in $part.Counts.Keys) {
            if ($allCounts.ContainsKey($key)) {
                $allCounts[$key] += [int]$part.Counts[$key]
                $allSizes[$key] += [long]$part.Sizes[$key]
            } else {
                $allCounts[$key] = [int]$part.Counts[$key]
                $allSizes[$key] = [long]$part.Sizes[$key]
            }
        }
        foreach ($candidate in @($part.Top)) { $topCandidates.Add($candidate) }
        foreach ($message in @($part.Errors)) { if ($errors.Count -lt $MaxDepth) { $errors.Add([string]$message) } }
    }

    $finalTop = @()
    if ($Top -gt 0 -and $topCandidates.Count -gt 0) {
        $finalTop = @($topCandidates |
            Sort-Object -Property @{ Expression = { $_.Size }; Descending = $true }, @{ Expression = { $_.Path }; Descending = $false } |
            Select-Object -First $Top)
    }
    return [pscustomobject]@{
        Files  = $totalFiles
        Size   = $totalSize
        Counts = $allCounts
        Sizes  = $allSizes
        Top    = $finalTop
        Errors = $errors.ToArray()
    }
}

function Invoke-WsSerialAggregate {
    param(
        [AllowEmptyCollection()][object[]]$Records = @(),
        [int]$Top = 10
    )
    return (New-WsAggregatePart -Records $Records -Top $Top)
}

function Invoke-WsParallelAggregate {
    # Chunk 模式：串行枚举好的清单 → 连续分块 → runspace 聚合 → 主线程合并
    param(
        [AllowEmptyCollection()][object[]]$Records = @(),
        [int]$Top = 10,
        [int]$ThrottleLimit = 4
    )
    if ($Records.Count -eq 0) {
        return (New-WsAggregatePart -Records @() -Top $Top)
    }

    $chunkSize = [Math]::Ceiling($Records.Count / [double][Math]::Max(1, $ThrottleLimit))
    $chunks = [System.Collections.Generic.List[object]]::new()
    for ($index = 0; $index -lt $Records.Count; $index += $chunkSize) {
        $take = [Math]::Min($chunkSize, $Records.Count - $index)
        $chunk = [object[]]::new($take)
        [Array]::Copy($Records, $index, $chunk, 0, $take)
        $chunks.Add($chunk)
    }

    $topN = $Top
    $parts = @($chunks | ForEach-Object -Parallel {
            $items = $_
            $limit = $using:topN
            $counts = @{}
            $sizes = @{}
            $totalFiles = 0
            $totalSize = 0L
            $candidates = [System.Collections.Generic.List[object]]::new()
            foreach ($record in $items) {
                $fileSize = [long]$record.Size
                $totalFiles += 1
                $totalSize += $fileSize
                $parent = [System.IO.Path]::GetDirectoryName([string]$record.Path)
                if ($counts.ContainsKey($parent)) {
                    $counts[$parent] += 1
                    $sizes[$parent] += $fileSize
                } else {
                    $counts[$parent] = 1
                    $sizes[$parent] = $fileSize
                }
                $candidates.Add($record)
            }
            $topList = @()
            if ($limit -gt 0 -and $candidates.Count -gt 0) {
                $topList = @($candidates |
                    Sort-Object -Property @{ Expression = { $_.Size }; Descending = $true }, @{ Expression = { $_.Path }; Descending = $false } |
                    Select-Object -First $limit)
            }
            [pscustomobject]@{
                Files = $totalFiles; Size = $totalSize; Counts = $counts; Sizes = $sizes; Top = $topList; Errors = @()
            }
        } -ThrottleLimit $ThrottleLimit)

    return (Merge-WsAggregateParts -Parts $parts -Top $Top)
}

function Get-WsDirectoryList {
    # BFS 枚举目录（带排除剪枝）：只用 .NET 枚举，避免几千次 Get-ChildItem cmdlet 调用开销
    param(
        [Parameter(Mandatory)][string]$RootPath,
        [string[]]$Patterns = $script:DefaultExclude
    )
    $matcher = Get-WsExcludeMatcher -Patterns $Patterns
    $options = [System.IO.EnumerationOptions]::new()
    $options.RecurseSubdirectories = $false
    $options.IgnoreInaccessible = $true
    $options.AttributesToSkip = [System.IO.FileAttributes]0

    $result = [System.Collections.Generic.List[string]]::new()
    $queue = [System.Collections.Generic.Queue[string]]::new()
    $queue.Enqueue($RootPath)
    while ($queue.Count -gt 0) {
        $current = $queue.Dequeue()
        try {
            foreach ($child in ([System.IO.DirectoryInfo]::new($current)).EnumerateDirectories('*', $options)) {
                if ($matcher.IsMatch($child.FullName)) { continue }
                $result.Add($child.FullName)
                $queue.Enqueue($child.FullName)
            }
        } catch {
            Write-Verbose ('跳过无法枚举的目录: ' + $current)
        }
    }
    return $result.ToArray()
}

function Invoke-WsDirBucketAggregate {
    # DirBucket 模式：目录分桶并行。
    # 1) .NET BFS 枚举目录（剪枝排除项，只走目录）
    # 2) 目录轮流分到 ThrottleLimit 个桶，每个桶在 runspace 内扫描"直属文件"（非递归）
    # 3) 每桶只在内存里保留 Top-N 候选（不再为每个文件建记录），主线程合并
    param(
        [Parameter(Mandatory)][string]$RootPath,
        [string[]]$Patterns = $script:DefaultExclude,
        [int]$Top = 10,
        [int]$ThrottleLimit = 4
    )

    $directories = [System.Collections.Generic.List[string]]::new()
    # 根目录直属文件也要算：把根目录自己加入目录列表（其"直属文件"= 根下非递归文件）
    $directories.Add($RootPath)
    foreach ($dir in (Get-WsDirectoryList -RootPath $RootPath -Patterns $Patterns)) { $directories.Add($dir) }

    $bucketCount = [Math]::Min([Math]::Max(1, $ThrottleLimit), $directories.Count)
    $buckets = @()
    for ($bucketIndex = 0; $bucketIndex -lt $bucketCount; $bucketIndex++) {
        $bucket = [System.Collections.Generic.List[string]]::new()
        for ($dirIndex = $bucketIndex; $dirIndex -lt $directories.Count; $dirIndex += $bucketCount) {
            $bucket.Add($directories[$dirIndex])
        }
        $buckets += , $bucket.ToArray()
    }

    $topN = $Top
    $parts = @($buckets | ForEach-Object -Parallel {
            $dirs = $_
            $limit = $using:topN
            $counts = @{}
            $sizes = @{}
            $totalFiles = 0
            $totalSize = 0L
            $topList = [System.Collections.Generic.List[object]]::new()
            $errors = [System.Collections.Generic.List[string]]::new()
            $comparer = [System.Comparison[object]] {
                param($left, $right)
                if ([long]$right.Size -ne [long]$left.Size) { return ([long]$right.Size).CompareTo([long]$left.Size) }
                return [string]::CompareOrdinal([string]$left.Path, [string]$right.Path)
            }

            $options = [System.IO.EnumerationOptions]::new()
            $options.RecurseSubdirectories = $false
            $options.IgnoreInaccessible = $true
            $options.AttributesToSkip = [System.IO.FileAttributes]0

            foreach ($directory in $dirs) {
                try {
                    foreach ($info in ([System.IO.DirectoryInfo]::new([string]$directory)).EnumerateFiles('*', $options)) {
                        $fileSize = [long]$info.Length
                        $fullName = $info.FullName
                        $totalFiles += 1
                        $totalSize += $fileSize
                        if ($counts.ContainsKey($directory)) {
                            $counts[$directory] += 1
                            $sizes[$directory] += $fileSize
                        } else {
                            $counts[$directory] = 1
                            $sizes[$directory] = $fileSize
                        }
                        if ($limit -gt 0) {
                            $candidate = [pscustomobject]@{ Path = $fullName; Size = $fileSize }
                            if ($topList.Count -lt $limit) {
                                $topList.Add($candidate)
                                $topList.Sort($comparer)
                            } elseif ($fileSize -gt [long]$topList[$topList.Count - 1].Size) {
                                $topList.RemoveAt($topList.Count - 1)
                                $topList.Add($candidate)
                                $topList.Sort($comparer)
                            }
                        }
                    }
                } catch {
                    $errors.Add($_.Exception.Message)
                }
            }

            [pscustomobject]@{
                Files = $totalFiles; Size = $totalSize; Counts = $counts; Sizes = $sizes; Top = @($topList); Errors = $errors.ToArray()
            }
        } -ThrottleLimit $ThrottleLimit)

    return (Merge-WsAggregateParts -Parts $parts -Top $Top)
}
function Invoke-WsSubtreeAggregate {
    # Subtree 模式：顶层子目录 = 工作单元，枚举+聚合都在各自 runspace 内完成（真正的并行 IO）
    param(
        [Parameter(Mandatory)][string]$RootPath,
        [string[]]$Patterns = $script:DefaultExclude,
        [int]$Top = 10,
        [int]$ThrottleLimit = 4
    )

    $matcher = Get-WsExcludeMatcher -Patterns $Patterns
    $parts = [System.Collections.Generic.List[object]]::new()

    # 根目录直属文件（不递归）：串行小块
    $rootRecords = [System.Collections.Generic.List[object]]::new()
    foreach ($file in @(Get-ChildItem -LiteralPath $RootPath -File -Force -ErrorAction SilentlyContinue)) {
        if ($matcher.IsMatch($file.FullName)) { continue }
        $rootRecords.Add([pscustomobject]@{ Path = $file.FullName; Size = [long]$file.Length })
    }
    $parts.Add((New-WsAggregatePart -Records $rootRecords.ToArray() -Top $Top))

    # 顶层子目录（排除命中规则的）：每个子树一个工作单元
    $units = @(Get-ChildItem -LiteralPath $RootPath -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object { -not $matcher.IsMatch($_.FullName) } |
        ForEach-Object { $_.FullName })

    if ($units.Count -gt 0) {
        $patternsForWorkers = $Patterns
        $topN = $Top
        $subtreeParts = @($units | ForEach-Object -Parallel {
                $subtree = [string]$_
                $patternsCopy = $using:patternsForWorkers
                $limit = $using:topN
                $combined = ($patternsCopy | Where-Object { $_ }) -join '|'
                $workerMatcher = [regex]::new($combined, [System.Text.RegularExpressions.RegexOptions]::Compiled)

                $options = [System.IO.EnumerationOptions]::new()
                $options.RecurseSubdirectories = $true
                $options.IgnoreInaccessible = $true
                $options.AttributesToSkip = [System.IO.FileAttributes]0

                $counts = @{}
                $sizes = @{}
                $totalFiles = 0
                $totalSize = 0L
                $candidates = [System.Collections.Generic.List[object]]::new()
                $errors = [System.Collections.Generic.List[string]]::new()
                try {
                    foreach ($info in ([System.IO.DirectoryInfo]::new($subtree)).EnumerateFiles('*', $options)) {
                        if ($workerMatcher.IsMatch($info.FullName)) { continue }
                        $record = [pscustomobject]@{ Path = $info.FullName; Size = [long]$info.Length }
                        $fileSize = [long]$record.Size
                        $totalFiles += 1
                        $totalSize += $fileSize
                        $parent = [System.IO.Path]::GetDirectoryName([string]$record.Path)
                        if ($counts.ContainsKey($parent)) {
                            $counts[$parent] += 1
                            $sizes[$parent] += $fileSize
                        } else {
                            $counts[$parent] = 1
                            $sizes[$parent] = $fileSize
                        }
                        $candidates.Add($record)
                    }
                } catch {
                    $errors.Add($_.Exception.Message)
                }
                $topList = @()
                if ($limit -gt 0 -and $candidates.Count -gt 0) {
                    $topList = @($candidates |
                        Sort-Object -Property @{ Expression = { $_.Size }; Descending = $true }, @{ Expression = { $_.Path }; Descending = $false } |
                        Select-Object -First $limit)
                }
                [pscustomobject]@{
                    Files = $totalFiles; Size = $totalSize; Counts = $counts; Sizes = $sizes; Top = $topList; Errors = $errors.ToArray()
                }
            } -ThrottleLimit $ThrottleLimit)
        foreach ($part in $subtreeParts) { $parts.Add($part) }
    }

    return (Merge-WsAggregateParts -Parts $parts.ToArray() -Top $Top)
}
function Format-WsSize {
    <#
    .SYNOPSIS
        把字节数格式化为便于阅读的 KB/MB/GB 文本（公开工具函数，CLI 与调用方共用）。
    .EXAMPLE
        Format-WsSize -Bytes 123456789
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][ValidateRange(0, [long]::MaxValue)][long]$Bytes)

    if ($Bytes -ge 1GB) { return '{0:N2} GB' -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return '{0:N1} MB' -f ($Bytes / 1MB) }
    return '{0:N0} KB' -f ($Bytes / 1KB)
}

#region 配置（v0.4：默认配置 + 用户覆盖 + 校验）
function Get-WsDefaultConfigPath {
    return (Join-Path $PSScriptRoot 'config\default.json')
}

function Read-WsJsonFile {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw ('配置文件不存在: ' + $Path) }
    $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($raw)) { throw ('配置文件为空: ' + $Path) }
    try {
        $null = Test-Json -Json $raw -ErrorAction Stop
    } catch {
        throw ('JSON 格式错误 (' + $Path + '): ' + $_.Exception.Message)
    }
    return (ConvertFrom-Json -InputObject $raw -AsHashtable)
}

function Merge-WsHashtable {
    param([hashtable]$Base, [hashtable]$Override)
    $result = @{}
    foreach ($key in $Base.Keys) { $result[$key] = $Base[$key] }
    foreach ($key in $Override.Keys) {
        $value = $Override[$key]
        if ($result.ContainsKey($key) -and $result[$key] -is [hashtable] -and $value -is [hashtable]) {
            $result[$key] = Merge-WsHashtable -Base $result[$key] -Override $value
        } else {
            $result[$key] = $value
        }
    }
    return $result
}

function Test-WsConfig {
    param([hashtable]$Config)
    if (-not $Config.ContainsKey('scan') -or $Config['scan'] -isnot [hashtable]) { throw '配置缺少 scan 节点' }
    $scan = $Config['scan']
    $top = $scan['top']
    if (($top -isnot [int] -and $top -isnot [long]) -or $top -lt 1 -or $top -gt 1000) {
        throw 'scan.top 必须是 1..1000 的整数'
    }
    $parallel = $scan['parallel']
    if ($null -ne $parallel -and $parallel -isnot [bool]) { throw 'scan.parallel 必须是 true/false' }
    $throttleLimit = $scan['throttleLimit']
    if (($throttleLimit -isnot [int] -and $throttleLimit -isnot [long]) -or $throttleLimit -lt 1 -or $throttleLimit -gt 64) {
        throw 'scan.throttleLimit 必须是 1..64 的整数'
    }
    $exclude = $scan['exclude']
    if ($null -eq $exclude -or $exclude -is [string]) { throw 'scan.exclude 必须是字符串数组' }
    foreach ($pattern in $exclude) {
        if ($pattern -isnot [string] -or [string]::IsNullOrWhiteSpace($pattern)) { throw 'scan.exclude 每一项必须是非空字符串' }
    }
    if (-not $Config.ContainsKey('duplicates') -or $Config['duplicates'] -isnot [hashtable]) { throw '配置缺少 duplicates 节点' }
    $minSize = $Config['duplicates']['minSize']
    if (($minSize -isnot [int] -and $minSize -isnot [long]) -or $minSize -lt 0) {
        throw 'duplicates.minSize 必须是 >=0 的整数（字节）'
    }
    if (-not $Config.ContainsKey('report') -or $Config['report'] -isnot [hashtable]) { throw '配置缺少 report 节点' }
    $formats = $Config['report']['formats']
    if ($null -eq $formats -or $formats -is [string]) { throw 'report.formats 必须是字符串数组' }
    $allowedFormats = @('json', 'csv', 'html')
    foreach ($format in $formats) {
        if ([string]$format -notin $allowedFormats) {
            throw ('report.formats 只允许 ' + ($allowedFormats -join '/') + '，收到: ' + $format)
        }
    }
    $outDir = $Config['report']['outDir']
    if ($outDir -isnot [string] -or [string]::IsNullOrWhiteSpace($outDir)) { throw 'report.outDir 必须是非空字符串' }

    if (-not $Config.ContainsKey('workspace') -or $Config['workspace'] -isnot [hashtable]) { throw '配置缺少 workspace 节点' }
    $workspace = $Config['workspace']
    $snapshotKeep = $workspace['snapshotKeep']
    if (($snapshotKeep -isnot [int] -and $snapshotKeep -isnot [long]) -or $snapshotKeep -lt 1 -or $snapshotKeep -gt 365) {
        throw 'workspace.snapshotKeep 必须是 1..365 的整数'
    }
    $residuePatterns = $workspace['residuePatterns']
    if ($null -eq $residuePatterns -or $residuePatterns -is [string]) { throw 'workspace.residuePatterns 必须是字符串数组' }
    foreach ($pattern in $residuePatterns) {
        if ($pattern -isnot [string] -or [string]::IsNullOrWhiteSpace($pattern)) { throw 'workspace.residuePatterns 每一项必须是非空字符串' }
    }
    return $Config
}
#endregion

#region 公开函数
function Invoke-WsScan {
    <#
    .SYNOPSIS
        扫描目录，统计每个子目录的文件数与体积，并给出最大的文件列表。
    .DESCRIPTION
        v0.5 提供三种实现，结果模型一致：
        - 默认：.NET 枚举器 + 串行聚合；
        - -LegacyEnumerator：Get-ChildItem -Recurse（性能对照）；
        - -Parallel：并行聚合，-ParallelMode 可选：
            Subtree（默认）：按顶层子目录切成工作单元，枚举+聚合都在 runspace 内完成，主线程合并；
            Chunk：先串行枚举全量文件清单，再分块并行聚合（用于对比"只并行聚合"的收益上限）。
        三种实现都应该得到完全相同的文件数/总大小/目录数/Top 文件（测试里有等价性断言）。
    .PARAMETER Path
        要扫描的目录（必须已存在）。
    .PARAMETER Exclude
        排除规则，正则数组，匹配完整路径。
    .PARAMETER Top
        列出最大的前 N 个文件，默认 10。
    .PARAMETER LegacyEnumerator
        使用旧的 Get-ChildItem -Recurse 实现（性能基准对照用）。
    .PARAMETER Parallel
        启用并行扫描（与 -LegacyEnumerator 互斥）。
    .PARAMETER ParallelMode
        并行模式：Subtree（默认，枚举也并行）/ Chunk（只并行聚合）。
    .PARAMETER ThrottleLimit
        并行度，默认 4（仅 -Parallel 生效）。
    .EXAMPLE
        Invoke-WsScan -Path D:\1Work -Top 5 | Format-List
    .EXAMPLE
        Invoke-WsScan -Path D:\1Work -Parallel -ThrottleLimit 8 | Select-Object TotalFiles, DurationMs
    .EXAMPLE
        Invoke-WsScan -Path D:\1Work -Parallel -ParallelMode Chunk | Select-Object DurationMs
    #>
    [CmdletBinding()]
    [OutputType([WsScanResult])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
        [string]$Path,

        [string[]]$Exclude = $script:DefaultExclude,

        [ValidateRange(1, 1000)]
        [int]$Top = 10,

        [switch]$LegacyEnumerator,

        [switch]$Parallel,

        [ValidateSet('DirBucket', 'Subtree', 'Chunk')]
        [string]$ParallelMode = 'DirBucket',

        [ValidateRange(1, 64)]
        [int]$ThrottleLimit = 4
    )

    if ($Parallel -and $LegacyEnumerator) {
        throw '参数冲突：-Parallel 与 -LegacyEnumerator 不能同时使用（并行路径固定用 .NET 枚举器）'
    }

    $rootPath = (Resolve-Path -LiteralPath $Path).ProviderPath
    $result = [WsScanResult]::new($rootPath)
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    if ($Parallel) {
        # 并行路径：枚举/聚合在 runspace 内完成（Subtree），或串行枚举后分块聚合（Chunk）
        if ($ParallelMode -eq 'DirBucket') {
            $merged = Invoke-WsDirBucketAggregate -RootPath $rootPath -Patterns $Exclude -Top $Top -ThrottleLimit $ThrottleLimit
        } elseif ($ParallelMode -eq 'Subtree') {
            $merged = Invoke-WsSubtreeAggregate -RootPath $rootPath -Patterns $Exclude -Top $Top -ThrottleLimit $ThrottleLimit
        } else {
            $records = [System.Collections.Generic.List[object]]::new()
            $matcher = Get-WsExcludeMatcher -Patterns $Exclude
            $parallelErrors = @()
            try {
                foreach ($file in (Get-WsPrunedFiles -RootPath $rootPath -Patterns $Exclude)) {
                    $records.Add([pscustomobject]@{ Path = $file.FullName; Size = [long]$file.Length })
                }
            } catch {
                $parallelErrors = @($_)
            }
            $merged = Invoke-WsParallelAggregate -Records $records.ToArray() -Top $Top -ThrottleLimit $ThrottleLimit
            foreach ($message in @($parallelErrors | ForEach-Object { $_.Exception.Message })) {
                $merged.Errors = @($merged.Errors) + $message
            }
        }
        $result.ErrorCount = @($merged.Errors).Count
        $result.Errors = @($merged.Errors | Select-Object -First 20)
    } else {
        # 串行路径：先枚举，再聚合
        $matcher = Get-WsExcludeMatcher -Patterns $Exclude
        $scanErrors = @()
        $records = [System.Collections.Generic.List[object]]::new()
        $fileSource = if ($LegacyEnumerator) {
            Get-ChildItem -LiteralPath $rootPath -File -Recurse -Force -ErrorAction SilentlyContinue -ErrorVariable +scanErrors
        } else {
            try {
                Get-WsPrunedFiles -RootPath $rootPath -Patterns $Exclude
            } catch {
                $scanErrors = @($_)
                @()
            }
        }
        foreach ($file in $fileSource) {
            if ($matcher.IsMatch($file.FullName)) { continue }
            $records.Add([pscustomobject]@{ Path = $file.FullName; Size = [long]$file.Length })
        }
        $merged = Invoke-WsSerialAggregate -Records $records.ToArray() -Top $Top
        $result.ErrorCount = @($scanErrors).Count
        $result.Errors = @($scanErrors | Select-Object -First 20 | ForEach-Object { $_.Exception.Message })
    }

    # 组装结果对象
    foreach ($dirEntry in $merged.Counts.GetEnumerator()) {
        $dir = $dirEntry.Key
        $result.Directories.Add([WsScanItem]::new($dir, [int]$dirEntry.Value, [long]$merged.Sizes[$dir]))
    }
    $result.Directories.Sort([System.Comparison[WsScanItem]] { param($a, $b) $b.Size.CompareTo($a.Size) })
    foreach ($topFile in @($merged.Top)) {
        $result.TopFiles.Add([WsFileItem]::new([string]$topFile.Path, [long]$topFile.Size))
    }

    $result.TotalFiles = [int]$merged.Files
    $result.TotalSize = [long]$merged.Size
    $result.TotalSizeText = Format-WsSize -Bytes $result.TotalSize
    $result.DirectoryCount = $result.Directories.Count
    $result.DurationMs = [math]::Round($stopwatch.Elapsed.TotalMilliseconds, 1)

    return $result
}
function Find-WsDuplicateFile {
    <#
    .SYNOPSIS
        找出目录中内容完全相同的重复文件。
    .DESCRIPTION
        v1.2 性能版：
        - 枚举剪枝：直接跳过排除目录（不再遍历 .dsh-snapshots/.venv 等）；
        - 两阶段哈希：先按大小分组 → 只读前 64KB 算前缀哈希 → 仅对"大小+前缀都相同"的文件做全量 SHA256；
        - 并行哈希：候选较多时按 ThrottleLimit 分块并行（.NET SHA256，比 Get-FileHash cmdlet 快）；
        - 返回 WsDuplicateGroup[]（按可回收空间降序）。
    .PARAMETER Path
        要扫描的目录。
    .PARAMETER Exclude
        排除规则，正则数组。
    .PARAMETER MinSize
        只检查不小于该字节数的文件，默认 1024。
    .PARAMETER SampleSize
        两阶段去重的取样字节数，默认 65536（0 = 关闭取样，直接全量哈希）。
    .PARAMETER ThrottleLimit
        并行哈希的并发度，默认 4（1 = 串行）。
    .PARAMETER NoParallel
        强制串行哈希（调试/基准对照用）。
    .EXAMPLE
        Find-WsDuplicateFile -Path D:\1Work\项目 | Select-Object -First 10
    #>
    [CmdletBinding()]
    [OutputType([WsDuplicateGroup[]])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
        [string]$Path,

        [string[]]$Exclude = $script:DefaultExclude,

        [ValidateRange(0, [long]::MaxValue)]
        [long]$MinSize = 1024,

        [ValidateRange(0, 67108864)]
        [long]$SampleSize = 65536,

        [ValidateRange(1, 64)]
        [int]$ThrottleLimit = 4,

        [switch]$NoParallel
    )

    $rootPath = (Resolve-Path -LiteralPath $Path).ProviderPath
    $plan = Get-WsDuplicateScanPlan -RootPath $rootPath -Patterns $Exclude -MinSize $MinSize
    Write-Verbose ('候选文件 {0} 个 / {1}' -f $plan.CandidateFiles, (Format-WsSize -Bytes $plan.CandidateBytes))
    if ($plan.CandidateFiles -eq 0) { return @() }

    $hashArgs = @{
        ThrottleLimit = $ThrottleLimit
        NoParallel    = $NoParallel
        SampleBytes   = if ($SampleSize -gt 0) { $SampleSize } else { 65536 }
    }

    # 自动策略：两阶段预计读盘量（取样 + 3% 全量）不低于全量一半时，直接用全量哈希（小目录更快）
    if ($SampleSize -gt 0) {
        $sampleBytesEstimate = 0L
        foreach ($candidate in $plan.Candidates) {
            $sampleBytesEstimate += [Math]::Min([long]$candidate.Size, $SampleSize)
        }
        $twoStageEstimate = $sampleBytesEstimate + [long]($plan.CandidateBytes * 0.03)
        if ($twoStageEstimate -ge [long]($plan.CandidateBytes * 0.5)) {
            Write-Verbose '两阶段无收益，自动切换为全量哈希'
            $SampleSize = 0
        }
    }

    # -SampleSize 0：关闭两阶段，直接对全部候选做全量哈希
    if ($SampleSize -le 0) {
        $hashArgs.SampleBytes = 65536
        $fullResults = @(Invoke-WsHashCandidates -Candidates $plan.Candidates -Mode 'Full' @hashArgs)
        $directGroups = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[string]]]::new()
        $directSizes = [System.Collections.Generic.Dictionary[string, long]]::new()
        $directHashes = [System.Collections.Generic.Dictionary[string, string]]::new()
        foreach ($result in $fullResults) {
            if (-not [string]::IsNullOrEmpty($result.Error)) { Write-Warning ('哈希失败，跳过 ' + $result.Path + ': ' + $result.Error); continue }
            $key = ('{0}|{1}' -f $result.Size, $result.Hash)
            if (-not $directGroups.ContainsKey($key)) {
                $directGroups[$key] = [System.Collections.Generic.List[string]]::new()
                $directSizes[$key] = [long]$result.Size
                $directHashes[$key] = [string]$result.Hash
            }
            $directGroups[$key].Add([string]$result.Path)
        }
        $directResult = [System.Collections.Generic.List[WsDuplicateGroup]]::new()
        foreach ($entry in $directGroups.GetEnumerator()) {
            if ($entry.Value.Count -lt 2) { continue }
            $directResult.Add([WsDuplicateGroup]::new($directSizes[$entry.Key], $directHashes[$entry.Key], $entry.Value.ToArray()))
        }
        $directResult.Sort([System.Comparison[WsDuplicateGroup]] { param($a, $b) $b.Wasted.CompareTo($a.Wasted) })
        return $directResult.ToArray()
    }

    # 第一层：前缀哈希（取样），把候选分成"大小+前缀"组
    $prefixResults = @(Invoke-WsHashCandidates -Candidates $plan.Candidates -Mode 'Prefix' @hashArgs)
    $prefixGroups = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[object]]]::new()
    foreach ($result in $prefixResults) {
        if (-not [string]::IsNullOrEmpty($result.Error)) { Write-Warning ('取样哈希失败，跳过 ' + $result.Path + ': ' + $result.Error); continue }
        $key = ('{0}|{1}' -f $result.Size, $result.Hash)
        if (-not $prefixGroups.ContainsKey($key)) {
            $prefixGroups[$key] = [System.Collections.Generic.List[object]]::new()
        }
        $prefixGroups[$key].Add([pscustomobject]@{ Path = $result.Path; Size = $result.Size; Hash = [string]$result.Hash })
    }

    # 第二层：前缀相同的文件里，小文件直接确认；大文件再做全量哈希
    $fullCandidates = [System.Collections.Generic.List[object]]::new()
    $confirmedGroups = [System.Collections.Generic.List[object]]::new()   # @{ Size; Files[] }
    foreach ($entry in $prefixGroups.GetEnumerator()) {
        if ($entry.Value.Count -lt 2) { continue }
        $size = [long]$entry.Value[0].Size
        if ($SampleSize -gt 0 -and $size -gt $SampleSize) {
            foreach ($candidate in $entry.Value) { $fullCandidates.Add($candidate) }
        } else {
            # 文件大小 <= 取样长度时，前缀哈希就是完整 SHA256
            [void]$confirmedGroups.Add([pscustomobject]@{
                    Size = $size; Hash = [string]$entry.Value[0].Hash
                    Files = @($entry.Value | ForEach-Object { [string]$_.Path })
                })
        }
    }

    if ($fullCandidates.Count -gt 0) {
        $fullResults = @(Invoke-WsHashCandidates -Candidates $fullCandidates.ToArray() -Mode 'Full' @hashArgs)
        $byKey = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[string]]]::new()
        $keySize = [System.Collections.Generic.Dictionary[string, long]]::new()
        $keyHash = [System.Collections.Generic.Dictionary[string, string]]::new()
        foreach ($result in $fullResults) {
            if (-not [string]::IsNullOrEmpty($result.Error)) { Write-Warning ('哈希失败，跳过 ' + $result.Path + ': ' + $result.Error); continue }
            $key = ('{0}|{1}' -f $result.Size, $result.Hash)
            if (-not $byKey.ContainsKey($key)) {
                $byKey[$key] = [System.Collections.Generic.List[string]]::new()
                $keySize[$key] = [long]$result.Size
                $keyHash[$key] = [string]$result.Hash
            }
            $byKey[$key].Add([string]$result.Path)
        }
        foreach ($entry in $byKey.GetEnumerator()) {
            if ($entry.Value.Count -lt 2) { continue }
            [void]$confirmedGroups.Add([pscustomobject]@{
                    Size = $keySize[$entry.Key]; Hash = $keyHash[$entry.Key]; Files = $entry.Value.ToArray()
                })
        }
    }

    $groups = [System.Collections.Generic.List[WsDuplicateGroup]]::new()
    foreach ($group in $confirmedGroups) {
        $groups.Add([WsDuplicateGroup]::new([long]$group.Size, [string]$group.Hash, [string[]]$group.Files))
    }
    $groups.Sort([System.Comparison[WsDuplicateGroup]] { param($a, $b) $b.Wasted.CompareTo($a.Wasted) })
    return $groups.ToArray()
}
function Measure-WsDuplicateWork {
    <#
    .SYNOPSIS
        估算重复文件检测的工作量和预计耗时（只做剪枝枚举 + 大小分组 + 取样字节统计，不读文件内容）。
    .DESCRIPTION
        用于 GUI 在真正开始前给用户「预计加载时间」，让用户决定继续或取消。
        耗时模型（v1.2 实测校准）：
        - 枚举：本次实测时间；
        - 第一层取样：候选文件 × min(大小, SampleSize) 字节；
        - 第二层全量：保守假设候选总量的 3%；
        - 有效吞吐：串行 60 MB/s，并行最多约 1.45x（磁盘受限）。
    .EXAMPLE
        Measure-WsDuplicateWork -Path D:\1Work | Format-List
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
        [string]$Path,

        [string[]]$Exclude = $script:DefaultExclude,

        [ValidateRange(0, [long]::MaxValue)]
        [long]$MinSize = 1024,

        [ValidateRange(0, 67108864)]
        [long]$SampleSize = 65536,

        [ValidateRange(1, 64)]
        [int]$ThrottleLimit = 4
    )

    $rootPath = (Resolve-Path -LiteralPath $Path).ProviderPath
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $plan = Get-WsDuplicateScanPlan -RootPath $rootPath -Patterns $Exclude -MinSize $MinSize
    $enumSeconds = [Math]::Round($stopwatch.Elapsed.TotalSeconds, 1)

    # 第一层取样字节数
    $sampleBytes = 0L
    $effectiveSample = if ($SampleSize -gt 0) { $SampleSize } else { 0 }
    foreach ($candidate in $plan.Candidates) {
        $size = [long]$candidate.Size
        $sampleBytes += if ($effectiveSample -gt 0) { [Math]::Min($size, $effectiveSample) } else { 0 }
    }
    # 第二层全量字节估计：关闭取样时全量；否则保守取候选总量的 3%
    $fullBytesEstimate = if ($SampleSize -le 0) { [long]$plan.CandidateBytes } else { [long]($plan.CandidateBytes * 0.03) }
    $bytesToRead = $sampleBytes + $fullBytesEstimate

    $assumedMbPerSecond = 60
    $speedup = 1 + ([Math]::Min($ThrottleLimit, 4) - 1) * 0.15
    $effectiveThroughput = $assumedMbPerSecond * $speedup
    $readSeconds = if ($bytesToRead -gt 0) { (($bytesToRead / 1MB) / $effectiveThroughput) } else { 0 }
    $estimatedSeconds = [Math]::Round($enumSeconds + $readSeconds + 1.5, 1)

    return [pscustomobject]@{
        Path               = $rootPath
        TotalFiles         = $plan.TotalFiles
        TotalBytes         = $plan.TotalBytes
        TotalSizeText      = Format-WsSize -Bytes $plan.TotalBytes
        CandidateGroups    = $plan.CandidateGroups
        CandidateFiles     = $plan.CandidateFiles
        CandidateBytes     = $plan.CandidateBytes
        CandidateSizeText  = Format-WsSize -Bytes $plan.CandidateBytes
        SampleSize         = $SampleSize
        SampleBytes        = $sampleBytes
        EstimatedFullBytes = $fullBytesEstimate
        EnumSeconds        = $enumSeconds
        ThrottleLimit      = $ThrottleLimit
        AssumedMbPerSecond = $assumedMbPerSecond
        ParallelSpeedup    = [Math]::Round($speedup, 2)
        EstimatedSeconds   = $estimatedSeconds
        EstimatedText      = Format-WsDuration -Seconds $estimatedSeconds
    }
}
function Measure-WsScanWork {
    <#
    .SYNOPSIS
        估算目录扫描的工作量和预计耗时（只做剪枝枚举，不聚合/不读文件内容）。
    .DESCRIPTION
        用于 GUI 在扫描前给用户「预计加载时间」。模型（v1.3 实测校准）：
        - 枚举实测时间；加上每文件聚合开销（串行 0.09ms/文件，并行 0.04ms/文件）与固定启动开销。
    .EXAMPLE
        Measure-WsScanWork -Path D:\1Work -Parallel | Format-List
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
        [string]$Path,

        [string[]]$Exclude = $script:DefaultExclude,

        [switch]$Parallel,

        [ValidateRange(1, 64)]
        [int]$ThrottleLimit = 4
    )

    $rootPath = (Resolve-Path -LiteralPath $Path).ProviderPath
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $files = Get-WsPrunedFiles -RootPath $rootPath -Patterns $Exclude
    $enumSeconds = [Math]::Round($stopwatch.Elapsed.TotalSeconds, 1)

    $totalBytes = 0L
    $directories = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($file in $files) {
        $totalBytes += $file.Length
        [void]$directories.Add([string]$file.DirectoryName)
    }
    $perFileSeconds = if ($Parallel) { 0.00004 } else { 0.00009 }
    $estimatedSeconds = [Math]::Round([Math]::Max(1.0, $enumSeconds + ($files.Count * $perFileSeconds) + 0.4), 1)

    return [pscustomobject]@{
        Path             = $rootPath
        TotalFiles       = $files.Count
        TotalBytes       = $totalBytes
        TotalSizeText    = Format-WsSize -Bytes $totalBytes
        DirectoryCount   = $directories.Count
        Parallel         = [bool]$Parallel
        ThrottleLimit    = $ThrottleLimit
        EnumSeconds      = $enumSeconds
        EstimatedSeconds = $estimatedSeconds
        EstimatedText    = Format-WsDuration -Seconds $estimatedSeconds
    }
}
function Remove-WsEmptyDirectory {
    <#
    .SYNOPSIS
        删除目录树中所有空目录（v0.2：ShouldProcess / -WhatIf 安全演练）。
    .DESCRIPTION
        从最深层向上处理，可级联清理"删完子目录才变空"的父目录。
        - 只删空目录，非空目录一律跳过；
        - 支持 -WhatIf 预览、-Confirm 逐项确认（ConfirmImpact = Medium）；
        - 默认排除规则同 Invoke-WsScan，避免误删 .git 等。
    .PARAMETER Path
        起始目录。
    .PARAMETER Exclude
        排除规则，正则数组，匹配完整路径。
    .EXAMPLE
        Remove-WsEmptyDirectory -Path D:\tmp -WhatIf
    .EXAMPLE
        Remove-WsEmptyDirectory -Path D:\tmp -Confirm
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
        [string]$Path,

        [string[]]$Exclude = $script:DefaultExclude
    )

    $rootPath = (Resolve-Path -LiteralPath $Path).ProviderPath
    $removed = [System.Collections.Generic.List[string]]::new()
    $allDirs = [System.Collections.Generic.List[string]]::new()
    $allDirs.Add($rootPath)
    # 剪枝枚举：直接跳过排除目录（同样用于快照/SDK 等都不遍历）
    foreach ($dir in (Get-WsDirectoryList -RootPath $rootPath -Patterns $Exclude)) {
        $allDirs.Add($dir)
    }

    # 深度降序：先处理叶子目录，父目录随后再判断是否变空
    $ordered = $allDirs | Sort-Object -Property { ($_ -split '[\\/]').Count } -Descending
    foreach ($dir in $ordered) {
        if ($dir -eq $rootPath) { continue }
        try {
            $children = @(Get-ChildItem -LiteralPath $dir -Force -ErrorAction Stop)
            if ($children.Count -gt 0) { continue }
            if ($PSCmdlet.ShouldProcess($dir, '删除空目录')) {
                Remove-Item -LiteralPath $dir -Force -ErrorAction Stop
                $removed.Add($dir)
                Write-Verbose ('已删除空目录: ' + $dir)
            } else {
                Write-Verbose ('WhatIf/已拒绝: ' + $dir)
            }
        } catch {
            Write-Warning ('跳过 ' + $dir + ': ' + $_.Exception.Message)
        }
    }

    return $removed.ToArray()
}
function Import-WsConfig {
    <#
    .SYNOPSIS
        读取并合并 WsDoctor 配置（默认配置 → 用户配置文件 → 内存覆盖）。
    .DESCRIPTION
        - 默认配置来自模块内 config/default.json；
        - 用户配置文件只需写差异（深层合并）；
        - 校验失败抛出带字段名的错误；
        - 返回 hashtable（由 ConvertFrom-Json -AsHashtable 得到）。
    .PARAMETER Path
        用户配置文件路径（JSON）。省略则只用默认配置。
    .PARAMETER Override
        代码层面的覆盖（优先级最高），例如把 CLI 参数并进去。
    .EXAMPLE
        $cfg = Import-WsConfig -Path .\my.json -Override @{ scan = @{ top = 5 } }
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [string]$Path,
        [hashtable]$Override
    )

    $defaults = Read-WsJsonFile -Path (Get-WsDefaultConfigPath)
    if ($PSBoundParameters.ContainsKey('Path') -and -not [string]::IsNullOrWhiteSpace($Path)) {
        $resolved = (Resolve-Path -LiteralPath $Path).ProviderPath
        $userConfig = Read-WsJsonFile -Path $resolved
        $config = Merge-WsHashtable -Base $defaults -Override $userConfig
    } else {
        $config = $defaults
    }
    if ($Override) { $config = Merge-WsHashtable -Base $config -Override $Override }
    return (Test-WsConfig -Config $config)
}

function Export-WsReport {
    <#
    .SYNOPSIS
        把扫描结果/重复文件结果导出为 JSON、CSV、HTML 报告（v0.4）。
    .DESCRIPTION
        - 支持组合格式：-Format Json,Csv,Html 或 -Format All；
        - 输出文件名带时间戳（wsdoctor-<stamp>.<ext> / -directories.csv 等）；
        - HTML 使用 ConvertTo-Html 生成，自动转义路径中的特殊字符；
        - 支持 -WhatIf 预览将写入的目录。
    .PARAMETER ScanResult
        Invoke-WsScan 的返回值（可省略，只导重复文件结果时）。
    .PARAMETER DuplicateGroups
        Find-WsDuplicateFile 的返回值（可省略）。
    .PARAMETER OutputDirectory
        报告输出目录（不存在会自动创建）。
    .PARAMETER Format
        输出格式，默认 Json。
    .EXAMPLE
        Export-WsReport -ScanResult $r -DuplicateGroups $d -OutputDirectory .\reports -Format All
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string[]])]
    param(
        [WsScanResult]$ScanResult,

        [WsDuplicateGroup[]]$DuplicateGroups = @(),

        [Parameter(Mandatory, Position = 0)]
        [string]$OutputDirectory,

        [ValidateSet('Json', 'Csv', 'Html', 'All')]
        [string[]]$Format = @('Json')
    )

    if (-not $ScanResult -and @($DuplicateGroups).Count -eq 0) {
        throw '至少提供 ScanResult 或 DuplicateGroups 之一'
    }

    $formats = if ($Format -contains 'All') { @('Json', 'Csv', 'Html') } else { @($Format | Select-Object -Unique) }
    $outPath = [System.IO.Path]::GetFullPath($OutputDirectory)
    if (-not $PSCmdlet.ShouldProcess($outPath, '生成体检报告')) { return @() }
    New-Item -ItemType Directory -Path $outPath -Force | Out-Null

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $written = [System.Collections.Generic.List[string]]::new()
    $dups = @($DuplicateGroups)
    $wasted = 0L
    foreach ($group in $dups) { $wasted += $group.Wasted }
    $moduleVersion = $MyInvocation.MyCommand.Module.Version

    $overview = [ordered]@{
        generatedAt         = (Get-Date).ToString('o')
        hostName            = $env:COMPUTERNAME
        moduleVersion       = [string]$moduleVersion
        root                = if ($ScanResult) { $ScanResult.Root } else { '' }
        totalFiles          = if ($ScanResult) { $ScanResult.TotalFiles } else { 0 }
        totalSize           = if ($ScanResult) { $ScanResult.TotalSize } else { 0 }
        totalSizeText       = if ($ScanResult) { $ScanResult.GetTotalSizeText() } else { '' }
        scanDurationMs      = if ($ScanResult) { $ScanResult.DurationMs } else { 0 }
        directoryCount      = if ($ScanResult) { $ScanResult.DirectoryCount } else { 0 }
        duplicateGroups     = $dups.Count
        duplicateWasted     = $wasted
        duplicateWastedText = Format-WsSize -Bytes $wasted
    }

    $directoryRows = @()
    $topFileRows = @()
    if ($ScanResult) {
        $directoryRows = @($ScanResult.Directories | Select-Object -First 200 | ForEach-Object {
            [pscustomobject][ordered]@{
                Path = $_.Path; Files = $_.Files; Size = $_.Size; SizeText = $_.SizeText; Severity = [string]$_.Severity
            }
        })
        $topFileRows = @($ScanResult.TopFiles | ForEach-Object {
            [pscustomobject][ordered]@{ Path = $_.Path; Size = $_.Size; SizeText = $_.SizeText }
        })
    }
    $duplicateRows = @($dups | ForEach-Object {
        [pscustomobject][ordered]@{
            Size = $_.Size; SizeText = $_.SizeText; FileCount = $_.FileCount; Wasted = $_.Wasted
            WastedText = $_.WastedText; Hash = $_.Hash; Files = ($_.Files -join '; ')
        }
    })

    if ($formats -contains 'Json') {
        $dto = [ordered]@{
            schemaVersion = 1
            overview      = $overview
            directories   = $directoryRows
            topFiles      = $topFileRows
            duplicates    = $duplicateRows
        }
        $jsonPath = Join-Path $outPath ('wsdoctor-' + $stamp + '.json')
        $dto | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
        $written.Add($jsonPath)
    }

    if ($formats -contains 'Csv') {
        foreach ($pair in @(
                @{ Name = 'directories'; Data = $directoryRows }
                @{ Name = 'top-files'; Data = $topFileRows }
                @{ Name = 'duplicates'; Data = $duplicateRows }
            )) {
            $csvPath = Join-Path $outPath ('wsdoctor-' + $stamp + '-' + $pair.Name + '.csv')
            if (@($pair.Data).Count -gt 0) {
                $pair.Data | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8
            } else {
                '' | Set-Content -LiteralPath $csvPath -Encoding UTF8
            }
            $written.Add($csvPath)
        }
    }

    if ($formats -contains 'Html') {
        $style = '<style>body{font-family:"Segoe UI",sans-serif;margin:24px;color:#1f2328}table{border-collapse:collapse;margin:8px 0 20px}th,td{border:1px solid #d0d7de;padding:4px 10px;font-size:13px}th{background:#f6f8fa}h1{font-size:20px}h2{font-size:16px;margin-top:24px}</style>'
        $htmlParts = [System.Collections.Generic.List[string]]::new()
        $htmlParts.Add('<h1>WsDoctor 体检报告</h1>')
        $htmlParts.Add('<h2>概览</h2>')
        $htmlParts.Add(($overview.GetEnumerator() | ForEach-Object {
            [pscustomobject][ordered]@{ 项目 = $_.Key; 值 = [string]$_.Value }
        } | ConvertTo-Html -Fragment | Out-String))
        if ($directoryRows.Count -gt 0) {
            $htmlParts.Add('<h2>目录 Top 200</h2>')
            $htmlParts.Add(($directoryRows | Select-Object Path, Files, SizeText, Severity |
                ConvertTo-Html -Fragment | Out-String))
        }
        if ($topFileRows.Count -gt 0) {
            $htmlParts.Add('<h2>最大的文件</h2>')
            $htmlParts.Add(($topFileRows | ConvertTo-Html -Fragment | Out-String))
        }
        if ($duplicateRows.Count -gt 0) {
            $htmlParts.Add('<h2>重复文件</h2>')
            $htmlParts.Add(($duplicateRows | Select-Object SizeText, FileCount, WastedText, Files |
                ConvertTo-Html -Fragment | Out-String))
        }
        $htmlPath = Join-Path $outPath ('wsdoctor-' + $stamp + '.html')
        ConvertTo-Html -Title 'WsDoctor 体检报告' -Head $style -Body ($htmlParts -join [Environment]::NewLine) `
            -PostContent ('<p>由 WsDoctor ' + $moduleVersion + ' 生成</p>') |
            Set-Content -LiteralPath $htmlPath -Encoding UTF8
        $written.Add($htmlPath)
    }

    Write-Verbose ('已生成 {0} 个报告文件到 {1}' -f $written.Count, $outPath)
    return $written.ToArray()
}

function Invoke-WsWorkspaceAudit {
    <#
    .SYNOPSIS
        工作区体检：快照保留数、疑似历史残留目录、空 temp 等规则检查（v0.6）。
    .DESCRIPTION
        规则来自配置文件的 workspace 节：
        - snapshotKeep：.dsh-snapshots 下快照保留数，超出时报告最旧的可删项；
        - residuePatterns：根目录条目名称的残留匹配正则（如 QQ 数据目录）；
        返回 WsFinding[]（Severity / Category / Target / Message / Action）。
    .PARAMETER Path
        工作区根目录。
    .PARAMETER Config
        配置 hashtable（默认用 Import-WsConfig 读取）。
    .EXAMPLE
        Invoke-WsWorkspaceAudit -Path D:\1Work | Format-Table
    #>
    [CmdletBinding()]
    [OutputType([WsFinding[]])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
        [string]$Path,

        [hashtable]$Config = (Import-WsConfig)
    )

    $rootPath = (Resolve-Path -LiteralPath $Path).ProviderPath
    $workspaceConfig = $Config['workspace']
    $findings = [System.Collections.Generic.List[WsFinding]]::new()

    # 规则 1：快照保留数
    $snapshotRoot = Join-Path $rootPath '.dsh-snapshots'
    if (Test-Path -LiteralPath $snapshotRoot -PathType Container) {
        $keep = [int]$workspaceConfig['snapshotKeep']
        $snapshots = @(Get-ChildItem -LiteralPath $snapshotRoot -Directory -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^20\d{6}-' } | Sort-Object Name)
        if ($snapshots.Count -gt $keep) {
            $excess = $snapshots.Count - $keep
            $candidates = $snapshots | Select-Object -First $excess
            foreach ($snapshot in $candidates) {
                $findings.Add([WsFinding]::new(
                        [Severity]::Warn, '快照保留', $snapshot.FullName,
                        ('快照 {0} 个 > 保留策略 {1}，最旧的可删除' -f $snapshots.Count, $keep),
                        '确认后删除（先核对 restore 依赖）'))
            }
        }
    } else {
        $findings.Add([WsFinding]::new([Severity]::Info, '快照保留', $snapshotRoot,
                '未发现 .dsh-snapshots 目录（当前无快照回滚点）', '如需回滚能力请建快照'))
    }

    # 规则 2：根目录疑似残留
    $residuePatterns = @($workspaceConfig['residuePatterns'])
    foreach ($entry in @(Get-ChildItem -LiteralPath $rootPath -Directory -Force -ErrorAction SilentlyContinue)) {
        foreach ($pattern in $residuePatterns) {
            if ($entry.Name -match $pattern) {
                $findings.Add([WsFinding]::new(
                        [Severity]::Info, '疑似残留', $entry.FullName,
                        ('目录名匹配残留规则 /{0}/' -f $pattern),
                        '确认无用后删除以释放空间'))
                break
            }
        }
    }

    # 规则 3：空 temp 目录
    $tempDir = Join-Path $rootPath 'temp'
    if (Test-Path -LiteralPath $tempDir -PathType Container) {
        $entryCount = @(Get-ChildItem -LiteralPath $tempDir -Force -ErrorAction SilentlyContinue).Count
        if ($entryCount -eq 0) {
            $findings.Add([WsFinding]::new([Severity]::Info, '空目录', $tempDir, 'temp 目录为空，可删除', '删除空目录'))
        }
    }

    return $findings.ToArray()
}

#endregion

Export-ModuleMember -Function Invoke-WsScan, Find-WsDuplicateFile, Measure-WsDuplicateWork, Measure-WsScanWork, Remove-WsEmptyDirectory, Format-WsSize, Import-WsConfig, Export-WsReport, Invoke-WsWorkspaceAudit
