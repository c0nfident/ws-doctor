// Program.cs — 入口（GUI / 自检 / 离屏截图）
#nullable enable

using System.Runtime.Versioning;

namespace WsDoctorGui;

[SupportedOSPlatform("windows")]
public static class Program
{
    /// <summary>WinExe 入口：无参数 = 打开窗口；--selftest / --integration / --screenshot 供自动化。</summary>
    [STAThread]
    public static int Main(string[] args)
    {
        try
        {
            if (args.Any(argument => argument is "--selftest" or "-t"))
            {
                return ExecuteWithLog("selftest.log", RunSelfTest);
            }
            if (args.Any(argument => argument is "--integration" or "-i"))
            {
                return ExecuteWithLog("integration.log", RunIntegrationTest);
            }
            if (args.Any(argument => argument is "--uitest"))
            {
                return ExecuteWithLog("uitest.log", RunUiTest);
            }
if (args.Any(argument => argument is "--check-env"))
            {
                return RunCheckEnvironment();
            }
            var actionIndex = Array.IndexOf(args, "--action");
            if (actionIndex >= 0 && actionIndex + 1 < args.Length)
            {
                var actionName = args[actionIndex + 1];
                var pathIndex = Array.IndexOf(args, "--path");
                var targetPath = pathIndex >= 0 && pathIndex + 1 < args.Length ? args[pathIndex + 1] : Paths.ProjectRoot;
                return ExecuteWithLog("action.log", () => RunAction(actionName, targetPath));
            }
            var screenshotIndex = Array.IndexOf(args, "--screenshot");
            if (screenshotIndex >= 0)
            {
                var path = screenshotIndex + 1 < args.Length
                    ? args[screenshotIndex + 1]
                    : Path.Combine(Paths.TempDirectory, "screenshot.png");
                RenderScreenshot(path);
                return 0;
            }
            if (args.Any(argument => argument is "--help" or "-h" or "/?"))
            {
                Console.WriteLine("WsDoctorGui [--selftest|-t] [--integration|-i] [--screenshot <png>] [--help]");
                return 0;
            }
            RunGui();
            return 0;
        }
        catch (Exception ex)
        {
            WriteFatalLog(ex);
            return 1;
        }
    }

    private static int ExecuteWithLog(string fileName, Func<int> action)
    {
        Directory.CreateDirectory(Paths.TempDirectory);
        var logPath = Path.Combine(Paths.TempDirectory, fileName);
        var originalOut = Console.Out;
        try
        {
            using var writer = new StreamWriter(logPath, append: false, Encoding.UTF8) { AutoFlush = true };
            Console.SetOut(writer);
            var exitCode = action();
            writer.WriteLine();
            writer.WriteLine("=== exit code: " + exitCode + " ===");
            writer.WriteLine("=== log: " + logPath + " ===");
            return exitCode;
        }
        finally
        {
            Console.SetOut(originalOut);
        }
    }

    private static void WriteFatalLog(Exception exception)
    {
        try
        {
            Directory.CreateDirectory(Paths.TempDirectory);
            File.AppendAllText(Path.Combine(Paths.TempDirectory, "gui-error.log"),
                $"[{DateTime.Now:O}] {exception}{Environment.NewLine}");
        }
        catch (Exception)
        {
            // 启动阶段连日志都写不了时只能放弃
        }
    }

    /// <summary>打开交互窗口（需在 STA 线程调用，见 run.ps1 -STA）。</summary>
public static void RunGui()
    {
        Application.SetHighDpiMode(HighDpiMode.SystemAware);
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        InstallExceptionHandlers();

        if (!BridgeService.TryResolvePowerShell(out _, out var powerShellHint))
        {
            var choice = MessageBox.Show(
                "未检测到 PowerShell 7（pwsh.exe）。" + Environment.NewLine + Environment.NewLine +
                powerShellHint + Environment.NewLine + Environment.NewLine +
                "GUI 可以打开，但扫描/重复/清理等动作都会失败。" + Environment.NewLine +
                "是否仍要打开界面？",
                "WsDoctor 环境检查", MessageBoxButtons.YesNo, MessageBoxIcon.Warning, MessageBoxDefaultButton.Button2);
            if (choice != DialogResult.Yes) { return; }
        }

        using var form = new MainForm();
        Application.Run(form);
    }

    /// <summary>环境检查：OS / .NET / 模块 / PowerShell 7，供部署与排障使用。</summary>
        public static int RunCheckEnvironment()
    {
        var lines = new List<string>();
        void Add(string line) { lines.Add(line); Console.WriteLine(line); }
        Add("WsDoctor GUI 环境检查");
        Add("OS            : " + System.Runtime.InteropServices.RuntimeInformation.OSDescription + " / " + System.Runtime.InteropServices.RuntimeInformation.ProcessArchitecture);
        Add(".NET          : " + System.Runtime.InteropServices.RuntimeInformation.FrameworkDescription);
        Add("AppBase       : " + AppContext.BaseDirectory);
        Add("ProjectRoot   : " + Paths.ProjectRoot);
        var modulePath = Path.Combine(Paths.ProjectRoot, "WsDoctor.psd1");
        var moduleOk = File.Exists(modulePath);
        Add("Module        : " + (moduleOk ? "OK " + modulePath : "MISSING " + modulePath));
        var powerShellOk = BridgeService.TryResolvePowerShell(out var powerShellPath, out var hint);
        Add("PowerShell 7  : " + (powerShellOk ? "OK " + powerShellPath : "MISSING " + hint));
        try
        {
            Directory.CreateDirectory(Paths.TempDirectory);
            File.WriteAllLines(Path.Combine(Paths.TempDirectory, "check-env.log"), lines);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            // 环境检查结果写不进文件时忽略，退出码仍然可信
        }
        return powerShellOk && moduleOk ? 0 : 1;
    }

    private static bool s_errorDialogShown;

    /// <summary>全局异常兜底：写完整堆栈到日志 + 只弹一次错误框（避免重绘异常形成弹窗风暴）。</summary>
    private static void InstallExceptionHandlers()
    {
        Application.SetUnhandledExceptionMode(UnhandledExceptionMode.CatchException);
        Application.ThreadException += (_, args) => ReportError(args.Exception);
        AppDomain.CurrentDomain.UnhandledException += (_, args) => ReportError(args.ExceptionObject as Exception);
    }

    private static void ReportError(Exception? exception)
    {
        if (exception is null) { return; }
        WriteFatalLog(exception);
        if (s_errorDialogShown) { return; }
        s_errorDialogShown = true;
        try
        {
            var logPath = Path.Combine(Paths.TempDirectory, "gui-error.log");
            MessageBox.Show("程序遇到一个错误（详情已写入日志）。\n\n" + exception.GetType().Name + ": " + exception.Message + "\n\n" + logPath,
                "WsDoctor 错误", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
        catch (Exception)
        {
            // 弹窗失败时忽略，避免异常处理里再抛异常
        }
    }

    /// <summary>UI 回归测试：显示窗口、注入日志、切到「日志」页并强制重绘两轮。</summary>
    public static int RunUiTest()
    {
        var errors = new List<string>();
        Application.SetHighDpiMode(HighDpiMode.SystemAware);
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        Application.SetUnhandledExceptionMode(UnhandledExceptionMode.CatchException);
        Application.ThreadException += (_, args) => errors.Add(args.Exception.ToString());

        try
        {
            using var form = new MainForm();
            form.InjectDemoData();
            form.StartPosition = FormStartPosition.Manual;
            form.Location = new Point(-20000, -20000);
            form.ShowInTaskbar = false;
            form.Show();
            Application.DoEvents();

            for (var round = 0; round < 3; round++)
            {
                form.ShowLogTabForTest();
                for (var i = 0; i < 6; i++)
                {
                    Application.DoEvents();
                    Thread.Sleep(30);
                }
                using var bitmap = new Bitmap(form.Width, form.Height);
                form.DrawToBitmap(bitmap, new Rectangle(Point.Empty, form.Size));
                Application.DoEvents();
            }
            form.Hide();
        }
        catch (Exception ex)
        {
            errors.Add(ex.ToString());
        }

        Console.WriteLine(errors.Count == 0 ? "PASS: 日志页来回切换 3 轮，无绘制异常" : "FAIL: 捕获到 UI 异常");
        foreach (var error in errors) { Console.WriteLine(error); }
        return errors.Count;
    }

    /// <summary>自动化：走与 GUI 完全相同的 BridgeService 链路执行一个动作（诊断用）。</summary>
    public static int RunAction(string actionName, string path)
    {
        var kind = Enum.TryParse<WsActionKind>(actionName, ignoreCase: true, out var parsed) ? parsed : WsActionKind.Scan;
        var bridgeAction = string.Equals(actionName, "Estimate", StringComparison.OrdinalIgnoreCase) ? "Estimate" : string.Empty;
        var request = new RunRequest(kind, path, 10, 1024, "DirBucket", true, true, null, bridgeAction);
        using var bridge = new BridgeService();
        try
        {
            var result = bridge.RunAsync(request, new Progress<string>(text => Console.WriteLine("[progress] " + text)), CancellationToken.None).GetAwaiter().GetResult();
            var payloadKind = result.Payload.TryGetProperty("kind", out var property) ? property.GetString() : "?";
            Console.WriteLine($"PASS action={request.ActionName} kind={payloadKind} duration={result.DurationMs:N0}ms version={result.Version}");
            return 0;
        }
        catch (Exception ex)
        {
            Console.WriteLine("FAIL: " + ex.Message);
            return 1;
        }
    }

    /// <summary>运行 C# 自检（不依赖 Pester），返回失败数（0 = 全部通过）。</summary>
    public static int RunSelfTest() => SelfTest.Execute();

    /// <summary>集成测试：真实调用 bridge.ps1 → 映射 DTO → 取消路径。</summary>
    public static int RunIntegrationTest()
    {
        var failures = 0;
        void Check(string name, bool ok, string detail = "")
        {
            Console.WriteLine((ok ? "  PASS  " : "  FAIL  ") + name + (ok ? "" : "  (" + detail + ")"));
            if (!ok) { failures++; }
        }

        var bridge = new BridgeService();



        try
        {
            var request = new RunRequest(WsActionKind.Scan, Path.Combine(Paths.ProjectRoot, "docs"), 5, 1024, "DirBucket", true, true, null);

            var logMessages = new List<string>();
            IProgress<string> progress = new Progress<string>(message => logMessages.Add(message));
            var result = bridge.RunAsync(request, progress, CancellationToken.None).GetAwaiter().GetResult();
            Check("bridge 调用成功", result.Success, result.Error);
            var kind = result.Payload.TryGetProperty("kind", out var kindProperty) ? kindProperty.GetString() : null;
            Check("payload kind == scan", kind == "scan", kind ?? "null");
            var mapper = PayloadMapperFactory.Create(kind ?? "scan");
            var view = new ViewData();
            mapper.Map(result.Payload, view);
            Check("Summary 映射", view.Summary is { TotalFiles: > 0 }, "totalFiles=" + (view.Summary?.TotalFiles ?? 0));
            Check("目录行映射", view.Directories.Count > 0, "directories=" + view.Directories.Count);
            Check("进度回调", logMessages.Count > 0, "logs=" + logMessages.Count);

            using var cancellation = new CancellationTokenSource();
            cancellation.Cancel();
            try
            {
                bridge.RunAsync(request, null, cancellation.Token).GetAwaiter().GetResult();
                Check("取消抛 OperationCanceledException", false, "未抛出");
            }
            catch (OperationCanceledException)
            {
                Check("取消抛 OperationCanceledException", true);
            }

            var estimateRequest = RunRequest.CreateEstimate(Path.Combine(Paths.ProjectRoot, "docs"), 1024);
            var estimateResult = bridge.RunAsync(estimateRequest, null, CancellationToken.None).GetAwaiter().GetResult();
            Check("estimate 调用成功", estimateResult.Success, estimateResult.Error);
            var estimateView = new ViewData();
            PayloadMapperFactory.Create("estimate").Map(estimateResult.Payload, estimateView);
            Check("estimate 映射", estimateView.Estimate is { EstimatedSeconds: > 0 }, "estimate=" + (estimateView.Estimate?.EstimatedText ?? "null"));

            var scanEstimateRequest = RunRequest.CreateScanEstimate(Path.Combine(Paths.ProjectRoot, "docs"), true, "DirBucket");
            var scanEstimateResult = bridge.RunAsync(scanEstimateRequest, null, CancellationToken.None).GetAwaiter().GetResult();
            Check("scan-estimate 调用成功", scanEstimateResult.Success, scanEstimateResult.Error);
            var scanEstimateView = new ViewData();
            PayloadMapperFactory.Create("scan-estimate").Map(scanEstimateResult.Payload, scanEstimateView);
            Check("scan-estimate 映射", scanEstimateView.ScanEstimate is { EstimatedSeconds: > 0 }, "scan-estimate=" + (scanEstimateView.ScanEstimate?.EstimatedText ?? "null"));
        }
        catch (Exception ex)
        {
            Check("集成测试未预期异常", false, ex.GetType().Name + ": " + ex.Message);
        }
        finally
        {
            bridge.Dispose();
        }

        Console.WriteLine();
        Console.WriteLine("=== 集成测试：" + failures + " 项失败 ===");
        return failures;
    }

    /// <summary>离屏渲染主窗体并保存 PNG（用于无人工介入的界面验证）。</summary>
    public static void RenderScreenshot(string outputPath)
    {
        Application.SetHighDpiMode(HighDpiMode.SystemAware);
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);

        using var form = new MainForm();
        form.InjectDemoData();
        form.StartPosition = FormStartPosition.Manual;
        form.Location = new Point(-20000, -20000);
        form.ShowInTaskbar = false;
        form.Show();
        form.Refresh();
        Application.DoEvents();
        Thread.Sleep(120);
        Application.DoEvents();

        using var bitmap = new Bitmap(form.Width, form.Height);
        form.DrawToBitmap(bitmap, new Rectangle(Point.Empty, form.Size));

        var directory = Path.GetDirectoryName(outputPath);
        if (!string.IsNullOrEmpty(directory))
        {
            Directory.CreateDirectory(directory);
        }
        bitmap.Save(outputPath, System.Drawing.Imaging.ImageFormat.Png);
        form.Hide();
    }
}
