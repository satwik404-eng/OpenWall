namespace OpenWall.Windows;

public static class VideoQualityPolicy {
    public static readonly int[] FrameRates = [24, 60, 120];
    public static int[] Options(int width, int height) {
        int edge = Math.Min(width, height);
        int[] levels = [1080, 1440, 2160];
        var available = levels.Where(n => n <= edge);
        return levels.Contains(edge) ? available.ToArray() : available.Prepend(0).ToArray();
    }
    public static bool NeedsCopy(Wallpaper item, int height) => height > 0 && height < Math.Min(item.PixelWidth, item.PixelHeight);
    public static string CopyName(string id, int height) {
        if (!Guid.TryParse(id, out _) || !new[] {1080, 1440, 2160}.Contains(height)) throw new ArgumentException("Invalid video quality.");
        return id + "-" + height + ".mp4";
    }
}
