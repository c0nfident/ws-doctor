// SelfTest.cs — C# 知识点自检（无需测试框架；返回失败数）
#nullable enable

namespace WsDoctorGui;

/// <summary>覆盖语言/框架核心知识点的轻量自检。运行：pwsh -STA -File run.ps1 -SelfTest</summary>
public static class SelfTest
{
    private static int s_passed;
    private static int s_failed;

    public static int Execute()
    {
        s_passed = 0;
        s_failed = 0;
        var watch = Stopwatch.StartNew();

        Section("基础类型与运算符", TestBasics);
        Section("字符串与格式化", TestStrings);
        Section("模式匹配与 record", TestRecordsAndPatterns);
        Section("泛型与接口", TestGenerics);
        Section("LINQ", TestLinq);
        Section("集合与迭代器", TestCollections);
        Section("异常处理", TestExceptions);
        Section("反射与特性", TestReflection);
        Section("JSON 序列化", TestJson);
        Section("async/await 与并发", TestAsync);
        Section("自定义绘图与扩展方法", TestDrawingHelpers);

        watch.Stop();
        Console.WriteLine();
        Console.WriteLine($"=== 自检结果：{s_passed} 通过，{s_failed} 失败（{watch.ElapsedMilliseconds} ms）===");
        return s_failed;
    }

    private static void Section(string name, Action action)
    {
        Console.WriteLine();
        Console.WriteLine($"--- {name} ---");
        try
        {
            action();
        }
        catch (Exception ex)
        {
            Fail(name + " 区块异常", ex.Message);
        }
    }

    private static void Check(string name, bool condition, string? detail = null)
    {
        if (condition)
        {
            s_passed++;
            Console.WriteLine("  PASS  " + name);
        }
        else
        {
            Fail(name, detail ?? "断言失败");
        }
    }

    private static void Fail(string name, string detail)
    {
        s_failed++;
        Console.WriteLine("  FAIL  " + name + "  (" + detail + ")");
    }

    private static void TestBasics()
    {
        int a = 7, b = 2;
        Check("整数除法", a / b == 3);
        Check("取模", a % b == 1);
        var nearMax = int.MaxValue;
        Check("checked 溢出保护", Throws<OverflowException>(() => _ = checked(nearMax + 1)));
        Check("位运算", (0b1010 & 0b0110) == 0b0010);
        Check("Math.Clamp", Math.Clamp(500, 1, 100) == 100);
        var (quotient, remainder) = (a / b, a % b);
        Check("元组解构", quotient == 3 && remainder == 1);
        int? nullable = null;
        Check("可空类型 + ??", (nullable ?? -1) == -1);
        nullable ??= 42;
        Check("??= 赋值", nullable == 42);
        Check("三元表达式", (a > b ? "a" : "b") == "a");
    }

    private static void TestStrings()
    {
        var name = "WsDoctor";
        var count = 3;
        Check("字符串插值", $"{name}-{count}" == "WsDoctor-3");
        var raw = """
                  line1
                  "line2"
                  """;
        Check("原始字符串字面量", raw.Contains("\"line2\""));
        Check("StringComparison", "ABC".Equals("abc", StringComparison.OrdinalIgnoreCase));
        var builder = new StringBuilder();
        builder.Append('x', 3);
        Check("StringBuilder", builder.ToString() == "xxx");
        Check("Split 与范围索引", "a,b,c".Split(',')[^1] == "c");
        Check("Join", string.Join("|", new[] { 1, 2, 3 }) == "1|2|3");
        Check("格式化数字", 1234567.ToString("N0") == "1,234,567");
    }

    private static void TestRecordsAndPatterns()
    {
        var first = new DirectoryRow(@"C:\a", 3, 1024, "1 KB", "Info");
        var second = first with { Files = 4 };
        Check("record with 表达式", first != second && second.Files == 4);
        Check("record 值相等", first == new DirectoryRow(@"C:\a", 3, 1024, "1 KB", "Info"));
        var (path, files, _, _, severity) = first;
        Check("record 解构", path == @"C:\a" && files == 3 && severity == "Info");

        static string Describe(object value) => value switch
        {
            int n when n > 100 => "big-int",
            int => "int",
            DirectoryRow { Files: > 2 } row => "dir:" + row.Files,
            string { Length: 0 } => "empty",
            string text => "str:" + text,
            _ => "unknown"
        };
        Check("switch 模式匹配（类型/属性/关系）",
            Describe(5) == "int" && Describe(500) == "big-int" && Describe(first) == "dir:3" && Describe("x") == "str:x");
        Check("is 模式", first is DirectoryRow { Severity: "Info" } row && row.Files == 3);

        var color = Theme.ForSeverity("warn");
        Check("switch 表达式映射颜色", color == Theme.Warning);
    }

    private static void TestGenerics()
    {
        var result = Result<int>.Ok(42);
        Check("泛型 Result.Ok", result.IsSuccess && result.ValueOrThrow() == 42);
        var failure = Result<string>.Fail("boom");
        Check("泛型 Result.Fail", !failure.IsSuccess && failure.Error == "boom");
        Check("ValueOrThrow 抛异常", Throws<BridgeException>(() => failure.ValueOrThrow()));

        var repository = new Repository<DirectoryRow>(new[] { new DirectoryRow("a", 1, 10, "0 KB", "Ok") });
        Check("泛型仓储 Add/Count", repository.Add(new DirectoryRow("b", 2, 20, "0 KB", "Ok")) == 2);
        Check("泛型 Where 查询", repository.Where(row => row.Files > 1).Count() == 1);

        static T Max<T>(IEnumerable<T> values) where T : IComparable<T>
        {
            using var enumerator = values.GetEnumerator();
            if (!enumerator.MoveNext()) { throw new InvalidOperationException("空序列"); }
            var best = enumerator.Current;
            while (enumerator.MoveNext())
            {
                if (enumerator.Current.CompareTo(best) > 0) { best = enumerator.Current; }
            }
            return best;
        }
        Check("泛型约束 IComparable", Max(new[] { 3, 9, 2 }) == 9);
    }

    private static void TestLinq()
    {
        var rows = new[]
        {
            new DirectoryRow("a", 3, 300, "0 KB", "Info"),
            new DirectoryRow("b", 2, 200, "0 KB", "Info"),
            new DirectoryRow("c", 5, 500, "0 KB", "Warn")
        };
        Check("Where/OrderByDescending", rows.Where(r => r.Files >= 2).OrderByDescending(r => r.Size).First().Path == "c");
        Check("GroupBy + 聚合", rows.GroupBy(r => r.Severity).Count() == 2);
        Check("Sum", rows.Sum(r => r.Files) == 10);
        var query = from row in rows where row.Files > 2 orderby row.Path select row.Path;
        Check("查询表达式语法", query.SequenceEqual(new[] { "a", "c" }));
        Check("Select 投影到匿名类型", rows.Select(r => new { r.Path, Mb = r.SizeMb }).First().Path == "a");
        Check("Aggregate", rows.Aggregate(0, (sum, row) => sum + row.Files) == 10);
        Check("Any/All", rows.Any(r => r.Severity == "Warn") && rows.All(r => r.Size > 0));
        Check("Zip", rows.Select(r => r.Files).Zip(new[] { 1, 1, 1 }, (x, y) => x * y).Sum() == 10);
        Check("Chunk（.NET 6+）", rows.Chunk(2).Count() == 2);
        Check("Enumerable.Range", Enumerable.Range(1, 3).Sum() == 6);
    }

    private static void TestCollections()
    {
        var list = new List<int> { 3, 1, 2 };
        list.Sort();
        Check("List 排序", list.SequenceEqual(new[] { 1, 2, 3 }));

        var dictionary = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        dictionary["A"] = 1;
        dictionary["B"] = 2;
        Check("Dictionary + 大小写不敏感", dictionary["a"] == 1);
        Check("TryGetValue", dictionary.TryGetValue("b", out var value) && value == 2);

        var set = new HashSet<int> { 1, 2, 2, 3 };
        Check("HashSet 去重", set.Count == 3);

        var stack = new Stack<int>();
        stack.Push(1);
        stack.Push(2);
        Check("Stack LIFO", stack.Pop() == 2);

        var queue = new Queue<string>();
        queue.Enqueue("a");
        queue.Enqueue("b");
        Check("Queue FIFO", queue.Dequeue() == "a");

        var buffer = new LogBuffer(3);
        buffer.Info("one");
        buffer.Info("two");
        buffer.Info("three");
        buffer.Info("four");
        Check("环形缓冲容量", buffer.Count == 3);
        Check("环形缓冲索引器（最旧）", buffer[0].Message == "two");
        Check("环形缓冲迭代器", buffer.Enumerate().Count() == 3);
        Check("Tail 最近条目", buffer.Tail(1).Single().Message == "four");
    }

    private static void TestExceptions()
    {
        Check("try/catch/finally", RunWithFinally());
        Check("异常过滤器 catch when", Throws<IOException>(() => ThrowFiltered(new IOException("io"))));
        Check("自定义异常带 ExitCode", new BridgeException("x", 7).ExitCode == 7);
        Check("using 声明与 IDisposable", UsingDisposable());
        Check("ArgumentNullException.ThrowIfNull", Throws<ArgumentNullException>(() => ArgumentNullException.ThrowIfNull((string?)null, "value")));
    }

    private static bool RunWithFinally()
    {
        var flag = false;
        try
        {
            throw new InvalidOperationException("expected");
        }
        catch (InvalidOperationException)
        {
            flag = true;
        }
        finally
        {
            flag &= true;
        }
        return flag;
    }

    private static void ThrowFiltered(Exception exception)
    {
        try
        {
            throw exception;
        }
        catch (Exception ex) when (ex is IOException)
        {
            throw;
        }
    }

    private static bool UsingDisposable()
    {
        using var disposable = new Countdown();
        return true;
    }

    private sealed class Countdown : IDisposable
    {
        private bool _disposed;
        public void Dispose() => _disposed = true;
        public bool IsDisposed => _disposed;
    }

    private static void TestReflection()
    {
        var info = ActionCatalog.For(WsActionKind.Scan);
        Check("反射读取特性标题", info.Title == "扫描");
        Check("反射读取快捷键", info.Shortcut == Keys.F5);
        Check("动作目录数量", ActionCatalog.All.Count == Enum.GetValues<WsActionKind>().Length);

        var type = typeof(BridgeResult);
        Check("反射构造对象",
            Activator.CreateInstance(type, "scan", true, string.Empty, 1.5, "1.0.0", JsonDocument.Parse("{}").RootElement) is BridgeResult);

        var method = typeof(string).GetMethod("ToUpperInvariant");
        Check("反射调用方法", method?.Invoke("abc", null) as string == "ABC");
    }

    private static void TestJson()
    {
        var result = new BridgeResult("scan", true, string.Empty, 12.5, "1.0.0", JsonDocument.Parse("""{"kind":"scan","totalFiles":5}""").RootElement);
        var json = JsonSerializer.Serialize(result, JsonConfig.Options);
        var roundtrip = JsonSerializer.Deserialize<BridgeResult>(json, JsonConfig.Options);
        Check("BridgeResult JSON 往返", roundtrip is not null && roundtrip.Action == "scan" && roundtrip.Payload.GetInt32OrDefault("totalFiles") == 5);
        Check("JsonElement 扩展方法", result.Payload.GetStringOrEmpty("kind") == "scan");
        Check("JsonSerializer 序列化 record", JsonSerializer.Serialize(new { a = 1 }, JsonConfig.Options) == """{"a":1}""");
        Check("JSON 反序列化 settings", JsonSerializer.Deserialize<AppSettings>("""{"Top":7}""", JsonConfig.Options)?.Top == 7);
    }

    private static void TestAsync()
    {
        var value = ComputeAsync(21).GetAwaiter().GetResult();
        Check("async/await + Task", value == 42);

        var sum = SumAsync(new[] { 1, 2, 3 }).GetAwaiter().GetResult();
        Check("async 循环", sum == 6);

        var cts = new CancellationTokenSource();
        cts.Cancel();
        Check("取消令牌", Throws<OperationCanceledException>(() => WaitAsync(cts.Token).GetAwaiter().GetResult()));

        var progressValues = new List<string>();
        IProgress<string> progress = new Progress<string>(text => progressValues.Add(text));
        progress.Report("hello");
        Thread.Sleep(50);
        Check("IProgress<T> 回调", progressValues.Contains("hello"));

        Check("Parallel LINQ", Enumerable.Range(1, 100).AsParallel().Where(n => n % 2 == 0).Count() == 50);
        Check("Task.Run 并发", Task.Run(() => 7 * 6).Result == 42);
    }

    private static async Task<int> ComputeAsync(int input)
    {
        await Task.Delay(10).ConfigureAwait(false);
        return input * 2;
    }

    private static async Task<int> SumAsync(IEnumerable<int> values)
    {
        var sum = 0;
        foreach (var value in values)
        {
            await Task.Yield();
            sum += value;
        }
        return sum;
    }

    private static async Task WaitAsync(CancellationToken cancellationToken)
    {
        await Task.Delay(1000, cancellationToken).ConfigureAwait(false);
    }

    private static void TestDrawingHelpers()
    {
        using var bitmap = new Bitmap(20, 20);
        using (var graphics = Graphics.FromImage(bitmap))
        {
            using var brush = new SolidBrush(Color.Red);
            graphics.FillRoundedRectangle(brush, new Rectangle(0, 0, 20, 20), 4);
        }
        var pixel = bitmap.GetPixel(10, 10);
        Check("圆角绘制扩展方法", pixel.A > 0);

        using var path = DrawingExtensions.CreateRoundedPath(new Rectangle(0, 0, 10, 10), 3);
        Check("GraphicsPath 生成", path.PointCount > 0);

        Check("主题颜色映射", Theme.ForSeverity("error") == Theme.Danger);
        Check("扩展方法 ForLogLevel", Theme.ForLogLevel(LogLevel.Warn) == Theme.Warning);

        var enumerable = new[] { 1, 2, 3 }.Select(x => x * x);
        Check("自定义扩展 + LINQ 混合", enumerable.Sum() == 14);
    }

    private static bool Throws<TException>(Action action) where TException : Exception
    {
        try
        {
            action();
            return false;
        }
        catch (TException)
        {
            return true;
        }
        catch
        {
            return false;
        }
    }
}

/// <summary>泛型仓储（练习：泛型类 + 接口约束 + 集合封装）。</summary>
public sealed class Repository<T> where T : class
{
    private readonly List<T> _items;

    public Repository(IEnumerable<T>? initial = null)
    {
        _items = initial is null ? [] : new List<T>(initial);
    }

    public int Count => _items.Count;

    public int Add(T item)
    {
        ArgumentNullException.ThrowIfNull(item);
        _items.Add(item);
        return _items.Count;
    }

    public IEnumerable<T> Where(Func<T, bool> predicate) => _items.Where(predicate);
}
