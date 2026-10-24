using OpenWall.Windows;
var temp = Path.Combine(Path.GetTempPath(), "openwall-tests-" + Guid.NewGuid());
double clock = 0;
var file = Path.Combine(temp, "library.json");
var m = new PlaylistModel(file, () => clock);
void Check(bool test, string message) { if (!test) throw new Exception(message); Console.WriteLine("PASS " + message); }
string[] screens = ["main", "other"];
Check(PlaylistModel.Durations.SequenceEqual(new[] { 86400,21600,10800,3600,1800,300,0 }), "All seven requested durations");
Check(m.Wallpapers.Count() == 89 && m.Wallpapers.Select(w => w.Id).Distinct().Count() == 89, "89 unique original motion wallpapers");
m.Add("aurora"); m.Add("dusk"); m.Add("aurora");
Check(m.State.Playlist.Count == 2, "Playlist prevents duplicates");
var a = m.State.Playlist[0].Id; var b = m.State.Playlist[1].Id;
m.SetDuration(a, 300); m.SetDuration(b, 0); m.Apply("aurora", screens); m.Anchor(screens);
Check(m.State.Assignments.Values.All(id => id == "aurora"), "Click applies immediately to both displays");
clock = 100; m.SetPaused(true, screens); clock = 900; m.Tick(screens);
Check(m.State.Playback["main"].Remaining == 200, "Pause freezes countdown");
m.SetPaused(false, screens); clock = 1101; m.Tick(screens);
Check(m.State.Assignments["main"] == "dusk" && m.State.Playback["main"].Remaining == null, "Expiry advances to Forever");
clock = 999999; m.Tick(screens); Check(m.State.Assignments["main"] == "dusk", "Forever never advances automatically");
m.Next("main"); Check(m.State.Assignments["main"] == "aurora", "Next wraps in order");
m.Move(b, -1); Check(m.State.Playlist[0].Id == b, "Reordering updates playlist");
m.Apply("ember", ["main"]); Check(!m.State.Playback.ContainsKey("main") && m.State.Playback.ContainsKey("other"), "Click outside playlist stops rotation only on target display");
m.RemoveEntry(b); Check(m.State.Assignments["other"] == "aurora", "Removing active entry advances to next");
m.Apply("aurora", ["main"]); m.Anchor(screens); clock += 15; m.Checkpoint(); m.Save();
var saved = new PlaylistModel(file); Check(saved.State.Playback["main"].Remaining == 285, "Remaining time persists");
m.SetDuration(a, 0); Check(m.State.Playback["main"].Remaining == null, "Duration changes affect active playback");
try { m.SetDuration(a, 123); throw new Exception("Invalid duration accepted"); } catch (InvalidOperationException) { Console.WriteLine("PASS Invalid durations rejected"); }
var display = new ScreenRect(0, 0, 1920, 1080);
bool Full(ScreenRect rect, string cls = "VideoPlayer", bool own = false, bool visible = true,
    bool minimized = false, bool cloaked = false, bool caption = false, ScreenRect? monitor = null)
    => FullScreenPolicy.ShouldPause(rect, monitor ?? display, cls, own, visible, minimized, cloaked, caption);
Check(!Full(new(200, 100, 1200, 800)), "Ordinary window keeps wallpaper playing");
Check(!Full(new(0, 30, 1920, 1040), caption: true), "Maximized client with visible taskbar keeps playing");
Check(!Full(display, caption: true), "Captioned maximized window with auto-hidden taskbar keeps playing");
Check(!Full(display, own: true), "OpenWall's own display-sized window cannot pause itself");
foreach (var cls in new[] { "Progman", "WorkerW", "SHELLDLL_DefView", "Shell_TrayWnd", "Shell_SecondaryTrayWnd" })
    Check(!Full(display, cls), "Desktop/shell window is ignored: " + cls);
Check(!Full(display, visible: false) && !Full(display, minimized: true) && !Full(display, cloaked: true), "Hidden, minimized and other-desktop windows are ignored");
Check(Full(display), "Borderless full-screen video/game pauses playback");
Check(Full(new(1, 1, 1919, 1079)), "Two-pixel full-screen tolerance");
Check(!Full(new(0, 0, 1920, 1040)), "Borderless work-area window is not full screen");
Check(Full(new(-1920, -1080, 0, 0), monitor: new(-1920, -1080, 0, 0)), "Full screen works on a display above and left of main");
Check(!Full(new(0, 0, 0, 0)) && !Full(display, monitor: new(0, 0, 0, 0)), "Invalid rectangles do not pause");
var cacheRoot = Path.Combine(temp, "Thumbnails");
var cache = new ThumbnailCache(cacheRoot);
var videoId = Guid.NewGuid().ToString("N");
var staleId = Guid.NewGuid().ToString("N");
var jpegEnvelope = Convert.ToBase64String(new byte[] { 0xff, 0xd8, 1, 2, 3, 0xff, 0xd9 });
Check(cache.Store(videoId, jpegEnvelope) && cache.Name(videoId) == videoId + ".jpg", "Thumbnail cache writes an imported video's JPEG payload");
Check(new ThumbnailCache(cacheRoot).Name(videoId) is not null, "Thumbnail cache survives restart without re-decoding");
File.WriteAllText(Path.Combine(cacheRoot, videoId + ".jpg"), "damaged cached preview");
Check(cache.Name(videoId) is null, "Damaged existing previews are marked for regeneration");
cache.Store(videoId, jpegEnvelope);
Check(!cache.Store("../outside", jpegEnvelope) && !cache.Store(videoId, "invalid")
    && !cache.Store(videoId, Convert.ToBase64String(new byte[ThumbnailCache.MaxBytes + 1])), "Malformed, oversized and unsafe thumbnail writes rejected");
cache.Store(staleId, jpegEnvelope);
File.WriteAllText(Path.Combine(cacheRoot, staleId + ".jpg.tmp"), "unfinished");
cache.Prune([videoId]);
Check(Directory.GetFiles(cacheRoot).Length == 1 && cache.Name(videoId) is not null, "Cache prunes obsolete previews and interrupted writes");
cache.Remove(videoId);
Check(cache.Name(videoId) is null, "Removing a video removes its preview");
Directory.Delete(temp, true);
Console.WriteLine("All Windows playlist, fullscreen and thumbnail-cache checks passed.");
