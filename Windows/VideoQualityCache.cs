using global::Windows.Storage;
using global::Windows.Media.MediaProperties;
using global::Windows.Media.Transcoding;

namespace OpenWall.Windows;

internal sealed class VideoQualityCache(string root) {
    private readonly SemaphoreSlim encoder = new(1, 1);
    public const long MaximumFileBytes = 512L * 1024 * 1024;
    public const long MaximumBytes = 2L * 1024 * 1024 * 1024;
    public string? CachedName(Wallpaper item, int height) {
        if (!VideoQualityPolicy.NeedsCopy(item, height)) return null;
        var name = VideoQualityPolicy.CopyName(item.Id, height);
        return File.Exists(Path.Combine(root, name)) ? name : null;
    }
    public static async Task<Wallpaper> Probe(Wallpaper item, string media) {
        if (item.Filename is null || item.PixelWidth > 0 && item.PixelHeight > 0) return item;
        var file = await StorageFile.GetFileFromPathAsync(Path.Combine(media, item.Filename));
        var properties = await file.Properties.GetVideoPropertiesAsync();
        return item with { PixelWidth = (int)properties.Width, PixelHeight = (int)properties.Height };
    }
    public async Task Prepare(Wallpaper item, int height, string media, Func<HashSet<string>> protectedFiles, CancellationToken cancellation) {
        await encoder.WaitAsync(cancellation);
        string? temporary = null;
        try {
            cancellation.ThrowIfCancellationRequested();
            if (!VideoQualityPolicy.NeedsCopy(item, height) || CachedName(item, height) is not null) return;
            if (!VideoQualityPolicy.Options(item.PixelWidth, item.PixelHeight).Contains(height)) throw new ArgumentException("Unsupported quality.");
            Directory.CreateDirectory(root);
            foreach (var stale in Directory.GetFiles(root, "*.tmp.mp4")) { try { File.Delete(stale); } catch (IOException) { } }
            var input = await StorageFile.GetFileFromPathAsync(Path.Combine(media, item.Filename!));
            var properties = await input.Properties.GetVideoPropertiesAsync();
            var profile = await MediaEncodingProfile.CreateFromFileAsync(input);
            double scale = Math.Min(1, (double)height / Math.Min(profile.Video.Width, profile.Video.Height));
            profile.Video.Width = Math.Max(2, (uint)(profile.Video.Width * scale / 2) * 2);
            profile.Video.Height = Math.Max(2, (uint)(profile.Video.Height * scale / 2) * 2);
            profile.Video.Subtype = MediaEncodingSubtypes.H264;
            profile.Video.Bitrate = 8_000_000;
            profile.Audio = null;
            profile.Container = MediaEncodingProfile.CreateMp4(VideoEncodingQuality.Auto).Container;
            if (properties.Duration.TotalSeconds * 1_000_000 > MaximumFileBytes)
                throw new InvalidOperationException("This video is too long for a cached quality copy. Use Original quality.");
            temporary = Path.Combine(root, Guid.NewGuid().ToString("N") + ".tmp.mp4");
            using (File.Create(temporary)) { }
            var output = await StorageFile.GetFileFromPathAsync(temporary);
            var transcoder = new MediaTranscoder { HardwareAccelerationEnabled = true, AlwaysReencode = true };
            var prepared = await transcoder.PrepareFileTranscodeAsync(input, output, profile);
            if (!prepared.CanTranscode) throw new InvalidOperationException("Windows cannot encode this video's quality copy: " + prepared.FailureReason);
            await prepared.TranscodeAsync().AsTask(cancellation);
            cancellation.ThrowIfCancellationRequested();
            long size = new FileInfo(temporary).Length;
            if (size <= 0 || size > MaximumFileBytes) throw new InvalidOperationException("The quality copy exceeds the 512 MB limit. Use Original quality.");
            var copies = new DirectoryInfo(root).GetFiles("*.mp4").Where(f => !f.Name.Contains(".tmp.")).OrderBy(f => f.LastWriteTimeUtc).ToArray();
            long total = size + copies.Sum(f => f.Length);
            var protect = protectedFiles();
            foreach (var file in copies.Where(f => !protect.Contains(f.Name))) {
                if (total <= MaximumBytes) break;
                long old = file.Length;
                try { file.Delete(); total -= old; } catch (IOException) { }
            }
            if (total > MaximumBytes) throw new InvalidOperationException("The 2 GB quality cache is in use. Stop another wallpaper or use Original quality.");
            File.Move(temporary, Path.Combine(root, VideoQualityPolicy.CopyName(item.Id, height)), true);
        } finally {
            if (temporary is not null) { try { File.Delete(temporary); } catch (IOException) { } }
            encoder.Release();
        }
    }
    public void CleanUnfinished() {
        if (!Directory.Exists(root)) return;
        foreach (var file in Directory.GetFiles(root, "*.tmp.mp4")) { try { File.Delete(file); } catch (IOException) { } catch (UnauthorizedAccessException) { } }
    }
    public void Remove(string id) {
        if (!Guid.TryParse(id, out _) || !Directory.Exists(root)) return;
        foreach (var file in Directory.GetFiles(root, id + "-*.mp4")) { try { File.Delete(file); } catch (IOException) { } }
    }
}
