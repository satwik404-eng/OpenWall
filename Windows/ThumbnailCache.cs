namespace OpenWall.Windows;

internal sealed class ThumbnailCache(string root) {
    public const int MaxBytes = 256 * 1024;
    private string? FileFor(string id) => Guid.TryParseExact(id, "N", out _) ? Path.Combine(root, id + ".jpg") : null;
    public string? Name(string id) {
        if (FileFor(id) is not { } path) return null;
        try {
            using var stream = File.OpenRead(path);
            if (stream.Length < 4 || stream.Length > MaxBytes || stream.ReadByte() != 0xff || stream.ReadByte() != 0xd8) return null;
            stream.Seek(-2, SeekOrigin.End);
            return stream.ReadByte() == 0xff && stream.ReadByte() == 0xd9 ? Path.GetFileName(path) : null;
        } catch (IOException) { return null; } catch (UnauthorizedAccessException) { return null; }
    }
    public string Revision(string id) => FileFor(id) is { } path ? File.GetLastWriteTimeUtc(path).Ticks.ToString() : "0";
    public bool Store(string id, string encoded) {
        var path = FileFor(id);
        if (path is null || encoded.Length > (MaxBytes + 2) / 3 * 4) return false;
        byte[] bytes;
        try { bytes = Convert.FromBase64String(encoded); } catch (FormatException) { return false; }
        if (bytes.Length < 4 || bytes.Length > MaxBytes || bytes[0] != 0xff || bytes[1] != 0xd8
            || bytes[^2] != 0xff || bytes[^1] != 0xd9) return false;
        Directory.CreateDirectory(root);
        var temp = path + ".tmp";
        try { File.WriteAllBytes(temp, bytes); File.Move(temp, path, true); }
        finally { if (File.Exists(temp)) File.Delete(temp); }
        return true;
    }
    public void Remove(string id) { if (FileFor(id) is { } path && File.Exists(path)) File.Delete(path); }
    public void Prune(IEnumerable<string> ids) {
        if (!Directory.Exists(root)) return;
        var keep = ids.Select(FileFor).Where(p => p is not null).ToHashSet();
        foreach (var path in Directory.EnumerateFiles(root))
            if ((path.EndsWith(".jpg") || path.EndsWith(".jpg.tmp")) && !keep.Contains(path)) File.Delete(path);
    }
}
