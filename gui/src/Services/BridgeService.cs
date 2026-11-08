// BridgeService.cs — 调用 PowerShell 桥接进程（Process / async / 取消 / 异常 / IDisposable）
#nullable enable

namespace WsDoctorGui.Services;

/// <summary>启动 pwsh 跑 bridge.ps1，等待 JSON 结果文件；支持取消、超时、重试。</summary>
public sealed class BridgeService : IDisposable
{
private readonly string _powerShellPath;
    private readonly string _bridgeScript;
    private readonly bool _powerShellAvailable;
    private readonly string _powerShellHint;
    private bool _disposed;

    public BridgeService(string? powerShellPath = null, string? bridgeScript = null)
    {
        if (!string.IsNullOrWhiteSpace(powerShellPath))
        {
            _powerShellPath = powerShellPath;
            _powerShellAvailable = File.Exists(powerShellPath);
            _powerShellHint = _powerShellAvailable ? "" : ("指定的 PowerShell 不存在: " + powerShellPath);
        }
        else
        {
            _powerShellAvailable = TryResolvePowerShell(out _powerShellPath, out _powerShellHint);
        }
        _bridgeScript = bridgeScript ?? Paths.BridgeScript;
    }

    public string PowerShellPath => _powerShellPath;

public static string ResolvePowerShellPath()
    {
        return TryResolvePowerShell(out var path, out _) ? path : "pwsh.exe";
    }

    /// <summary>按优先级查找 pwsh：WSDOC_PWSH 覆盖 → 当前进程 → PATH → 常见安装目录。</summary>
    public static bool TryResolvePowerShell(out string path, out string hint)
    {
        var overridePath = Environment.GetEnvironmentVariable("WSDOC_PWSH");
        if (!string.IsNullOrWhiteSpace(overridePath))
        {
            if (File.Exists(overridePath)) { path = overridePath; hint = "来自 WSDOC_PWSH"; return true; }
            path = overridePath;
            hint = "WSDOC_PWSH 指向的文件不存在: " + overridePath;
            return false;
        }

        var processPath = Environment.ProcessPath;
        if (!string.IsNullOrEmpty(processPath) &&
            Path.GetFileNameWithoutExtension(processPath).StartsWith("pwsh", StringComparison.OrdinalIgnoreCase))
        {
            path = processPath;
            hint = "当前进程";
            return true;
        }

        var candidates = new List<string>();
        var pathVariable = Environment.GetEnvironmentVariable("PATH") ?? string.Empty;
        foreach (var directory in pathVariable.Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries))
        {
            try { candidates.Add(Path.Combine(directory.Trim(), "pwsh.exe")); }
            catch (ArgumentException) { }
        }
        var programFiles = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
        candidates.Add(Path.Combine(programFiles, "PowerShell", "7", "pwsh.exe"));
        candidates.Add(Path.Combine(programFiles, "PowerShell", "7-preview", "pwsh.exe"));
        candidates.Add(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Microsoft", "WindowsApps", "pwsh.exe"));

        foreach (var candidate in candidates)
        {
            if (File.Exists(candidate)) { path = candidate; hint = ""; return true; }
        }
        path = "pwsh.exe";
        hint = "未找到 PowerShell 7（pwsh.exe）。请安装：https://aka.ms/powershell-release?setchannel=Stable";
        return false;
    }

    public async Task<BridgeResult> RunAsync(
        RunRequest request,
        IProgress<string>? progress,
        CancellationToken cancellationToken)
    {
ObjectDisposedException.ThrowIf(_disposed, this);
        ArgumentNullException.ThrowIfNull(request);
        cancellationToken.ThrowIfCancellationRequested();
        if (!_powerShellAvailable)
        {
            throw new BridgeException("未检测到 PowerShell 7（pwsh.exe）：" + _powerShellHint, 127);
        }

        Directory.CreateDirectory(Paths.TempDirectory);
        var resultFile = Paths.NewResultFile(request.ActionName);
        progress?.Report($"启动桥接进程（{request.ActionName}）…");

        var startInfo = new ProcessStartInfo
        {
            FileName = _powerShellPath,
            WorkingDirectory = Paths.ProjectRoot,
            UseShellExecute = false,
            CreateNoWindow = true
        };
        foreach (var argument in request.ToArguments(resultFile))
        {
            startInfo.ArgumentList.Add(argument);
        }

        using var process = new Process { StartInfo = startInfo };
        try
        {
            if (!process.Start())
            {
                throw new BridgeException("无法启动 PowerShell 桥接进程", -1);
            }
            progress?.Report($"桥接进程 pid={process.Id}，等待结果…");

            using var registration = cancellationToken.Register(() => TryKill(process));
            await process.WaitForExitAsync(cancellationToken).ConfigureAwait(false);

            if (!File.Exists(resultFile))
            {
                var logFile = resultFile + ".log";
                var logTail = string.Empty;
                try
                {
                    if (File.Exists(logFile))
                    {
                        logTail = string.Join(Environment.NewLine, File.ReadAllLines(logFile).TakeLast(12));
                    }
                }
                catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
                {
                    logTail = "（读取桥接日志失败: " + ex.Message + "）";
                }
                var message = $"桥接未生成结果文件（exit={process.ExitCode}）";
                if (!string.IsNullOrEmpty(logTail))
                {
                    message += Environment.NewLine + Environment.NewLine + "桥接日志：" + Environment.NewLine + logTail;
                }
                throw new BridgeException(message, process.ExitCode);
            }
            var json = await File.ReadAllTextAsync(resultFile, cancellationToken).ConfigureAwait(false);
            var result = JsonSerializer.Deserialize<BridgeResult>(json, JsonConfig.Options)
                         ?? throw new BridgeException("桥接结果反序列化失败", process.ExitCode);
            progress?.Report($"桥接完成（{result.DurationMs:N0} ms）");
            if (!result.Success)
            {
                throw new BridgeException(result.Error, process.ExitCode);
            }
            return result;
        }
        catch (OperationCanceledException)
        {
            progress?.Report("已取消（桥接进程已终止）");
            throw;
        }
        catch (BridgeException)
        {
            throw;
        }
        catch (Exception ex) when (ex is IOException or InvalidOperationException or JsonException)
        {
            throw new BridgeException("桥接调用异常: " + ex.Message, -1, ex);
        }
        finally
        {
            TryDelete(resultFile);
        }
    }

    /// <summary>带退避的重试封装（泛型 + async 练习）。</summary>
    public static async Task<BridgeResult> RunWithRetryAsync(
        BridgeService service,
        RunRequest request,
        int maxAttempts,
        IProgress<string>? progress,
        CancellationToken cancellationToken)
    {
        for (var attempt = 1; ; attempt++)
        {
            try
            {
                return await service.RunAsync(request, progress, cancellationToken).ConfigureAwait(false);
            }
            catch (BridgeException ex) when (attempt < maxAttempts && !cancellationToken.IsCancellationRequested)
            {
                progress?.Report($"第 {attempt} 次失败（{ex.Message}），{attempt * 500} ms 后重试…");
                await Task.Delay(attempt * 500, cancellationToken).ConfigureAwait(false);
            }
        }
    }

    private static void TryKill(Process process)
    {
        try
        {
            if (!process.HasExited)
            {
                process.Kill(entireProcessTree: true);
            }
        }
        catch (Exception ex) when (ex is InvalidOperationException or NotSupportedException or Win32Exception)
        {
            Debug.WriteLine("终止桥接进程失败: " + ex.Message);
        }
    }

    private static void TryDelete(string path)
    {
        try
        {
            if (File.Exists(path)) { File.Delete(path); }
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            Debug.WriteLine("删除临时文件失败: " + ex.Message);
        }
    }

    public void Dispose()
    {
        if (_disposed) { return; }
        _disposed = true;
        TryDelete(Paths.SettingsFile + ".tmp");
    }
}
