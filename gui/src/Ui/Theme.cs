// Theme.cs — 调色板 / 绘图扩展 / 控件样式（静态类 + 扩展方法 + 圆角绘制）
#nullable enable

namespace WsDoctorGui.Ui;

public static class Theme
{
    public static readonly Color Canvas = Color.FromArgb(243, 246, 250);
    public static readonly Color Surface = Color.White;
    public static readonly Color Border = Color.FromArgb(224, 228, 234);
    public static readonly Color Accent = Color.FromArgb(0, 120, 212);
    public static readonly Color AccentSoft = Color.FromArgb(232, 242, 252);
    public static readonly Color TextPrimary = Color.FromArgb(32, 38, 46);
    public static readonly Color TextMuted = Color.FromArgb(100, 110, 122);
    public static readonly Color Success = Color.FromArgb(16, 124, 16);
    public static readonly Color Warning = Color.FromArgb(157, 93, 0);
    public static readonly Color Danger = Color.FromArgb(196, 43, 28);

    public static Font Ui(float size = 9f, bool bold = false) =>
        new("Segoe UI", size, bold ? FontStyle.Bold : FontStyle.Regular, GraphicsUnit.Point);

    public static Font Mono(float size = 9f) =>
        new("Cascadia Mono", size, FontStyle.Regular, GraphicsUnit.Point);

    public static Color ForSeverity(string? severity) => severity?.ToLowerInvariant() switch
    {
        "error" => Danger,
        "warn" => Warning,
        "info" => Accent,
        null or "" => TextMuted,
        _ => Success
    };

    public static Color ForLogLevel(LogLevel level) => level switch
    {
        LogLevel.Error => Danger,
        LogLevel.Warn => Warning,
        LogLevel.Debug => TextMuted,
        _ => TextPrimary
    };
}

/// <summary>绘图扩展：圆角矩形路径/填充/描边（扩展方法 + using 语句练习）。</summary>
public static class DrawingExtensions
{
    public static GraphicsPath CreateRoundedPath(Rectangle bounds, int radius)
    {
        var path = new GraphicsPath();
        if (radius <= 0 || bounds.Width <= 0 || bounds.Height <= 0)
        {
            path.AddRectangle(bounds);
            return path;
        }
        var diameter = Math.Min(radius * 2, Math.Min(bounds.Width, bounds.Height));
        var arc = new Rectangle(bounds.Location, new Size(diameter, diameter));
        path.AddArc(arc, 180, 90);
        arc.X = bounds.Right - diameter;
        path.AddArc(arc, 270, 90);
        arc.Y = bounds.Bottom - diameter;
        path.AddArc(arc, 0, 90);
        arc.X = bounds.Left;
        path.AddArc(arc, 90, 90);
        path.CloseFigure();
        return path;
    }

    public static void FillRoundedRectangle(this Graphics graphics, Brush brush, Rectangle bounds, int radius)
    {
        using var path = CreateRoundedPath(bounds, radius);
        graphics.FillPath(brush, path);
    }

    public static void DrawRoundedRectangle(this Graphics graphics, Pen pen, Rectangle bounds, int radius)
    {
        using var path = CreateRoundedPath(bounds, radius);
        graphics.DrawPath(pen, path);
    }
}

public static class ControlStyling
{
    public static void ApplyCard(this Control control)
    {
        control.BackColor = Theme.Surface;
        control.Padding = new Padding(12);
    }

    public static void ApplyRoundedRegion(this Control control, int radius = 10)
    {
        if (control.Width <= 0 || control.Height <= 0) { return; }
        using var path = DrawingExtensions.CreateRoundedPath(new Rectangle(0, 0, control.Width, control.Height), radius);
        var old = control.Region;
        control.Region = new Region(path);
        old?.Dispose();
    }

    public static void StylePrimaryButton(this Button button)
    {
        button.FlatStyle = FlatStyle.Flat;
        button.FlatAppearance.BorderSize = 0;
        button.BackColor = Theme.Accent;
        button.ForeColor = Color.White;
        button.Font = Theme.Ui(9f, bold: true);
        button.Cursor = Cursors.Hand;
    }

    public static void StyleSecondaryButton(this Button button)
    {
        button.FlatStyle = FlatStyle.Flat;
        button.FlatAppearance.BorderColor = Theme.Border;
        button.BackColor = Theme.Surface;
        button.ForeColor = Theme.TextPrimary;
        button.Font = Theme.Ui(9f);
        button.Cursor = Cursors.Hand;
    }
}
