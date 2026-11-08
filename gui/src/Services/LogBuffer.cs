// LogBuffer.cs — 环形日志缓冲（迭代器 / 索引器 / 通知 / 线程安全）
#nullable enable

namespace WsDoctorGui.Services;

public sealed record LogEntry(DateTime Timestamp, LogLevel Level, string Message)
{
    public string DisplayText => $"[{Timestamp:HH:mm:ss}] {Level,-5} {Message}";
}

/// <summary>线程安全的环形日志缓冲：固定容量、索引器、迭代器、事件。</summary>
public sealed class LogBuffer : INotifyPropertyChanged
{
    private readonly LogEntry[] _entries;
    private readonly object _gate = new();
    private int _start;
    private int _count;
    private long _totalAdded;

    public LogBuffer(int capacity = 500)
    {
        if (capacity <= 0) { throw new ArgumentOutOfRangeException(nameof(capacity)); }
        _entries = new LogEntry[capacity];
    }

    public int Capacity => _entries.Length;
    public int Count { get { lock (_gate) { return _count; } } }
    public long TotalAdded { get { lock (_gate) { return _totalAdded; } } }

    public event PropertyChangedEventHandler? PropertyChanged;
    public event EventHandler<LogEntry>? EntryAdded;

    /// <summary>索引器：0 = 最旧，Count-1 = 最新。</summary>
    public LogEntry this[int index]
    {
        get
        {
            lock (_gate)
            {
                if (index < 0 || index >= _count) { throw new IndexOutOfRangeException(nameof(index)); }
                return _entries[(_start + index) % Capacity];
            }
        }
    }

    public void Add(LogLevel level, string message)
    {
        var entry = new LogEntry(DateTime.Now, level, message);
        lock (_gate)
        {
            if (_count < Capacity)
            {
                _entries[(_start + _count) % Capacity] = entry;
                _count++;
            }
            else
            {
                _entries[_start] = entry;
                _start = (_start + 1) % Capacity;
            }
            _totalAdded++;
        }
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(Count)));
        EntryAdded?.Invoke(this, entry);
    }

    public void Info(string message) => Add(LogLevel.Info, message);
    public void Warn(string message) => Add(LogLevel.Warn, message);
    public void Error(string message) => Add(LogLevel.Error, message);

    public void Clear()
    {
        lock (_gate)
        {
            Array.Clear(_entries, 0, _entries.Length);
            _start = 0;
            _count = 0;
        }
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(Count)));
    }

    public List<LogEntry> Snapshot()
    {
        lock (_gate)
        {
            var list = new List<LogEntry>(_count);
            for (var i = 0; i < _count; i++)
            {
                list.Add(_entries[(_start + i) % Capacity]);
            }
            return list;
        }
    }

    /// <summary>迭代器（yield return）。</summary>
    public IEnumerable<LogEntry> Enumerate()
    {
        var snapshot = Snapshot();
        foreach (var entry in snapshot)
        {
            yield return entry;
        }
    }

    /// <summary>最近 n 条（LINQ TakeLast 的等价实现）。</summary>
    public IEnumerable<LogEntry> Tail(int count)
    {
        var snapshot = Snapshot();
        var skip = Math.Max(0, snapshot.Count - count);
        for (var i = skip; i < snapshot.Count; i++)
        {
            yield return snapshot[i];
        }
    }
}
