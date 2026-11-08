// MainForm.Layout.cs — 界面构建（partial class；控件/布局/数据绑定）
#nullable enable

namespace WsDoctorGui;

public sealed partial class MainForm
{
    private HeaderPanel _header = null!;
    private HeadlineBar _headline = null!;
    private TextBox _txtPath = null!;
    private Button _btnBrowse = null!;
    private Button _btnOpenReports = null!;
    private Button _btnCancel = null!;
    private NumericUpDown _numTop = null!;
    private NumericUpDown _numMinDup = null!;
    private ComboBox _cmbMode = null!;
    private CheckBox _chkParallel = null!;
    private CheckBox _chkDryRun = null!;
    private TextBox _txtOutDir = null!;
    private Button _btnBrowseOut = null!;
    private FlowLayoutPanel _flowActions = null!;
    private TabControl _tabControl = null!;
    private SplitContainer _splitContainer = null!;
    private DataGridView _gridDirectories = null!;
    private DataGridView _gridTopFiles = null!;
    private DataGridView _gridDuplicates = null!;
    private DataGridView _gridFindings = null!;
    private DataGridView _gridClean = null!;
    private DataGridView _gridReports = null!;
    private ListBox _listLog = null!;
    private StatCard _cardFiles = null!;
    private StatCard _cardSize = null!;
    private StatCard _cardDirectories = null!;
    private StatCard _cardDuration = null!;
    private Label _lblOverviewRoot = null!;
    private Label _lblOverviewStatus = null!;
    private Label _lblOptionsHint = null!;
    private ToolStripStatusLabel _statusLabel = null!;
    private ToolStripStatusLabel _elapsedLabel = null!;
    private ToolStripStatusLabel _versionLabel = null!;
    private ToolStripProgressBar _progressBar = null!;

    private BindingSource _sourceDirectories = null!;
    private BindingSource _sourceTopFiles = null!;
    private BindingSource _sourceDuplicates = null!;
    private BindingSource _sourceFindings = null!;
    private BindingSource _sourceClean = null!;
    private BindingSource _sourceReports = null!;

    private void InitializeComponent()
    {
        SuspendLayout();
        Text = "WsDoctor · 工作区体检（C# WinForms 前端）";
        StartPosition = FormStartPosition.CenterScreen;
        MinimumSize = new Size(980, 640);
        Size = new Size(1200, 780);
        BackColor = Theme.Canvas;
        Font = Theme.Ui(9f);
        KeyPreview = true;
        AllowDrop = true;

        var root = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 1,
            RowCount = 5,
            BackColor = Theme.Canvas,
            Padding = new Padding(0)
        };
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 82));  // header
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 50));  // actions
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 42));  // path
        root.RowStyles.Add(new RowStyle(SizeType.Percent, 100)); // content
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 26));  // status

        _header = new HeaderPanel
        {
            Title = "WsDoctor",
            Subtitle = "工作区体检 · C# WinForms 前端（PowerShell 桥接）",
            Dock = DockStyle.Fill
        };

        root.Controls.Add(_header, 0, 0);
        root.Controls.Add(BuildActionBar(), 0, 1);
        root.Controls.Add(BuildPathBar(), 0, 2);
        root.Controls.Add(BuildContent(), 0, 3);
        root.Controls.Add(BuildStatusStrip(), 0, 4);

        Controls.Add(root);
        ResumeLayout(performLayout: true);
    }

    private Control BuildActionBar()
    {
        _flowActions = new FlowLayoutPanel
        {
            Dock = DockStyle.Fill,
            FlowDirection = FlowDirection.LeftToRight,
            WrapContents = false,
            Padding = new Padding(16, 8, 16, 8),
            BackColor = Theme.Canvas
        };

        var toolTip = new ToolTip { AutoPopDelay = 9000, InitialDelay = 300 };
        foreach (var info in ActionCatalog.All)
        {
            var button = new Button
            {
                Text = info.Title,
                AutoSize = false,
                Width = 104,
                Height = 32,
                Margin = new Padding(0, 0, 8, 0),
                Tag = info.Kind
            };
            button.StylePrimaryButton();
            var kind = info.Kind;
            button.Click += (_, _) => OnActionButtonClick(kind);
            toolTip.SetToolTip(button, info.Description + "\n快捷键: " + info.Shortcut);
            _flowActions.Controls.Add(button);
        }

        _btnCancel = new Button
        {
            Text = "取消",
            Width = 76,
            Height = 32,
            Enabled = false
        };
        _btnCancel.StyleSecondaryButton();
        _btnCancel.Click += (_, _) => CancelCurrentRun();
        _flowActions.Controls.Add(_btnCancel);
        return _flowActions;
    }

    private Control BuildPathBar()
    {
        var bar = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 4,
            RowCount = 1,
            Padding = new Padding(16, 4, 16, 4),
            BackColor = Theme.Canvas
        };
        bar.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 80));
        bar.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        bar.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 90));
        bar.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 120));

        var label = new Label
        {
            Text = "工作区:",
            TextAlign = ContentAlignment.MiddleLeft,
            ForeColor = Theme.TextPrimary,
            Dock = DockStyle.Fill
        };
        _txtPath = new TextBox
        {
            Dock = DockStyle.Fill,
            Text = "D:\\1Work",
            Margin = new Padding(0, 6, 8, 6)
        };
        _btnBrowse = new Button { Text = "浏览…", Dock = DockStyle.Fill, Margin = new Padding(0, 2, 4, 2) };
        _btnBrowse.StyleSecondaryButton();
        _btnOpenReports = new Button { Text = "打开报告", Dock = DockStyle.Fill, Margin = new Padding(4, 2, 0, 2), Enabled = false };
        _btnOpenReports.StyleSecondaryButton();

        bar.Controls.Add(label, 0, 0);
        bar.Controls.Add(_txtPath, 1, 0);
        bar.Controls.Add(_btnBrowse, 2, 0);
        bar.Controls.Add(_btnOpenReports, 3, 0);
        return bar;
    }

    private Control BuildContent()
    {
        var split = new SplitContainer
        {
            Dock = DockStyle.Fill,
            Orientation = Orientation.Vertical,
            FixedPanel = FixedPanel.Panel1,
            SplitterWidth = 6,
            BackColor = Theme.Canvas
        };

        _splitContainer = split;
        split.Panel1.BackColor = Theme.Canvas;
        split.Panel1.Padding = new Padding(16, 8, 8, 8);
        split.Panel1.Controls.Add(BuildOptionsPanel());

        _tabControl = new TabControl
        {
            Dock = DockStyle.Fill,
            Padding = new Point(14, 6)
        };
        _tabControl.TabPages.Add(BuildOverviewTab());

        _sourceDirectories = new BindingSource { DataSource = _directories };
        _sourceTopFiles = new BindingSource { DataSource = _topFiles };
        _sourceDuplicates = new BindingSource { DataSource = _duplicates };
        _sourceFindings = new BindingSource { DataSource = _findings };
        _sourceClean = new BindingSource { DataSource = _cleanRows };
        _sourceReports = new BindingSource { DataSource = _reportRows };

        _gridDirectories = CreateGrid(("目录", "Path", 60), ("文件数", "Files", 12), ("大小", "SizeText", 14), ("级别", "Severity", 12));
        _gridDirectories.DataSource = _sourceDirectories;
        _tabControl.TabPages.Add(CreateGridTab("目录", _gridDirectories));

        _gridTopFiles = CreateGrid(("文件", "Path", 80), ("大小", "SizeText", 20));
        _gridTopFiles.DataSource = _sourceTopFiles;
        _tabControl.TabPages.Add(CreateGridTab("大文件", _gridTopFiles));

        _gridDuplicates = CreateGrid(
            ("样例文件", "SampleFile", 60), ("份数", "FileCount", 10),
            ("单文件", "SizeText", 12), ("可回收", "WastedText", 12), ("SHA256", "Hash", 30));
        _gridDuplicates.DataSource = _sourceDuplicates;
        _tabControl.TabPages.Add(CreateGridTab("重复文件", _gridDuplicates));

        _gridFindings = CreateGrid(("级别", "Severity", 10), ("类别", "Category", 16), ("目标", "Target", 36), ("说明", "Message", 38));
        _gridFindings.DataSource = _sourceFindings;
        _tabControl.TabPages.Add(CreateGridTab("规则体检", _gridFindings));

        _gridClean = CreateGrid(("已处理目录", "Path", 100));
        _gridClean.DataSource = _sourceClean;
        _tabControl.TabPages.Add(CreateGridTab("空目录清理", _gridClean));

        _gridReports = CreateGrid(("报告文件", "File", 100));
        _gridReports.DataSource = _sourceReports;
        _tabControl.TabPages.Add(CreateGridTab("报告", _gridReports));

        _listLog = new ListBox
        {
            Dock = DockStyle.Fill,
            DrawMode = DrawMode.OwnerDrawFixed,
            ItemHeight = 18,
            BorderStyle = BorderStyle.None,
            Font = Theme.Mono(9f),
            BackColor = Theme.Surface,
            IntegralHeight = false
        };
        var logTab = new TabPage("日志") { BackColor = Theme.Surface, Padding = new Padding(8) };
        logTab.Controls.Add(_listLog);
        _tabControl.TabPages.Add(logTab);

        split.Panel2.Padding = new Padding(0, 8, 16, 8);
        split.Panel2.Controls.Add(_tabControl);
        return split;
    }

    private Control BuildOptionsPanel()
    {
        var panel = new Panel { Dock = DockStyle.Fill, BackColor = Theme.Surface, Padding = new Padding(12) };
        panel.ApplyRoundedRegion(10);

        var title = new Label
        {
            Text = "选项",
            Dock = DockStyle.Top,
            Height = 28,
            Font = Theme.Ui(11f, bold: true),
            ForeColor = Theme.TextPrimary
        };
        panel.Controls.Add(title);

        var flow = new FlowLayoutPanel
        {
            Dock = DockStyle.Top,
            AutoSize = true,
            FlowDirection = FlowDirection.TopDown,
            WrapContents = false,
            Padding = new Padding(0, 4, 0, 0)
        };

        _numTop = AddNumberOption(flow, "Top 数量", 1, 100, 10);
        _numMinDup = AddNumberOption(flow, "重复文件最小字节", 0, int.MaxValue, 1024);
        _cmbMode = AddComboOption(flow, "并行模式", new[] { "DirBucket", "Subtree", "Chunk" });
        _chkParallel = AddCheckOption(flow, "启用并行扫描", check: true);
        _chkDryRun = AddCheckOption(flow, "DryRun（清理只预览）", check: true);

        var outLabel = new Label { Text = "报告输出目录:", AutoSize = true, Margin = new Padding(0, 8, 0, 2), ForeColor = Theme.TextMuted };
        flow.Controls.Add(outLabel);
        var outRow = new TableLayoutPanel { AutoSize = true, ColumnCount = 2, RowCount = 1, Width = 222, Margin = new Padding(0) };
        outRow.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        outRow.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 60));
        _txtOutDir = new TextBox { Width = 124, Text = "", Margin = new Padding(0) };
        _btnBrowseOut = new Button { Text = "选择…", Width = 92, Margin = new Padding(6, 0, 0, 0) };
        _btnBrowseOut.StyleSecondaryButton();
        outRow.Controls.Add(_txtOutDir, 0, 0);
        outRow.Controls.Add(_btnBrowseOut, 1, 0);
        flow.Controls.Add(outRow);

        _lblOptionsHint = new Label
        {
            Dock = DockStyle.Fill,
            Text = "快捷键：F5 扫描 · F6 重复 · F7 清理 · F8 体检 · F9 报告 · Esc 取消\n\n" +
                   "提示：真实删除前会二次确认；报告导出会写入 JSON/CSV/HTML 并在「报告」页列出。",
            ForeColor = Theme.TextMuted,
            Font = Theme.Ui(8.5f)
        };
        panel.Controls.Add(_lblOptionsHint);
        panel.Controls.Add(flow);
        _lblOptionsHint.BringToFront();
        return panel;
    }

    private static NumericUpDown AddNumberOption(FlowLayoutPanel flow, string text, decimal min, decimal max, decimal value)
    {
        var label = new Label { Text = text, AutoSize = true, ForeColor = Theme.TextMuted, Margin = new Padding(0, 4, 0, 0) };
        var numeric = new NumericUpDown
        {
            Minimum = min,
            Maximum = max,
            Value = value,
            Width = 120,
            ThousandsSeparator = true
        };
        flow.Controls.Add(label);
        flow.Controls.Add(numeric);
        return numeric;
    }

    private static ComboBox AddComboOption(FlowLayoutPanel flow, string text, string[] items)
    {
        var label = new Label { Text = text, AutoSize = true, ForeColor = Theme.TextMuted, Margin = new Padding(0, 8, 0, 0) };
        var combo = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Width = 140 };
        combo.Items.AddRange(items);
        combo.SelectedIndex = 0;
        flow.Controls.Add(label);
        flow.Controls.Add(combo);
        return combo;
    }

    private static CheckBox AddCheckOption(FlowLayoutPanel flow, string text, bool check)
    {
        var box = new CheckBox { Text = text, AutoSize = true, Checked = check, ForeColor = Theme.TextPrimary, Margin = new Padding(0, 6, 0, 0) };
        flow.Controls.Add(box);
        return box;
    }

    private TabPage BuildOverviewTab()
    {
        var page = new TabPage("概览") { BackColor = Theme.Surface, Padding = new Padding(10) };
        var layout = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 1, RowCount = 4 };
        layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 112));
        layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 70));
        layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 76));
        layout.RowStyles.Add(new RowStyle(SizeType.Percent, 100));

        var cards = new FlowLayoutPanel { Dock = DockStyle.Fill, FlowDirection = FlowDirection.LeftToRight, WrapContents = false };
        _cardFiles = new StatCard { CardTitle = "文件总数", Value = "—", Accent = Theme.Accent };
        _cardSize = new StatCard { CardTitle = "总大小", Value = "—", Accent = Theme.Success };
        _cardDirectories = new StatCard { CardTitle = "目录数", Value = "—", Accent = Theme.Warning };
        _cardDuration = new StatCard { CardTitle = "耗时", Value = "—", Accent = Theme.TextMuted };
        foreach (var card in new[] { _cardFiles, _cardSize, _cardDirectories, _cardDuration })
        {
            card.Width = 190;
            card.Height = 96;
            cards.Controls.Add(card);
        }

        _cardFiles.DataBindings.Add(nameof(StatCard.Value), _overview, nameof(OverviewModel.TotalFiles), true, DataSourceUpdateMode.Never);
        _cardSize.DataBindings.Add(nameof(StatCard.Value), _overview, nameof(OverviewModel.TotalSize), true, DataSourceUpdateMode.Never);
        _cardDirectories.DataBindings.Add(nameof(StatCard.Value), _overview, nameof(OverviewModel.Directories), true, DataSourceUpdateMode.Never);
        _cardDuration.DataBindings.Add(nameof(StatCard.Value), _overview, nameof(OverviewModel.Duration), true, DataSourceUpdateMode.Never);

        _headline = new HeadlineBar { Dock = DockStyle.Fill, Headline = "尚未运行任何动作", Detail = "从上方按钮或快捷键开始" };
        layout.Controls.Add(cards, 0, 0);
        layout.Controls.Add(_headline, 0, 1);

        var meta = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 2, RowCount = 2 };
        meta.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 80));
        meta.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        _lblOverviewRoot = new Label { Text = "—", ForeColor = Theme.TextPrimary, AutoEllipsis = true, Dock = DockStyle.Fill };
        _lblOverviewStatus = new Label { Text = "就绪", ForeColor = Theme.TextMuted, Dock = DockStyle.Fill };
        _lblOverviewRoot.DataBindings.Add(nameof(Label.Text), _overview, nameof(OverviewModel.Root), true, DataSourceUpdateMode.Never);
        _lblOverviewStatus.DataBindings.Add(nameof(Label.Text), _overview, nameof(OverviewModel.Status), true, DataSourceUpdateMode.Never);
        meta.Controls.Add(new Label { Text = "工作区:", ForeColor = Theme.TextMuted, Dock = DockStyle.Fill }, 0, 0);
        meta.Controls.Add(_lblOverviewRoot, 1, 0);
        meta.Controls.Add(new Label { Text = "状态:", ForeColor = Theme.TextMuted, Dock = DockStyle.Fill }, 0, 1);
        meta.Controls.Add(_lblOverviewStatus, 1, 1);
        layout.Controls.Add(meta, 0, 2);
        layout.Controls.Add(new Label
        {
            Text = "使用说明：\n 1) 选择工作区目录（可拖拽文件夹到窗口）\n 2) 点击动作按钮（扫描 / 重复 / 清理 / 体检 / 报告）\n 3) 左侧选项控制 Top、并行模式、DryRun 与报告输出\n 4) 双击「目录/大文件/重复/体检/报告」行可打开对应位置",
            ForeColor = Theme.TextMuted,
            Dock = DockStyle.Fill
        }, 0, 3);

        page.Controls.Add(layout);
        return page;
    }

    private static DataGridView CreateGrid(params (string Header, string Property, int FillWeight)[] columns)
    {
        var grid = new DataGridView
        {
            Dock = DockStyle.Fill,
            ReadOnly = true,
            AllowUserToAddRows = false,
            AllowUserToDeleteRows = false,
            AllowUserToResizeRows = false,
            AutoGenerateColumns = false,
            SelectionMode = DataGridViewSelectionMode.FullRowSelect,
            MultiSelect = false,
            RowHeadersVisible = false,
            BackgroundColor = Theme.Surface,
            BorderStyle = BorderStyle.None,
            EnableHeadersVisualStyles = false,
            ColumnHeadersHeight = 32,
            GridColor = Theme.Border,
            AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.Fill,
            Font = Theme.Ui(8.5f)
        };
        grid.ColumnHeadersDefaultCellStyle.BackColor = Theme.AccentSoft;
        grid.ColumnHeadersDefaultCellStyle.ForeColor = Theme.TextPrimary;
        grid.ColumnHeadersDefaultCellStyle.Font = Theme.Ui(8.5f, bold: true);
        grid.DefaultCellStyle.SelectionBackColor = Theme.AccentSoft;
        grid.DefaultCellStyle.SelectionForeColor = Theme.TextPrimary;
        grid.DefaultCellStyle.Padding = new Padding(4, 0, 4, 0);

        foreach (var (header, property, weight) in columns)
        {
            grid.Columns.Add(new DataGridViewTextBoxColumn
            {
                HeaderText = header,
                DataPropertyName = property,
                FillWeight = weight,
                SortMode = DataGridViewColumnSortMode.Automatic
            });
        }
        return grid;
    }

    private static TabPage CreateGridTab(string title, DataGridView grid)
    {
        var page = new TabPage(title) { BackColor = Theme.Surface, Padding = new Padding(8) };
        page.Controls.Add(grid);
        return page;
    }

    private Control BuildStatusStrip()
    {
        var strip = new StatusStrip
        {
            SizingGrip = true,
            BackColor = Theme.Surface,
            Font = Theme.Ui(8.5f)
        };
        _statusLabel = new ToolStripStatusLabel("就绪") { Spring = true, TextAlign = ContentAlignment.MiddleLeft };
        _progressBar = new ToolStripProgressBar { Style = ProgressBarStyle.Marquee, Visible = false, Width = 140, Margin = new Padding(8, 0, 8, 0) };
        _elapsedLabel = new ToolStripStatusLabel("—");
        _versionLabel = new ToolStripStatusLabel("GUI");
        strip.Items.AddRange(new ToolStripItem[] { _statusLabel, _progressBar, _elapsedLabel, _versionLabel });
        return strip;
    }
}
