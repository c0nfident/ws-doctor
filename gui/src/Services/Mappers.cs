// Mappers.cs — JSON → 视图数据的映射（泛型 / 接口 / 继承 / 多态 / LINQ）
#nullable enable

namespace WsDoctorGui.Services;

/// <summary>JsonElement 读取扩展（扩展方法练习）。</summary>
public static class JsonExtensions
{
    public static string GetStringOrEmpty(this JsonElement element, string name) =>
        element.TryGetProperty(name, out var property) && property.ValueKind == JsonValueKind.String
            ? property.GetString() ?? string.Empty
            : string.Empty;

    public static int GetInt32OrDefault(this JsonElement element, string name) =>
        element.TryGetProperty(name, out var property) && property.ValueKind == JsonValueKind.Number
            ? property.GetInt32()
            : 0;

    public static long GetInt64OrDefault(this JsonElement element, string name) =>
        element.TryGetProperty(name, out var property) && property.ValueKind == JsonValueKind.Number
            ? property.GetInt64()
            : 0;

    public static double GetDoubleOrDefault(this JsonElement element, string name) =>
        element.TryGetProperty(name, out var property) && property.ValueKind == JsonValueKind.Number
            ? property.GetDouble()
            : 0d;

    public static IReadOnlyList<JsonElement> GetArrayOrEmpty(this JsonElement element, string name) =>
        element.TryGetProperty(name, out var property) && property.ValueKind == JsonValueKind.Array
            ? property.EnumerateArray().ToArray()
            : Array.Empty<JsonElement>();
}

/// <summary>统一视图数据容器：所有动作共用一个目标对象，各 Mapper 只填自己关心的部分。</summary>
public sealed class ViewData
{
    public ScanSummary? Summary { get; set; }
    public List<DirectoryRow> Directories { get; } = [];
    public List<FileRow> TopFiles { get; } = [];
    public List<DuplicateRow> Duplicates { get; } = [];
    public List<FindingRow> Findings { get; } = [];
    public List<CleanRow> RemovedDirectories { get; } = [];
    public List<ReportRow> Reports { get; } = [];
    public string Headline { get; set; } = string.Empty;
    public string Detail { get; set; } = string.Empty;
    public DuplicateEstimate? Estimate { get; set; }
    public ScanEstimate? ScanEstimate { get; set; }
    public bool DryRun { get; set; }
    public int WarnCount { get; set; }
    public int ErrorCount { get; set; }
    public int InfoCount { get; set; }
}

/// <summary>映射策略接口（多态 + 工厂）。</summary>
public interface IPayloadMapper
{
    void Map(JsonElement payload, ViewData target);
}

public static class PayloadMapperFactory
{
    public static IPayloadMapper Create(string kind) => kind switch
    {
        "scan" => new ScanMapper(),
        "duplicates" => new DuplicateMapper(),
        "audit" => new AuditMapper(),
        "clean" => new CleanMapper(),
        "report" => new ReportMapper(),
        "estimate" => new EstimateMapper(),
        "scan-estimate" => new ScanEstimateMapper(),
        _ => throw new NotSupportedException("未知 payload kind: " + kind)
    };
}

internal sealed class ScanMapper : IPayloadMapper
{
    public void Map(JsonElement payload, ViewData target)
    {
        var summary = new ScanSummary(
            payload.GetStringOrEmpty("root"),
            payload.GetInt32OrDefault("totalFiles"),
            payload.GetInt64OrDefault("totalSize"),
            payload.GetStringOrEmpty("totalSizeText"),
            payload.GetInt32OrDefault("directoryCount"),
            payload.GetDoubleOrDefault("durationMs"),
            payload.GetInt32OrDefault("errorCount"));
        target.Summary = summary;
        target.Headline = $"扫描完成：{summary.TotalFiles:N0} 个文件 / {summary.TotalSizeText}";
        target.Detail = $"目录 {summary.DirectoryCount:N0} 个 · 耗时 {summary.DurationMs:N0} ms · 访问错误 {summary.ErrorCount}";
        target.Directories.AddRange(payload.GetArrayOrEmpty("directories").Select(element => new DirectoryRow(
            element.GetStringOrEmpty("path"),
            element.GetInt32OrDefault("files"),
            element.GetInt64OrDefault("size"),
            element.GetStringOrEmpty("sizeText"),
            element.GetStringOrEmpty("severity"))));
        target.TopFiles.AddRange(payload.GetArrayOrEmpty("topFiles").Select(element => new FileRow(
            element.GetStringOrEmpty("path"),
            element.GetInt64OrDefault("size"),
            element.GetStringOrEmpty("sizeText"))));
    }
}

internal sealed class DuplicateMapper : IPayloadMapper
{
    public void Map(JsonElement payload, ViewData target)
    {
        var groups = payload.GetInt32OrDefault("groupCount");
        var wastedText = payload.GetStringOrEmpty("wastedText");
        target.Headline = $"重复文件：{groups:N0} 组 / 可回收 {wastedText}";
        target.Detail = groups == 0 ? "没有发现重复文件" : "双击行可打开文件所在目录";
        target.Duplicates.AddRange(payload.GetArrayOrEmpty("groups").Select(element => new DuplicateRow(
            element.GetInt64OrDefault("size"),
            element.GetStringOrEmpty("sizeText"),
            element.GetInt32OrDefault("fileCount"),
            element.GetInt64OrDefault("wasted"),
            element.GetStringOrEmpty("wastedText"),
            element.GetStringOrEmpty("hash"),
            element.GetStringOrEmpty("sampleFile"),
            element.GetArrayOrEmpty("files").Select(file => file.GetString() ?? string.Empty).ToArray())));
    }
}

internal sealed class AuditMapper : IPayloadMapper
{
    public void Map(JsonElement payload, ViewData target)
    {
        var total = payload.GetInt32OrDefault("count");
        target.WarnCount = payload.GetInt32OrDefault("warn");
        target.ErrorCount = payload.GetInt32OrDefault("error");
        target.InfoCount = payload.GetInt32OrDefault("info");
        target.Headline = $"规则体检：{total:N0} 条发现（Warn {target.WarnCount} / Info {target.InfoCount} / Error {target.ErrorCount}）";
        target.Detail = "规则来自 config/default.json 的 workspace 节";
        target.Findings.AddRange(payload.GetArrayOrEmpty("findings").Select(element => new FindingRow(
            element.GetStringOrEmpty("severity"),
            element.GetStringOrEmpty("category"),
            element.GetStringOrEmpty("target"),
            element.GetStringOrEmpty("message"),
            element.GetStringOrEmpty("action"))));
    }
}

internal sealed class CleanMapper : IPayloadMapper
{
    public void Map(JsonElement payload, ViewData target)
    {
        target.DryRun = payload.TryGetProperty("dryRun", out var dryRunProperty) &&
                        dryRunProperty.ValueKind == JsonValueKind.True;
        var count = payload.GetInt32OrDefault("count");
        target.Headline = target.DryRun
            ? $"清理预览（DryRun）：将删除 {count:N0} 个空目录"
            : $"清理完成：已删除 {count:N0} 个空目录";
        target.Detail = target.DryRun ? "勾选/取消 DryRun 可切换预览与真实删除" : string.Empty;
        target.RemovedDirectories.AddRange(payload.GetArrayOrEmpty("dirs")
            .Select(element => new CleanRow(element.GetString() ?? string.Empty)));
    }
}

internal sealed class ScanEstimateMapper : IPayloadMapper
{
    public void Map(JsonElement payload, ViewData target)
    {
        var estimate = new ScanEstimate(
            payload.GetInt32OrDefault("totalFiles"),
            payload.GetInt64OrDefault("totalBytes"),
            payload.GetStringOrEmpty("totalSizeText"),
            payload.GetInt32OrDefault("directoryCount"),
            payload.TryGetProperty("parallel", out var parallelProperty) && parallelProperty.ValueKind == JsonValueKind.True,
            payload.GetInt32OrDefault("throttleLimit"),
            payload.GetDoubleOrDefault("enumSeconds"),
            payload.GetDoubleOrDefault("estimatedSeconds"),
            payload.GetStringOrEmpty("estimatedText"));
        target.ScanEstimate = estimate;
        target.Headline = $"扫描预计约 {estimate.EstimatedText}";
        target.Detail = $"{estimate.TotalFiles:N0} 个文件 / {estimate.TotalSizeText} · {estimate.DirectoryCount:N0} 个目录 · 枚举 {estimate.EnumSeconds:N1}s";
    }
}

internal sealed class EstimateMapper : IPayloadMapper
{
    public void Map(JsonElement payload, ViewData target)
    {
        var estimate = new DuplicateEstimate(
            payload.GetInt32OrDefault("totalFiles"),
            payload.GetInt64OrDefault("totalBytes"),
            payload.GetStringOrEmpty("totalSizeText"),
            payload.GetInt32OrDefault("candidateGroups"),
            payload.GetInt32OrDefault("candidateFiles"),
            payload.GetInt64OrDefault("candidateBytes"),
            payload.GetStringOrEmpty("candidateSizeText"),
            payload.GetInt64OrDefault("sampleSize"),
            payload.GetInt64OrDefault("sampleBytes"),
            payload.GetInt64OrDefault("estimatedFullBytes"),
            payload.GetDoubleOrDefault("enumSeconds"),
            payload.GetInt32OrDefault("throttleLimit"),
            payload.GetDoubleOrDefault("assumedMbPerSecond"),
            payload.GetDoubleOrDefault("parallelSpeedup"),
            payload.GetDoubleOrDefault("estimatedSeconds"),
            payload.GetStringOrEmpty("estimatedText"));
        target.Estimate = estimate;
        target.Headline = $"重复检测预计约 {estimate.EstimatedText}";
        target.Detail = $"候选 {estimate.CandidateFiles:N0} 个 / {estimate.CandidateSizeText} · 取样 {SizeText.Format(estimate.SampleBytes)} · 预计全量校验 {SizeText.Format(estimate.EstimatedFullBytes)}";
    }
}

internal sealed class ReportMapper : IPayloadMapper
{
    public void Map(JsonElement payload, ViewData target)
    {
        var outDir = payload.GetStringOrEmpty("outDir");
        var groups = payload.GetInt32OrDefault("groupCount");
        target.Headline = $"报告已生成：{groups:N0} 个重复组";
        target.Detail = outDir;
        target.Reports.AddRange(payload.GetArrayOrEmpty("files")
            .Select(element => new ReportRow(element.GetString() ?? string.Empty)));
    }
}
