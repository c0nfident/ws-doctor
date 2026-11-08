// Models.cs — 数据类型（record / enum / 异常 / 设置 / 通知模型）
#nullable enable

namespace WsDoctorGui.Models;

using WsDoctorGui;

/// <summary>GUI 可触发的 WsDoctor 动作。枚举值带 [WsAction] 元数据，由反射生成按钮。</summary>
public enum WsActionKind
{
    [WsAction("扫描", "统计目录体积、最大文件，生成体检报告", Keys.F5)]
    Scan,

    [WsAction("重复文件", "按内容哈希查找重复文件并计算可回收空间", Keys.F6)]
    Duplicates,

    [WsAction("清空目录", "删除空目录；勾选 DryRun 时只预览", Keys.F7)]
    Clean,

    [WsAction("规则体检", "检查快照保留数 / 残留目录 / 空 temp", Keys.F8)]
    Audit,

    [WsAction("导出报告", "生成 JSON / CSV / HTML 报告并打开目录", Keys.F9)]
    Report
}

public enum RunState
{
    Idle,
    Running,
    Cancelling,
    Completed,
    Failed
}

public enum LogLevel
{
    Debug,
    Info,
    Warn,
    Error
}

/// <summary>bridge.ps1 输出的 JSON 契约（字段名与 PowerShell 侧一致）。</summary>
public sealed record BridgeResult(
    string Action,
    bool Success,
    string Error,
    double DurationMs,
    string Version,
    JsonElement Payload);

public sealed record ScanSummary(
    string Root,
    int TotalFiles,
    long TotalSize,
    string TotalSizeText,
    int DirectoryCount,
    double DurationMs,
    int ErrorCount);

public sealed record DirectoryRow(string Path, int Files, long Size, string SizeText, string Severity)
{
    [JsonIgnore]
    public double SizeMb => Size / 1048576d;
}

public sealed record FileRow(string Path, long Size, string SizeText);

public sealed record DuplicateRow(
    long Size,
    string SizeText,
    int FileCount,
    long Wasted,
    string WastedText,
    string Hash,
    string SampleFile,
    IReadOnlyList<string> Files);

public sealed record FindingRow(string Severity, string Category, string Target, string Message, string Action);

public sealed record CleanRow(string Path);

public sealed record ReportRow(string File);

/// <summary>重复检测的预计工作量（由 Measure-WsDuplicateWork 返回）。</summary>
public sealed record DuplicateEstimate(
    int TotalFiles,
    long TotalBytes,
    string TotalSizeText,
    int CandidateGroups,
    int CandidateFiles,
    long CandidateBytes,
    string CandidateSizeText,
    long SampleSize,
    long SampleBytes,
    long EstimatedFullBytes,
    double EnumSeconds,
    int ThrottleLimit,
    double AssumedMbPerSecond,
    double ParallelSpeedup,
    double EstimatedSeconds,
    string EstimatedText);

/// <summary>扫描工作量估算（Measure-WsScanWork 返回）。</summary>
public sealed record ScanEstimate(
    int TotalFiles,
    long TotalBytes,
    string TotalSizeText,
    int DirectoryCount,
    bool Parallel,
    int ThrottleLimit,
    double EnumSeconds,
    double EstimatedSeconds,
    string EstimatedText);

/// <summary>把字节数格式化为 KB/MB/GB 文本（纯静态工具）。</summary>
public static class SizeText
{
    public static string Format(long bytes)
    {
        if (bytes >= 1024L * 1024 * 1024) { return $"{bytes / 1024d / 1024 / 1024:N2} GB"; }
        if (bytes >= 1024L * 1024) { return $"{bytes / 1024d / 1024:N1} MB"; }
        return $"{bytes / 1024d:N0} KB";
    }
}

/// <summary>一次动作的请求参数（record + 不可变 + with 表达式）。</summary>
public sealed record RunRequest(
    WsActionKind Kind,
    string Path,
    int Top,
    long MinDupSize,
    string ParallelMode,
    bool Parallel,
    bool DryRun,
    string? OutDir,
    string BridgeAction = "")
{
    public string ActionName => string.IsNullOrEmpty(BridgeAction) ? Kind.ToString() : BridgeAction;

    public static RunRequest CreateEstimate(string path, long minDupSize) =>
        new(WsActionKind.Duplicates, path, 10, minDupSize, "DirBucket", true, false, null, "Estimate");

    public static RunRequest CreateScanEstimate(string path, bool parallel, string parallelMode) =>
        new(WsActionKind.Scan, path, 10, 1024, parallelMode, parallel, true, null, "EstimateScan");

    /// <summary>转换为 bridge.ps1 的命令行参数（数组避免字符串拼接注入）。</summary>
    public IReadOnlyList<string> ToArguments(string resultFile)
    {
        var args = new List<string>
        {
            "-NoProfile", "-ExecutionPolicy", "Bypass",
            "-File", Paths.BridgeScript,
            "-Action", ActionName,
            "-Path", Path,
            "-ResultFile", resultFile
        };
        switch (ActionName)
        {
            case "EstimateScan":
                AddParallelArguments(args);
                break;
            case "Estimate":
                args.AddRange(["-MinDupSize", MinDupSize.ToString()]);
                break;
            case "Scan":
                args.AddRange(["-Top", Top.ToString()]);
                AddParallelArguments(args);
                break;
            case "Duplicates":
                args.AddRange(["-MinDupSize", MinDupSize.ToString()]);
                break;
            case "Clean":
                if (DryRun) { args.Add("-DryRun"); }
                break;
            case "Report":
                args.AddRange(["-Top", Top.ToString()]);
                args.AddRange(["-MinDupSize", MinDupSize.ToString()]);
                AddParallelArguments(args);
                if (!string.IsNullOrWhiteSpace(OutDir)) { args.AddRange(["-OutDir", OutDir]); }
                break;
        }
        return args;
    }

    private void AddParallelArguments(List<string> args)
    {
        if (!Parallel) { return; }
        args.Add("-Parallel");
        args.AddRange(["-ParallelMode", ParallelMode]);
    }
}

/// <summary>桥接进程失败的领域异常。</summary>
public sealed class BridgeException : Exception
{
    public int ExitCode { get; }

    public BridgeException(string message, int exitCode, Exception? inner = null)
        : base(message, inner)
    {
        ExitCode = exitCode;
    }
}

/// <summary>桥接调用结果（泛型 Result 模式，练习泛型 + 静态工厂）。</summary>
public sealed class Result<T>
{
    public bool IsSuccess { get; }
    public T? Value { get; }
    public string Error { get; }

    private Result(bool success, T? value, string error)
    {
        IsSuccess = success;
        Value = value;
        Error = error;
    }

    public static Result<T> Ok(T value) => new(true, value, string.Empty);
    public static Result<T> Fail(string error) => new(false, default, error);

    public T ValueOrThrow() => IsSuccess
        ? Value!
        : throw new BridgeException(Error, -1);

    public override string ToString() => IsSuccess ? "Ok" : "Fail: " + Error;
}

/// <summary>设置持久化（System.Text.Json + INotifyPropertyChanged）。</summary>
public sealed class AppSettings : INotifyPropertyChanged
{
    private string _lastPath = "D:\\1Work";
    private int _top = 10;
    private long _minDupSize = 1024;
    private string _parallelMode = "DirBucket";
    private bool _parallel;
    private bool _dryRun;

    public string LastPath
    {
        get => _lastPath;
        set => Set(ref _lastPath, value);
    }

    public int Top
    {
        get => _top;
        set => Set(ref _top, Math.Clamp(value, 1, 100));
    }

    public long MinDupSize
    {
        get => _minDupSize;
        set => Set(ref _minDupSize, Math.Max(0, value));
    }

    public string ParallelMode
    {
        get => _parallelMode;
        set => Set(ref _parallelMode, value);
    }

    public bool Parallel
    {
        get => _parallel;
        set => Set(ref _parallel, value);
    }

    public bool DryRun
    {
        get => _dryRun;
        set => Set(ref _dryRun, value);
    }

    public string? OutDir { get; set; }

    public event PropertyChangedEventHandler? PropertyChanged;

    private void Set<T>(ref T field, T value, [System.Runtime.CompilerServices.CallerMemberName] string? name = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value)) { return; }
        field = value;
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
    }

    public static AppSettings Load()
    {
        try
        {
            if (File.Exists(Paths.SettingsFile))
            {
                var json = File.ReadAllText(Paths.SettingsFile);
                var loaded = JsonSerializer.Deserialize<AppSettings>(json, JsonConfig.Options);
                if (loaded is not null) { return loaded; }
            }
        }
        catch (Exception ex) when (ex is IOException or JsonException or UnauthorizedAccessException)
        {
            Debug.WriteLine("读取设置失败，使用默认值: " + ex.Message);
        }
        return new AppSettings();
    }

    public void Save()
    {
        try
        {
            Directory.CreateDirectory(System.IO.Path.GetDirectoryName(Paths.SettingsFile)!);
            File.WriteAllText(Paths.SettingsFile, JsonSerializer.Serialize(this, JsonConfig.Options));
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            Debug.WriteLine("保存设置失败: " + ex.Message);
        }
    }
}

/// <summary>概览面板的数据模型（数据绑定 + INotifyPropertyChanged）。</summary>
public sealed class OverviewModel : INotifyPropertyChanged
{
    private string _root = "（尚未扫描）";
    private string _totalFiles = "—";
    private string _totalSize = "—";
    private string _directories = "—";
    private string _duration = "—";
    private string _status = "就绪";

    public string Root { get => _root; set => Set(ref _root, value); }
    public string TotalFiles { get => _totalFiles; set => Set(ref _totalFiles, value); }
    public string TotalSize { get => _totalSize; set => Set(ref _totalSize, value); }
    public string Directories { get => _directories; set => Set(ref _directories, value); }
    public string Duration { get => _duration; set => Set(ref _duration, value); }
    public string Status { get => _status; set => Set(ref _status, value); }

    public event PropertyChangedEventHandler? PropertyChanged;

    private void Set(ref string field, string value,
        [System.Runtime.CompilerServices.CallerMemberName] string? name = null)
    {
        if (field == value) { return; }
        field = value;
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
    }
}
