using System.Text.Json;

namespace OpenWall.Windows;

public record Wallpaper(string Id, string Name, string? Filename = null);
public record PlaylistEntry(string Id, string WallpaperId, int Duration = 3600);
public class PlaylistProgress {
    public string EntryId { get; set; } = "";
    public double? Remaining { get; set; }
}
public class LibraryState {
    public List<Wallpaper> Videos { get; set; } = [];
    public List<PlaylistEntry> Playlist { get; set; } = [];
    public Dictionary<string, string> Assignments { get; set; } = [];
    public Dictionary<string, PlaylistProgress> Playback { get; set; } = [];
    public bool ManualPause { get; set; }
    public bool PauseOnBattery { get; set; } = true;
    public bool PauseInFullScreen { get; set; } = true;
    public double Speed { get; set; } = 1;
}

public class PlaylistModel {
    public static readonly int[] Durations = [86400, 21600, 10800, 3600, 1800, 300, 0];
    public static readonly Wallpaper[] Presets = LoadPresets();
    private static Wallpaper[] LoadPresets() {
        using var catalog = JsonDocument.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "Assets", "motion-catalog.json")));
        return catalog.RootElement.GetProperty("items").EnumerateArray().Select(item =>
            new Wallpaper(item.GetProperty("id").GetString()!, item.GetProperty("name").GetString()!)).ToArray();
    }

    public static readonly JsonSerializerOptions Json = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase, WriteIndented = true };
    public LibraryState State { get; private set; } = new();
    public IEnumerable<Wallpaper> Wallpapers => Presets.Concat(State.Videos);
    public bool Paused { get; private set; }
    private readonly Dictionary<string, double> anchors = [];
    private readonly Func<double> clock;
    private readonly string file;
    public string? LoadError { get; private set; }

    public PlaylistModel(string file, Func<double>? clock = null) {
        this.file = file;
        this.clock = clock ?? (() => Environment.TickCount64 / 1000.0);
        if (File.Exists(file)) {
            try { State = JsonSerializer.Deserialize<LibraryState>(File.ReadAllText(file), Json) ?? new(); }
            catch (Exception error) { LoadError = "The saved library could not be read. " + error.Message; }
        }
        Paused = State.ManualPause;
    }
    public void Save() {
        Directory.CreateDirectory(Path.GetDirectoryName(file)!);
        var temp = file + ".tmp";
        File.WriteAllText(temp, JsonSerializer.Serialize(State, Json));
        File.Move(temp, file, true);
    }
    public void Checkpoint() {
        var now = clock();
        foreach (var (screen, since) in anchors) {
            if (State.Playback.TryGetValue(screen, out var progress) && progress.Remaining is double remaining)
                progress.Remaining = Math.Max(0, remaining - Math.Max(0, now - since));
        }
        anchors.Clear();
    }
    public void SetPaused(bool paused, IEnumerable<string> connected) {
        Checkpoint();
        Paused = paused;
        Anchor(connected);
    }
    public void Anchor(IEnumerable<string> connected) {
        if (Paused) return;
        foreach (var screen in connected)
            if (State.Playback.TryGetValue(screen, out var p) && p.Remaining.HasValue) anchors[screen] = clock();
    }
    public void Apply(string id, IEnumerable<string> displays) {
        Checkpoint();
        if (!Wallpapers.Any(w => w.Id == id)) throw new InvalidOperationException("Wallpaper not found.");
        foreach (var display in displays) {
            State.Assignments[display] = id;
            var entry = State.Playlist.FirstOrDefault(e => e.WallpaperId == id);
            if (entry is null) State.Playback.Remove(display);
            else State.Playback[display] = new() { EntryId = entry.Id, Remaining = entry.Duration == 0 ? null : entry.Duration };
        }
    }
    public void Add(string id) {
        if (Wallpapers.Any(w => w.Id == id) && !State.Playlist.Any(e => e.WallpaperId == id))
            State.Playlist.Add(new(Guid.NewGuid().ToString("N"), id));
    }
    public void SetDuration(string id, int duration) {
        if (!Durations.Contains(duration)) throw new InvalidOperationException("Unsupported duration.");
        Checkpoint();
        var index = State.Playlist.FindIndex(e => e.Id == id);
        if (index < 0) return;
        State.Playlist[index] = State.Playlist[index] with { Duration = duration };
        foreach (var progress in State.Playback.Values.Where(p => p.EntryId == id))
            progress.Remaining = duration == 0 ? null : duration;
    }
    public bool Tick(IEnumerable<string> connected) {
        Checkpoint();
        bool changed = false;
        if (!Paused) foreach (var screen in connected) {
            if (State.Playback.TryGetValue(screen, out var p) && p.Remaining is <= 0) {
                Next(screen); changed = true;
            }
        }
        Anchor(connected);
        return changed;
    }
    public void Next(string screen) {
        if (!State.Playback.TryGetValue(screen, out var current)) return;
        var index = State.Playlist.FindIndex(e => e.Id == current.EntryId);
        if (index < 0 || State.Playlist.Count == 0) { State.Playback.Remove(screen); return; }
        var next = State.Playlist[(index + 1) % State.Playlist.Count];
        State.Assignments[screen] = next.WallpaperId;
        State.Playback[screen] = new() { EntryId = next.Id, Remaining = next.Duration == 0 ? null : next.Duration };
    }
    public void Move(string entryId, int direction) {
        var index = State.Playlist.FindIndex(e => e.Id == entryId);
        var destination = index + Math.Sign(direction);
        if (index < 0 || destination < 0 || destination >= State.Playlist.Count) return;
        var entry = State.Playlist[index]; State.Playlist.RemoveAt(index); State.Playlist.Insert(destination, entry);
    }
    public void RemoveEntry(string entryId) {
        Checkpoint();
        var index = State.Playlist.FindIndex(e => e.Id == entryId);
        if (index < 0) return;
        var affected = State.Playback.Where(p => p.Value.EntryId == entryId).Select(p => p.Key).ToArray();
        State.Playlist.RemoveAt(index);
        foreach (var screen in affected) {
            if (State.Playlist.Count == 0) State.Playback.Remove(screen);
            else {
                var next = State.Playlist[index % State.Playlist.Count];
                State.Assignments[screen] = next.WallpaperId;
                State.Playback[screen] = new() { EntryId = next.Id, Remaining = next.Duration == 0 ? null : next.Duration };
            }
        }
    }
}
