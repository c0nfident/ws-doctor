// MainForm.cs — 交互逻辑（async 事件 / 取消 / 数据绑定 / 日志 / 拖拽 / 快捷键）
#nullable enable

namespace WsDoctorGui;

public sealed partial class MainForm : Form
{
    private readonly AppSettings _settings;
    private readonly BridgeService _bridge;
    private readonly LogBuffer _log = new(600);
    private readonly OverviewModel _overview = new();

    private readonly BindingList<DirectoryRow> _directories = [];
    private readonly BindingList<FileRow> _topFiles = [];
    private readonly BindingList<DuplicateRow> _duplicates = [];
    private readonly BindingList<FindingRow> _findings = [];
    private readonly BindingList<CleanRow> _cleanRows = [];
    private readonly BindingList<ReportRow> _reportRows = [];

    private readonly System.Windows.Forms.Timer _elapsedTimer = new() { Interval = 200 };
    private readonly Stopwatch _stopwatch = new();

    private CancellationTokenSource? _cts;
    private bool _running;
    private string? _lastReportDirectory;

    public MainForm()
    {
        _settings = AppSettings.Load();
        _bridge = new BridgeService();
        InitializeComponent();
        WireEvents();
        ApplySettings();

        _elapsedLabel.Text = "—";
        _versionLabel.Text = "GUI · pwsh " + _bridge.PowerShellPath;
        AddLog(LogLevel.Info, "WsDoctor GUI 启动（C# WinForms 前端 + PowerShell 桥接）");
        AddLog(LogLevel.Info, "模块根目录: " + Paths.ProjectRoot);
        _overview.Root = _settings.LastPath;
        _overview.Status = "就绪";
        SelectTab(0);
    }

    // ---------------- 事件绑定 ----------------
    private void WireEvents()
    {
        _btnBrowse.Click += (_, _) => PickFolder(_txtPath, "选择工作区目录");
        _btnBrowseOut.Click += (_, _) => PickFolder(_txtOutDir, "选择报告输出目录");
        _btnOpenReports.Click += (_, _) => OpenReportFolder();
        _txtPath.TextChanged += (_, _) =>
        {
            _overview.Root = string.IsNullOrWhiteSpace(_txtPath.Text) ? "（未选择）" : _txtPath.Text;
        };

        foreach (var grid in new[] { _gridDirectories, _gridTopFiles, _gridDuplicates, _gridFindings, _gridClean, _gridReports })
        {
            grid.CellDoubleClick += OnGridCellDoubleClick;
        }

        _listLog.DrawItem += OnLogDrawItem;
        _log.EntryAdded += OnLogEntryAdded;
        _overview.PropertyChanged += (_, args) =>
        {
            if (args.PropertyName == nameof(OverviewModel.Status) && !IsDisposed)
            {
                _statusLabel.Text = _overview.Status;
            }
        };

        _elapsedTimer.Tick += (_, _) =>
        {
            _elapsedLabel.Text = $"耗时 {_stopwatch.Elapsed.TotalSeconds:0.0} s";
        };

        KeyDown += OnFormKeyDown;
        FormClosing += OnFormClosing;
        DragEnter += OnDragEnter;
        DragDrop += OnDragDrop;
    }

    private void ApplySettings()
    {
        _txtPath.Text = _settings.LastPath;
        _numTop.Value = Math.Clamp(_settings.Top, 1, 100);
        _numMinDup.Value = Math.Clamp(_settings.MinDupSize, 0, int.MaxValue);
        var modeIndex = _cmbMode.Items.IndexOf(_settings.ParallelMode);
        _cmbMode.SelectedIndex = modeIndex >= 0 ? modeIndex : 0;
        _chkParallel.Checked = _settings.Parallel;
        _chkDryRun.Checked = _settings.DryRun;
        _txtOutDir.Text = _settings.OutDir ?? string.Empty;
    }

    private void CaptureSettings()
    {
        _settings.LastPath = _txtPath.Text.Trim();
        _settings.Top = (int)_numTop.Value;
        _settings.MinDupSize = (long)_numMinDup.Value;
        _settings.ParallelMode = _cmbMode.SelectedItem?.ToString() ?? "DirBucket";
        _settings.Parallel = _chkParallel.Checked;
        _settings.DryRun = _chkDryRun.Checked;
        _settings.OutDir = string.IsNullOrWhiteSpace(_txtOutDir.Text) ? null : _txtOutDir.Text.Trim();
        _settings.Save();
    }

    // ---------------- 执行动作 ----------------
    private async void OnActionButtonClick(WsActionKind kind)
    {
        await RunActionAsync(kind);
    }

    private async Task RunActionAsync(WsActionKind kind)
    {
        if (_running) { return; }

        var path = _txtPath.Text.Trim();
        if (!Directory.Exists(path))
        {
            MessageBox.Show(this, "工作区目录不存在：" + path, "路径错误", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }

        var info = ActionCatalog.For(kind);
        if (kind == WsActionKind.Clean && !_chkDryRun.Checked)
        {
            var confirm = MessageBox.Show(this,
                "将真实删除空目录（不可撤销）。是否继续？",
                "确认清理", MessageBoxButtons.YesNo, MessageBoxIcon.Warning, MessageBoxDefaultButton.Button2);
            if (confirm != DialogResult.Yes) { return; }
        }

        SetRunning(true, info.Title);
        _log.Clear();
        AddLog(LogLevel.Info, $"=== {info.Title} === {path}");
        _cts = new CancellationTokenSource();
        _stopwatch.Restart();
        _elapsedTimer.Start();
        var progress = new Progress<string>(message => AddLog(LogLevel.Info, message));

        try
        {
            if (kind == WsActionKind.Scan)
            {
                var scanProceed = await ConfirmScanEstimateAsync(path);
                if (!scanProceed)
                {
                    AddLog(LogLevel.Warn, "已取消：用户选择不继续（扫描预估后）");
                    SetStatus("已取消（预估后选择不继续）", Theme.Warning, "已取消");
                    return;
                }
            }

            if (kind == WsActionKind.Duplicates)
            {
                var proceed = await ConfirmDuplicatesEstimateAsync(path);
                if (!proceed)
                {
                    AddLog(LogLevel.Warn, "已取消：用户选择不继续（预估耗时后）");
                    SetStatus("已取消（预估后选择不继续）", Theme.Warning, "已取消");
                    return;
                }
            }

            var request = new RunRequest(
                kind,
                path,
                (int)_numTop.Value,
                (long)_numMinDup.Value,
                _cmbMode.SelectedItem?.ToString() ?? "DirBucket",
                _chkParallel.Checked,
                _chkDryRun.Checked,
                string.IsNullOrWhiteSpace(_txtOutDir.Text) ? null : _txtOutDir.Text.Trim());

            AddLog(LogLevel.Debug, "参数: " + string.Join(' ', request.ToArguments("<result.json>")));
            var result = await _bridge.RunAsync(request, progress, _cts.Token);
            ApplyResult(result);
            AddLog(LogLevel.Info, $"完成：{result.Action}（{result.DurationMs:N0} ms，模块 {result.Version}）");
            SetStatus("完成：" + info.Title, Theme.Success, "完成");
        }
        catch (OperationCanceledException)
        {
            AddLog(LogLevel.Warn, "操作已取消");
            SetStatus("已取消", Theme.Warning, "已取消");
        }
        catch (BridgeException ex)
        {
            AddLog(LogLevel.Error, "桥接失败: " + ex.Message);
            SetStatus("失败", Theme.Danger, "失败");
            MessageBox.Show(this, ex.Message, "执行失败", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
        catch (Exception ex)
        {
            AddLog(LogLevel.Error, ex.ToString());
            SetStatus("失败", Theme.Danger, "失败");
            MessageBox.Show(this, ex.Message, "未预期错误", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
        finally
        {
            _elapsedTimer.Stop();
            _stopwatch.Stop();
            _cts?.Dispose();
            _cts = null;
            SetRunning(false, info.Title);
            CaptureSettings();
        }
    }

    private void CancelCurrentRun()
    {
        if (_cts is null || _cts.IsCancellationRequested) { return; }
        AddLog(LogLevel.Warn, "正在取消…");
        _overview.Status = "正在取消…";
        _cts.Cancel();
    }

    private void SetRunning(bool running, string actionName)
    {
        _running = running;
        _header.StatusText = running ? "运行中" : "就绪";
        _statusLabel.Text = running ? actionName + "运行中…" : "就绪";
        _progressBar.Visible = running;
        _btnCancel.Enabled = running;
        foreach (Control control in _flowActions.Controls)
        {
            if (control != _btnCancel && control is Button button)
            {
                button.Enabled = !running;
            }
        }
        _elapsedLabel.Text = running ? "耗时 0.0 s" : _stopwatch.Elapsed.TotalSeconds > 0
            ? $"耗时 {_stopwatch.Elapsed.TotalSeconds:0.0} s"
            : "—";
    }

    private void ApplyResult(BridgeResult result)
    {
        var payloadKind = result.Payload.TryGetProperty("kind", out var kindProperty)
            ? kindProperty.GetString() ?? string.Empty
            : string.Empty;
        var mapper = PayloadMapperFactory.Create(payloadKind);
        var view = new ViewData();
        mapper.Map(result.Payload, view);

        _headline.Headline = view.Headline;
        _headline.Detail = view.Detail;

        if (view.Summary is { } summary)
        {
            _overview.Root = summary.Root;
            _overview.TotalFiles = summary.TotalFiles.ToString("N0");
            _overview.TotalSize = summary.TotalSizeText;
            _overview.Directories = summary.DirectoryCount.ToString("N0");
            _overview.Duration = summary.DurationMs.ToString("N0") + " ms";
        }
        else if (payloadKind == "clean" || payloadKind == "duplicates" || payloadKind == "audit")
        {
            _overview.Duration = result.DurationMs.ToString("N0") + " ms";
        }

        // 只更新本次动作对应的表格，避免把之前扫描得到的「目录 / 大文件」数据清空
        switch (payloadKind)
        {
            case "scan":
                ReplaceRows(_directories, view.Directories);
                ReplaceRows(_topFiles, view.TopFiles);
                break;
            case "duplicates":
                ReplaceRows(_duplicates, view.Duplicates);
                break;
            case "audit":
                ReplaceRows(_findings, view.Findings);
                break;
            case "clean":
                ReplaceRows(_cleanRows, view.RemovedDirectories);
                break;
            case "report":
                ReplaceRows(_reportRows, view.Reports);
                break;
            case "estimate":
                // 估算不产生表格数据，保持现有结果
                break;
        }

        if (payloadKind == "report")
        {
            _lastReportDirectory = view.Detail;
        }
        _btnOpenReports.Enabled = view.Reports.Count > 0 || !string.IsNullOrEmpty(_lastReportDirectory);

        _overview.Status = view.Headline;
        SelectTabFor(payloadKind);
    }

    private static void ReplaceRows<T>(BindingList<T> list, IEnumerable<T> rows)
    {
        list.RaiseListChangedEvents = false;
        try
        {
            list.Clear();
            foreach (var row in rows) { list.Add(row); }
        }
        finally
        {
            list.RaiseListChangedEvents = true;
            list.ResetBindings();
        }
    }

    private void SelectTabFor(string kind)
    {
        var index = kind switch
        {
            "scan" => 1,
            "duplicates" => 3,
            "audit" => 4,
            "clean" => 5,
            "report" => 6,
            _ => 0
        };
        SelectTab(index);
    }

    private void SelectTab(int index)
    {
        if (index >= 0 && index < _tabControl.TabPages.Count)
        {
            _tabControl.SelectedIndex = index;
        }
    }

    private void SetStatus(string text, Color color, string? chipText = null)
    {
        _overview.Status = text;
        _header.StatusColor = color;
        _header.StatusText = chipText ?? text;
        _statusLabel.Text = text;
    }

    /// <summary>扫描前先估算耗时，弹窗让用户决定继续/取消。</summary>
    private async Task<bool> ConfirmScanEstimateAsync(string path)
    {
        AddLog(LogLevel.Info, "先估算扫描耗时（剪枝枚举统计）…");
        var estimateRequest = RunRequest.CreateScanEstimate(path, _chkParallel.Checked, _cmbMode.SelectedItem?.ToString() ?? "DirBucket");
        var result = await _bridge.RunAsync(estimateRequest, new Progress<string>(message => AddLog(LogLevel.Info, message)), _cts!.Token);
        var mapper = PayloadMapperFactory.Create("scan-estimate");
        var view = new ViewData();
        mapper.Map(result.Payload, view);
        var estimate = view.ScanEstimate ?? throw new BridgeException("扫描估算结果为空", 0);

        _headline.Headline = view.Headline;
        _headline.Detail = view.Detail;
        AddLog(LogLevel.Info, $"预计 {estimate.EstimatedText}：{estimate.TotalFiles:N0} 个文件 / {estimate.TotalSizeText}");

        var messageText =
            $"扫描预计需要约 {estimate.EstimatedText}。" + Environment.NewLine + Environment.NewLine +
            $"目录：{path}" + Environment.NewLine +
            $"文件：{estimate.TotalFiles:N0} 个 / {estimate.TotalSizeText}" + Environment.NewLine +
            $"子目录：{estimate.DirectoryCount:N0} 个" + Environment.NewLine +
            $"模式：{(estimate.Parallel ? "并行 " + _cmbMode.SelectedItem : "串行")} · 枚举 {estimate.EnumSeconds:N1}s" + Environment.NewLine + Environment.NewLine +
            "是否继续扫描？选「否」即取消。";

        var choice = MessageBox.Show(this, messageText, "预计扫描时间",
            MessageBoxButtons.YesNo, MessageBoxIcon.Question, MessageBoxDefaultButton.Button2);
        return choice == DialogResult.Yes;
    }

    /// <summary>重复检测前先估算工作量，弹窗让用户决定继续/取消。</summary>
    private async Task<bool> ConfirmDuplicatesEstimateAsync(string path)
    {
        AddLog(LogLevel.Info, "先估算重复检测工作量（枚举 + 取样统计）…");
        var estimateRequest = RunRequest.CreateEstimate(path, (long)_numMinDup.Value);
        var result = await _bridge.RunAsync(estimateRequest, new Progress<string>(message => AddLog(LogLevel.Info, message)), _cts!.Token);
        var mapper = PayloadMapperFactory.Create("estimate");
        var view = new ViewData();
        mapper.Map(result.Payload, view);
        var estimate = view.Estimate ?? throw new BridgeException("估算结果为空", 0);

        _headline.Headline = view.Headline;
        _headline.Detail = view.Detail;
        AddLog(LogLevel.Info, $"预计 {estimate.EstimatedText}：候选 {estimate.CandidateFiles:N0} 个 / {estimate.CandidateSizeText}，枚举 {estimate.EnumSeconds:N0}s");

        var messageText =
            $"重复文件检测预计需要约 {estimate.EstimatedText}。" + Environment.NewLine + Environment.NewLine +
            $"目录：{path}" + Environment.NewLine +
            $"文件总量：{estimate.TotalFiles:N0} 个 / {estimate.TotalSizeText}" + Environment.NewLine +
            $"同大小候选：{estimate.CandidateFiles:N0} 个 / {estimate.CandidateSizeText}" + Environment.NewLine +
            $"两阶段哈希：先取样 {SizeText.Format(estimate.SampleSize)} × 候选文件，再全量校验（预计 {SizeText.Format(estimate.EstimatedFullBytes)}）" + Environment.NewLine + Environment.NewLine +
            "首次运行/冷缓存可能更慢。是否继续？" + Environment.NewLine +
            "选「否」即取消，不会开始检测。";

        var choice = MessageBox.Show(this, messageText, "预计加载时间",
            MessageBoxButtons.YesNo, MessageBoxIcon.Question, MessageBoxDefaultButton.Button2);
        return choice == DialogResult.Yes;
    }

    // ---------------- 交互辅助 ----------------
    private void PickFolder(TextBox target, string description)
    {
        using var dialog = new FolderBrowserDialog
        {
            Description = description,
            UseDescriptionForTitle = true,
            SelectedPath = Directory.Exists(target.Text) ? target.Text : Paths.ProjectRoot
        };
        if (dialog.ShowDialog(this) == DialogResult.OK && !string.IsNullOrWhiteSpace(dialog.SelectedPath))
        {
            target.Text = dialog.SelectedPath;
        }
    }

    private void OpenReportFolder()
    {
        if (string.IsNullOrEmpty(_lastReportDirectory) || !Directory.Exists(_lastReportDirectory))
        {
            MessageBox.Show(this, "还没有生成报告，先点击「导出报告」。", "无报告", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }
        OpenPath(_lastReportDirectory);
    }

    private void OnGridCellDoubleClick(object? sender, DataGridViewCellEventArgs e)
    {
        if (e.RowIndex < 0 || sender is not DataGridView grid) { return; }
        var item = grid.Rows[e.RowIndex].DataBoundItem;
        switch (item)
        {
            case DirectoryRow directory: OpenPath(directory.Path); break;
            case FileRow file: RevealPath(file.Path); break;
            case DuplicateRow duplicate: RevealPath(duplicate.SampleFile); break;
            case FindingRow finding: OpenPath(finding.Target); break;
            case CleanRow clean: OpenPath(clean.Path); break;
            case ReportRow report: RevealPath(report.File); break;
        }
    }

    private void OpenPath(string? path)
    {
        if (string.IsNullOrWhiteSpace(path) || !Directory.Exists(path)) { return; }
        StartExplorer(path, selectFile: false);
    }

    private void RevealPath(string? path)
    {
        if (string.IsNullOrWhiteSpace(path)) { return; }
        StartExplorer(path, selectFile: File.Exists(path));
    }

    private void StartExplorer(string path, bool selectFile)
    {
        try
        {
            var arguments = selectFile ? $"/select,\"{path}\"" : $"\"{path}\"";
            Process.Start(new ProcessStartInfo("explorer.exe", arguments) { UseShellExecute = true });
        }
        catch (Exception ex) when (ex is InvalidOperationException or Win32Exception)
        {
            MessageBox.Show(this, "无法打开资源管理器: " + ex.Message, "提示", MessageBoxButtons.OK, MessageBoxIcon.Warning);
        }
    }

    // ---------------- 日志 ----------------
    private void AddLog(LogLevel level, string message) => _log.Add(level, message);

    private void OnLogEntryAdded(object? sender, LogEntry entry)
    {
        if (IsDisposed) { return; }
        if (InvokeRequired)
        {
            try { BeginInvoke(() => AppendLogEntry(entry)); }
            catch (InvalidOperationException) { /* 窗口已销毁 */ }
            return;
        }
        AppendLogEntry(entry);
    }

    private void AppendLogEntry(LogEntry entry)
    {
        _listLog.Items.Add(entry);
        while (_listLog.Items.Count > 500)
        {
            _listLog.Items.RemoveAt(0);
        }
        if (_listLog.Items.Count > 0)
        {
            _listLog.TopIndex = _listLog.Items.Count - 1;
        }
    }

    private void OnLogDrawItem(object? sender, DrawItemEventArgs e)
    {
        try
        {
            if (e.Index < 0 || e.Index >= _listLog.Items.Count) { return; }
            e.DrawBackground();
            if (_listLog.Items[e.Index] is not LogEntry entry) { return; }
            using var brush = new SolidBrush(Theme.ForLogLevel(entry.Level));

            // 注意：e.Font 是 ListBox 自己的 Font 实例，不能 Dispose（否则下一次重绘 GDI+ 抛
            // "Parameter is not valid." 并进入重绘死循环）。只有自己临时创建的才释放。
            var borrowedFont = e.Font;
            var temporaryFont = borrowedFont is null ? Theme.Mono(9f) : null;
            try
            {
                e.Graphics.DrawString(entry.DisplayText, borrowedFont ?? temporaryFont!, brush, e.Bounds);
            }
            finally
            {
                temporaryFont?.Dispose();
            }
            e.DrawFocusRectangle();
        }
        catch (Exception ex)
        {
            // 绘制异常必须吞掉：否则会触发“重绘 → 异常 → 重绘”死循环
            Debug.WriteLine("日志绘制失败: " + ex.Message);
        }
    }

    // ---------------- 快捷键 / 拖拽 / 关闭 ----------------
    private void OnFormKeyDown(object? sender, KeyEventArgs e)
    {
        if (e.Control && e.KeyCode == Keys.O)
        {
            PickFolder(_txtPath, "选择工作区目录");
            e.Handled = true;
            return;
        }
        if (e.KeyCode == Keys.Escape && _running)
        {
            CancelCurrentRun();
            e.Handled = true;
            return;
        }
        foreach (var info in ActionCatalog.All)
        {
            if (info.Shortcut != Keys.None && info.Shortcut == e.KeyCode && !_running)
            {
                _ = RunActionAsync(info.Kind);
                e.Handled = true;
                return;
            }
        }
    }

    private void OnDragEnter(object? sender, DragEventArgs e)
    {
        if (e.Data?.GetDataPresent(DataFormats.FileDrop) == true)
        {
            e.Effect = DragDropEffects.Copy;
        }
    }

    private void OnDragDrop(object? sender, DragEventArgs e)
    {
        if (e.Data?.GetData(DataFormats.FileDrop) is not string[] paths || paths.Length == 0) { return; }
        var firstDirectory = paths.FirstOrDefault(Directory.Exists);
        if (firstDirectory is not null)
        {
            _txtPath.Text = firstDirectory;
        }
    }

    private void OnFormClosing(object? sender, FormClosingEventArgs e)
    {
        if (_running)
        {
            var confirm = MessageBox.Show(this, "当前有动作在运行，确定退出并取消吗？", "退出确认",
                MessageBoxButtons.YesNo, MessageBoxIcon.Question, MessageBoxDefaultButton.Button2);
            if (confirm != DialogResult.Yes)
            {
                e.Cancel = true;
                return;
            }
            _cts?.Cancel();
        }
        CaptureSettings();
        _bridge.Dispose();
        _elapsedTimer.Dispose();
    }

    protected override void OnLoad(EventArgs e)
    {
        base.OnLoad(e);
        try
        {
            if (_splitContainer.Width > 800)
            {
                _splitContainer.Panel1MinSize = 220;
                _splitContainer.Panel2MinSize = 420;
                _splitContainer.SplitterDistance = 300;
            }
        }
        catch (InvalidOperationException)
        {
            // 窗口尺寸过小时忽略，保持默认分隔位置
        }
    }

    /// <summary>UI 回归测试：切到「日志」页（会触发 owner-draw 绘制）。</summary>
    internal void ShowLogTabForTest()
    {
        SelectTab(7);
    }

    /// <summary>截图模式使用：注入演示数据，不启动桥接进程。</summary>
    internal void InjectDemoData()
    {
        _txtPath.Text = @"D:\1Work";
        _overview.Root = @"D:\1Work";
        _overview.TotalFiles = "146,797";
        _overview.TotalSize = "40.85 GB";
        _overview.Directories = "12,431";
        _overview.Duration = "2,110 ms";
        _overview.Status = "扫描完成：146,797 个文件 / 40.85 GB（DirBucket 并行 2.11x）";
        _headline.Headline = "扫描完成：146,797 个文件 / 40.85 GB（DirBucket 并行 2.11x）";
        _headline.Detail = "目录 12,431 个 · 耗时 2,110 ms · 访问错误 0 · 模块 v1.0.0";
        _chkParallel.Checked = true;
        _chkDryRun.Checked = true;

        ReplaceRows(_directories, new List<DirectoryRow>
        {
            new(@"D:\1Work\素材\视频素材", 502, 18745600000, "17.5 GB", "Warn"),
            new(@"D:\1Work\.dsh-snapshots\20261108-111600-weekly", 1944, 2800000000, "2.6 GB", "Warn"),
            new(@"D:\1Work\tools\userscripts", 214, 10100000, "9.6 MB", "Ok"),
            new(@"D:\1Work\项目\ws-doctor\gui", 32, 860000, "840 KB", "Ok")
        });
        ReplaceRows(_topFiles, new List<FileRow>
        {
            new(@"D:\1Work\素材\视频素材\demo.mp4", 1874560000, "1.7 GB"),
            new(@"D:\1Work\.dsh-snapshots\20261108-111600-weekly\body.zip", 986000000, "940 MB")
        });
        ReplaceRows(_duplicates, new List<DuplicateRow>
        {
            new(45145, "44 KB", 2, 45145, "44 KB", "E3BBE37AEB93EDCD…", @"D:\1Work\项目\ws-doctor\dist\wsdoctor-1.0.0.zip",
                new[] { @"D:\1Work\项目\ws-doctor\dist\wsdoctor-1.0.0.zip", @"D:\1Work\项目\ws-doctor\dist\backup.zip" })
        });
        ReplaceRows(_findings, new List<FindingRow>
        {
            new("Info", "疑似残留", @"D:\1Work\2287723691", "目录名匹配残留规则 /^\\d{6,}$/", "确认无用后删除"),
            new("Info", "空目录", @"D:\1Work\temp", "temp 目录为空，可删除", "删除空目录")
        });
        ReplaceRows(_reportRows, new List<ReportRow>
        {
            new(@"D:\1Work\项目\ws-doctor\reports\wsdoctor-20261108-134550.json"),
            new(@"D:\1Work\项目\ws-doctor\reports\wsdoctor-20261108-134550.html")
        });
        _btnOpenReports.Enabled = true;
        _header.StatusText = "完成";
        _header.StatusColor = Theme.Success;
        _lastReportDirectory = @"D:\1Work\项目\ws-doctor\reports";
        AddLog(LogLevel.Info, "扫描 D:\\1Work（DirBucket 并行，ThrottleLimit=8）");
        AddLog(LogLevel.Debug, "桥接进程 pid=4242，等待结果…");
        AddLog(LogLevel.Info, "桥接完成（2,110 ms）");
        AddLog(LogLevel.Info, "完成：Scan（2,110 ms，模块 1.0.0）");
        SelectTab(0);
    }
}
