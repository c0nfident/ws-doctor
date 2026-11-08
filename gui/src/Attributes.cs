// Attributes.cs — 自定义特性 + 反射驱动的动作目录
#nullable enable

namespace WsDoctorGui;

/// <summary>动作元数据：标题 / 描述 / 快捷键。挂在 WsActionKind 枚举字段上，由反射读取。</summary>
[AttributeUsage(AttributeTargets.Field, AllowMultiple = false)]
public sealed class WsActionAttribute(string title, string description, Keys shortcut = Keys.None) : Attribute
{
    public string Title { get; } = title;
    public string Description { get; } = description;
    public Keys Shortcut { get; } = shortcut;
}

/// <summary>反射结果快照（record 不可变）。</summary>
public sealed record WsActionInfo(WsActionKind Kind, string Title, string Description, Keys Shortcut)
{
    public override string ToString() => $"{Title}（{Shortcut}）";
}

/// <summary>动作目录：启动时反射一次，之后 O(1) 查询。</summary>
public static class ActionCatalog
{
    private static readonly IReadOnlyList<WsActionInfo> s_actions = Build();
    private static readonly Dictionary<WsActionKind, WsActionInfo> s_byKind =
        s_actions.ToDictionary(a => a.Kind);

    public static IReadOnlyList<WsActionInfo> All => s_actions;

    public static WsActionInfo For(WsActionKind kind) => s_byKind[kind];

    private static List<WsActionInfo> Build()
    {
        var list = new List<WsActionInfo>();
        foreach (var value in Enum.GetValues<WsActionKind>())
        {
            var field = typeof(WsActionKind).GetField(value.ToString());
            var meta = field?.GetCustomAttributes(typeof(WsActionAttribute), inherit: false)
                            .OfType<WsActionAttribute>()
                            .FirstOrDefault();
            if (meta is null)
            {
                list.Add(new WsActionInfo(value, value.ToString(), "（无元数据）", Keys.None));
                continue;
            }
            list.Add(new WsActionInfo(value, meta.Title, meta.Description, meta.Shortcut));
        }
        return list;
    }
}
