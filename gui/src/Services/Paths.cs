// Paths.cs / JsonConfig.cs — 路径解析与 JSON 选项（静态类 + 只读缓存）
#nullable enable

namespace WsDoctorGui.Services;

/// <summary>解析项目根 / bridge 脚本 / 设置文件路径。</summary>
public static class Paths
{
    private static readonly Lazy<string> s_projectRoot = new(ResolveProjectRoot);
    private static readonly Lazy<string> s_bridgeScript =
        new(() => Path.Combine(ProjectRoot, "gui", "ps", "bridge.ps1"));

    /// <summary>ws-doctor 项目根（gui 的上一级）。可以由环境变量 WSDOC_GUI_ROOT 覆盖。</summary>
    public static string ProjectRoot => s_projectRoot.Value;

    public static string BridgeScript => s_bridgeScript.Value;

    public static string SettingsFile => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "WsDoctorGui",
        "settings.json");

    public static string TempDirectory => Path.Combine(Path.GetTempPath(), "wsdoctor-gui");

    private static string ResolveProjectRoot()
    {
        var overridden = Environment.GetEnvironmentVariable("WSDOC_GUI_ROOT");
        if (!string.IsNullOrWhiteSpace(overridden) && Directory.Exists(overridden))
        {
            return Path.GetFullPath(overridden);
        }

        // 从程序集位置向上找：gui/bin/WsDoctorGui.dll → gui/bin → gui → ws-doctor
        var baseDir = AppContext.BaseDirectory;
        var candidate = Path.GetFullPath(Path.Combine(baseDir, "..", ".."));
        if (File.Exists(Path.Combine(candidate, "WsDoctor.psd1")))
        {
            return candidate;
        }

        // 从当前工作目录向上找
        var current = new DirectoryInfo(Environment.CurrentDirectory);
        while (current is not null)
        {
            if (File.Exists(Path.Combine(current.FullName, "WsDoctor.psd1")))
            {
                return current.FullName;
            }
            current = current.Parent;
        }
        return Environment.CurrentDirectory;
    }

    public static string NewResultFile(string action) =>
        Path.Combine(TempDirectory, $"result-{action}-{Guid.NewGuid():N}.json");
}

/// <summary>共享 JSON 序列化选项。</summary>
public static class JsonConfig
{
    public static readonly JsonSerializerOptions Options = new()
    {
        PropertyNameCaseInsensitive = true,
        WriteIndented = false,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull
    };

    public static readonly JsonSerializerOptions Pretty = new(Options)
    {
        WriteIndented = true
    };
}
