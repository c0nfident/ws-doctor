// Controls.cs — 自定义绘制控件（继承 / override / OnPaint / DoubleBuffered）
#nullable enable

namespace WsDoctorGui.Ui.Controls;

/// <summary>顶部标题栏：渐变背景 + 标题/副标题 + 右侧状态胶囊。</summary>
public sealed class HeaderPanel : Panel
{
    private string _title = "WsDoctor";
    private string _subtitle = "工作区体检工具";
    private string _statusText = "就绪";
    private Color _statusColor = Theme.TextMuted;

    public HeaderPanel()
    {
        DoubleBuffered = true;
        BackColor = Theme.Accent;
        ForeColor = Color.White;
        Height = 82;
        Dock = DockStyle.Top;
        ResizeRedraw = true;
    }

    public string Title { get => _title; set { _title = value; Invalidate(); } }
    public string Subtitle { get => _subtitle; set { _subtitle = value; Invalidate(); } }

    public string StatusText { get => _statusText; set { _statusText = value; Invalidate(); } }

    public Color StatusColor { get => _statusColor; set { _statusColor = value; Invalidate(); } }

    protected override void OnPaint(PaintEventArgs e)
    {
        if (ClientSize.Width <= 0 || ClientSize.Height <= 0) { return; }
        var graphics = e.Graphics;
        graphics.SmoothingMode = SmoothingMode.AntiAlias;

        using (var backdrop = new LinearGradientBrush(ClientRectangle,
                   Color.FromArgb(0, 99, 177), Color.FromArgb(0, 140, 232), LinearGradientMode.Horizontal))
        {
            graphics.FillRectangle(backdrop, ClientRectangle);
        }

        using (var accent = new SolidBrush(Color.FromArgb(64, 255, 255, 255)))
        {
            graphics.FillRectangle(accent, new Rectangle(0, 0, 6, Height));
        }

        using var titleFont = Theme.Ui(17f, bold: true);
        using var subtitleFont = Theme.Ui(9.5f);
        using var titleBrush = new SolidBrush(Color.White);
        using var subtitleBrush = new SolidBrush(Color.FromArgb(220, 235, 250));

        graphics.DrawString(_title, titleFont, titleBrush, new PointF(24, 12));
        graphics.DrawString(_subtitle, subtitleFont, subtitleBrush, new PointF(24, 45));

        // 右侧状态胶囊：宽度按文字测量，且不侵入左侧标题区
        using var statusMeasureFont = Theme.Ui(9f, bold: true);
        var measured = TextRenderer.MeasureText(_statusText, statusMeasureFont);
        var chipWidth = Math.Max(96, Math.Min(measured.Width + 44, Width - 380));
        var statusRect = new Rectangle(Width - chipWidth - 24, 26, chipWidth, 30);
        using (var chipBrush = new SolidBrush(Color.FromArgb(56, 255, 255, 255)))
        {
            graphics.FillRoundedRectangle(chipBrush, statusRect, 15);
        }
        using (var dotBrush = new SolidBrush(_statusColor))
        {
            graphics.FillEllipse(dotBrush, statusRect.X + 12, statusRect.Y + 12, 6, 6);
        }
        using var statusBrush = new SolidBrush(Color.White);
        graphics.DrawString(_statusText, statusMeasureFont, statusBrush, new PointF(statusRect.X + 24, statusRect.Y + 7));
    }
}

/// <summary>统计卡片：标题 + 大数值 + 强调色（自定义绘制、属性触发重绘）。</summary>
public sealed class StatCard : Control
{
    private string _cardTitle = "统计";
    private string _value = "—";
    private Color _accent = Theme.Accent;

    public StatCard()
    {
        DoubleBuffered = true;
        BackColor = Theme.Surface;
        Size = new Size(180, 96);
        Margin = new Padding(6);
    }

    public string CardTitle { get => _cardTitle; set { _cardTitle = value; Invalidate(); } }
    public string Value { get => _value; set { _value = value; Invalidate(); } }
    public Color Accent { get => _accent; set { _accent = value; Invalidate(); } }

    protected override void OnPaint(PaintEventArgs e)
    {
        if (ClientSize.Width <= 0 || ClientSize.Height <= 0) { return; }
        var graphics = e.Graphics;
        graphics.SmoothingMode = SmoothingMode.AntiAlias;
        graphics.Clear(Parent?.BackColor ?? Theme.Canvas);

        var card = new Rectangle(0, 0, Width - 1, Height - 1);
        using (var fill = new SolidBrush(BackColor))
        {
            graphics.FillRoundedRectangle(fill, card, 10);
        }
        using (var border = new Pen(Theme.Border))
        {
            graphics.DrawRoundedRectangle(border, card, 10);
        }
        using (var accentBrush = new SolidBrush(_accent))
        {
            graphics.FillRectangle(accentBrush, new Rectangle(16, 16, 4, Height - 32));
        }

        using var titleFont = Theme.Ui(9f);
        using var valueFont = Theme.Ui(16f, bold: true);
        using var titleBrush = new SolidBrush(Theme.TextMuted);
        using var valueBrush = new SolidBrush(Theme.TextPrimary);
        graphics.DrawString(_cardTitle, titleFont, titleBrush, new PointF(30, 16));
        graphics.DrawString(_value, valueFont, valueBrush, new RectangleF(30, 40, Width - 40, Height - 48));
    }
}

/// <summary>带圆角底色的只读信息条（用于 Headline 展示）。</summary>
public sealed class HeadlineBar : Control
{
    private string _headline = string.Empty;
    private string _detail = string.Empty;

    public HeadlineBar()
    {
        DoubleBuffered = true;
        Height = 64;
        BackColor = Theme.AccentSoft;
        ForeColor = Theme.TextPrimary;
    }

    public string Headline
    {
        get => _headline;
        set { _headline = value; Invalidate(); }
    }

    public string Detail
    {
        get => _detail;
        set { _detail = value; Invalidate(); }
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        if (ClientSize.Width <= 0 || ClientSize.Height <= 0) { return; }
        var graphics = e.Graphics;
        graphics.SmoothingMode = SmoothingMode.AntiAlias;
        graphics.Clear(Parent?.BackColor ?? Theme.Canvas);
        var rect = new Rectangle(0, 0, Width - 1, Height - 1);
        using (var fill = new SolidBrush(BackColor))
        {
            graphics.FillRoundedRectangle(fill, rect, 10);
        }
        using var headlineFont = Theme.Ui(10.5f, bold: true);
        using var detailFont = Theme.Ui(9f);
        using var headlineBrush = new SolidBrush(Theme.TextPrimary);
        using var detailBrush = new SolidBrush(Theme.TextMuted);
        graphics.DrawString(_headline, headlineFont, headlineBrush, new PointF(18, 12));
        if (!string.IsNullOrEmpty(_detail))
        {
            graphics.DrawString(_detail, detailFont, detailBrush, new PointF(18, 36));
        }
    }
}
